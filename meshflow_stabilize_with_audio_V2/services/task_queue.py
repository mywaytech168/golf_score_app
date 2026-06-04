"""
任務隊列管理模塊

負責接收來自 C# Server 的處理任務，將其加入 Redis 隊列，
並按順序進行處理。支持分布式處理和任務持久化。
"""

from queue import Queue
from threading import Thread, Lock
import time
import json
import requests
from datetime import datetime
from pathlib import Path
import logging
import logging.handlers
import redis
from redis import ConnectionPool
import uuid
import threading
import numpy as np
import platform
import os

# 配置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# ============================================================================
# 跨平台路徑轉換工具（作法二：UNC → Linux 轉換，相容寫法）
# ============================================================================

def normalize_unc_path(path: str) -> str:
    """
    跨平台路徑轉換：將 Windows UNC 路徑轉換為 Linux 掛載點
    
    僅在 Linux 系統上執行轉換邏輯。
    如果在 Windows 上運行，直接返回原路徑。
    
    Args:
        path: 原始路徑（可能包含 UNC 路徑或本地路徑）
        
    Returns:
        轉換後的路徑（Linux 系統進行轉換，其他系統返回原值）
        
    Examples:
        # Linux 上：
        normalize_unc_path(r"\\10.1.1.101\TekSwing\videos\...")
        # 返回：/data/tekswing/videos/...
        
        # Windows 上：
        normalize_unc_path(r"\\10.1.1.101\TekSwing\videos\...")
        # 返回：\\10.1.1.101\\TekSwing\\videos\\...（不變）
    """
    if not isinstance(path, str):
        return path
    
    current_os = platform.system()
    
    # ✅ 只在 Linux 系統上執行轉換
    if current_os == "Linux":
        # 處理 Windows UNC 路徑格式：\\10.1.1.101\TekSwing\...
        if "\\\\10.1.1.101\\TekSwing" in path or "\\10.1.1.101\\TekSwing" in path:
            # 轉換 UNC 路徑為 Linux 路徑
            converted = path.replace(
                "\\\\10.1.1.101\\TekSwing",
                "/data/tekswing"
            ).replace(
                "\\10.1.1.101\\TekSwing",
                "/data/tekswing"
            ).replace("\\", "/")  # 將所有反斜杠轉換為正斜杠
            logger.debug(f"🔄 路徑轉換 (UNC→Linux): {path} → {converted}")
            return converted
    # 其他作業系統（Windows, macOS等）直接返回原值
    
    return path


def apply_path_normalization(task_data: dict) -> dict:
    """
    批量應用路徑轉換到任務數據
    
    自動偵測並轉換任務數據中的所有路徑字段。
    
    Args:
        task_data: 任務數據字典
        
    Returns:
        轉換後的任務數據
    """
    # 需要轉換的路徑相關字段名
    path_fields = [
        "input_path",
        "output_path",
        "input_dir",
        "output_dir",
        "video_path",
        "data_dir",
        "workspace",
    ]
    
    converted_data = task_data.copy()
    
    for field in path_fields:
        if field in converted_data and isinstance(converted_data[field], str):
            original = converted_data[field]
            converted = normalize_unc_path(original)
            if original != converted:
                logger.info(f"📝 轉換字段 '{field}': {original} → {converted}")
                converted_data[field] = converted
    
    return converted_data


# ✅ 自定義 JSON Encoder 以支持 numpy 數據類型
class NumpyEncoder(json.JSONEncoder):
    """支持 numpy 數據類型的 JSON Encoder"""
    def default(self, obj):
        try:
            if isinstance(obj, np.integer):
                return int(obj)
            elif isinstance(obj, np.floating):
                return float(obj)
            elif isinstance(obj, np.ndarray):
                return obj.tolist()
            elif isinstance(obj, np.bool_):
                return bool(obj)
            elif isinstance(obj, (datetime, Path)):
                return str(obj)
        except Exception:
            pass
        return super().default(obj)


class TaskQueue:
    """
    任務隊列管理類 - 使用 Redis 作為後端存儲
    支持分布式任務處理和持久化
    """
    def __init__(
        self,
        csharp_server_url: str,
        redis_host: str = "10.1.1.80",
        redis_port: int = 6379,
        redis_db: int = 0,
        redis_password: str = None,
        max_workers: int = 1
    ):
        """
        初始化任務隊列
        
        Args:
            csharp_server_url: C# Server 的 URL
            redis_host: Redis 服務器主機
            redis_port: Redis 服務器端口
            redis_db: Redis 數據庫編號
            redis_password: Redis 密碼（可選）
            max_workers: 最大並行工作進程數（默認 1）
        """
        self.csharp_server_url = csharp_server_url
        self.max_workers = max_workers
        self.processing_lock = Lock()
        self.is_processing = False
        self.current_task_id = None
        self.scheduler_thread = None
        self.is_running = False
        self.worker_id = str(uuid.uuid4())[:8]  # 每個 worker 的唯一 ID
        
        # ✅ 改進：使用連接池和自動重連
        try:
            self.connection_pool = ConnectionPool(
                host=redis_host,
                port=redis_port,
                db=redis_db,
                password=redis_password,
                max_connections=10,
                socket_connect_timeout=5,
                socket_keepalive=True,
                socket_keepalive_options={1: 1}  # TCP Keep-Alive
            )
            self.redis_client = redis.Redis(connection_pool=self.connection_pool)
            # 測試連接
            self.redis_client.ping()
            logger.info(f"✅ Redis 連接成功 ({redis_host}:{redis_port}) - 使用連接池")
        except Exception as e:
            logger.error(f"❌ Redis 連接失敗: {str(e)}")
            raise
        
        # Redis 鍵前綴
        self.QUEUE_KEY = "task_queue:pending"           # 待處理隊列
        self.PROCESSING_KEY = "task_queue:processing"   # 處理中隊列
        self.COMPLETED_KEY = "task_queue:completed"     # 已完成隊列
        self.FAILED_KEY = "task_queue:failed"           # 失敗隊列
        self.TASK_DATA_PREFIX = "task:"                 # 任務詳情前綴
        self.LOCK_PREFIX = "task_lock:"                 # 任務鎖前綴
        self.LOCK_TIMEOUT = 300                          # 鎖超時時間（秒）
        self.TASK_RETENTION = 86400                      # 任務保留時間（秒，默認1天）
        
        logger.info(f"✅ 任務隊列已初始化 (Worker ID: {self.worker_id}, Max Workers: {max_workers})")

    def _redis_safe_call(self, func, *args, max_retries=3, **kwargs):
        """
        ✅ 改進：帶重試的 Redis 調用（自動重連）
        
        Args:
            func: Redis 方法
            args: 位置參數
            max_retries: 最大重試次數
            kwargs: 關鍵字參數
            
        Returns:
            Redis 調用結果
        """
        for attempt in range(max_retries):
            try:
                return func(*args, **kwargs)
            except (redis.ConnectionError, redis.TimeoutError) as e:
                logger.warning(f"⚠️  Redis 調用失敗 (嘗試 {attempt+1}/{max_retries}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(1)  # 等待後重試
                else:
                    logger.error(f"❌ Redis 調用失敗，已放棄 (經過 {max_retries} 次嘗試)")
                    raise

    def add_task(self, queue_item_id: str, video_id: str, input_dir: str = None):
        """
        添加任務到隊列
        
        Args:
            queue_item_id: 隊列項目 ID
            video_id: 視頻 ID
            input_dir: 輸入目錄路徑（可選）
        """
        try:
            # ✅ 應用跨平台路徑轉換（作法二）
            if input_dir:
                input_dir = normalize_unc_path(input_dir)
                logger.info(f"📂 輸入目錄已轉換: {input_dir}")
            
            task = {
                'queueItemId': queue_item_id,
                'videoId': video_id,
                'inputDir': input_dir,
                'receivedAt': datetime.now().isoformat(),
                'status': 'queued',
                'workerId': None,
                'attempts': 0
            }
            
            # ✅ 改進：使用安全的 Redis 調用
            task_key = f"{self.TASK_DATA_PREFIX}{queue_item_id}"
            
            # 逐個設置任務數據（簡化版，移除 workerId 和 attempts）
            self.redis_client.hset(task_key, 'queueItemId', queue_item_id)
            self.redis_client.hset(task_key, 'videoId', video_id)
            self.redis_client.hset(task_key, 'inputDir', input_dir or '')
            self.redis_client.hset(task_key, 'receivedAt', task['receivedAt'])
            self.redis_client.hset(task_key, 'status', 'queued')
            # 設置任務數據過期時間
            self._redis_safe_call(
                self.redis_client.expire,
                task_key,
                self.TASK_RETENTION
            )
            
            # 將任務 ID 添加到待處理隊列
            self._redis_safe_call(
                self.redis_client.rpush,
                self.QUEUE_KEY,
                queue_item_id
            )
            
            logger.info(f"📋 添加任務到隊列: {queue_item_id} (VideoId: {video_id}, InputDir: {input_dir})")
            
        except Exception as e:
            logger.error(f"❌ 添加任務時出錯: {str(e)}")
            raise

    def start_scheduler(self):
        """
        啟動排程器線程
        每秒檢查一次隊列，取出一個任務進行處理
        """
        if self.is_running:
            logger.warning("⚠️  排程器已在運行")
            return

        self.is_running = True
        self.scheduler_thread = Thread(target=self._scheduler_loop, daemon=True)
        self.scheduler_thread.start()
        logger.info(f"🚀 任務隊列排程器已啟動 (Worker ID: {self.worker_id})")

    def stop_scheduler(self):
        """
        停止排程器
        """
        self.is_running = False
        if self.scheduler_thread:
            self.scheduler_thread.join(timeout=5)
        logger.info("🛑 任務隊列排程器已停止")

    def _scheduler_loop(self):
        """
        排程器主循環
        每秒檢查一次隊列
        """
        while self.is_running:
            time.sleep(1)
            
            if not self.is_processing:
                try:
                    # ✅ 改進：使用安全的 Redis 調用，帶自動重連
                    queue_item_id = self._redis_safe_call(
                        self.redis_client.lpop,
                        self.QUEUE_KEY
                    )
                    
                    if queue_item_id:
                        # ✅ 改進：解碼 Redis 返回的 bytes
                        if isinstance(queue_item_id, bytes):
                            queue_item_id = queue_item_id.decode('utf-8')
                        
                        self._process_task(queue_item_id)
                except redis.ConnectionError as e:
                    logger.error(f"❌ Redis 連接失敗，排程器暫停: {str(e)}")
                    time.sleep(5)  # 連接失敗時延長等待
                except Exception as e:
                    logger.error(f"❌ 排程器循環出錯: {str(e)}")

    def _setup_task_logger(self, queue_item_id: str, input_dir: str) -> logging.Logger:
        """
        為任務建立獨立的 logger
        
        Args:
            queue_item_id: 隊列項目 ID
            input_dir: 輸入目錄
            
        Returns:
            logger 實例
        """
        task_logger = logging.getLogger(f"task_{queue_item_id}")
        task_logger.setLevel(logging.INFO)
        
        # 清除既有的處理器
        task_logger.handlers.clear()
        
        # 如果提供了 input_dir，建立日誌檔案
        if input_dir:
            try:
                input_path = Path(input_dir)
                input_path.mkdir(parents=True, exist_ok=True)
                
                # 統一使用 processing.log
                log_file = input_path / "processing.log"
                
                # 建立檔案處理器
                file_handler = logging.FileHandler(str(log_file), encoding='utf-8')
                file_handler.setLevel(logging.INFO)
                
                # 設定日誌格式
                formatter = logging.Formatter(
                    '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S'
                )
                file_handler.setFormatter(formatter)
                task_logger.addHandler(file_handler)
                
                logger.info(f"📝 任務日誌檔案: {log_file}")
            except Exception as e:
                logger.warning(f"⚠️  無法建立任務日誌檔案: {str(e)}")
        
        return task_logger

    def _process_task(self, queue_item_id: str):
        """
        處理單個任務
        
        Args:
            queue_item_id: 隊列項目 ID
        """
        with self.processing_lock:
            self.is_processing = True
            self.current_task_id = queue_item_id

        task_logger = None
        start_time = time.time()
        try:
            # 獲取任務詳情
            task_key = f"{self.TASK_DATA_PREFIX}{queue_item_id}"
            task_data = self._redis_safe_call(
                self.redis_client.hgetall,
                task_key
            )
            
            # ✅ 改進：解碼 Redis 返回的 bytes
            if task_data:
                task_data = {
                    (k.decode('utf-8') if isinstance(k, bytes) else k): 
                    (v.decode('utf-8') if isinstance(v, bytes) else v)
                    for k, v in task_data.items()
                }
            
            if not task_data:
                logger.warning(f"⚠️  任務未找到: {queue_item_id}")
                return
            
            video_id = task_data.get('videoId')
            input_dir = task_data.get('inputDir', '')
            
            # 建立任務特定的 logger
            task_logger = self._setup_task_logger(queue_item_id, input_dir)
            task_logger.info(f"⏳ 開始處理任務: {queue_item_id} (VideoId: {video_id})")
            logger.info(f"⏳ 開始處理任務: {queue_item_id} (VideoId: {video_id})")
            
            # 更新任務狀態為處理中（簡化版，移除 workerId）
            self.redis_client.hset(task_key, 'status', 'processing')
            self.redis_client.hset(task_key, 'startedAt', datetime.now().isoformat())
            
            # ✅ 改進：立即通知 C# 端任務已開始處理
            self.send_processing_status(
                queue_item_id=queue_item_id,
                progress_percent=0,
                processing_time=0
            )
            
            # 添加到處理中隊列
            self._redis_safe_call(
                self.redis_client.rpush,
                self.PROCESSING_KEY,
                queue_item_id
            )

            # 這裡應該調用實際的處理邏輯
            result = self._run_processing_pipeline(
                queue_item_id=queue_item_id,
                video_id=video_id,
                input_dir=input_dir,
                task_logger=task_logger
            )

            # 計算處理時間
            processing_time = time.time() - start_time
            task_logger.info(f"✅ 任務處理完成: {queue_item_id} (耗時: {processing_time:.2f}秒)")
            logger.info(f"✅ 任務處理完成: {queue_item_id} (耗時: {processing_time:.2f}秒)")

            # 發送結果回 C# Server
            if result['success']:
                self.send_completed_status(
                    queue_item_id=queue_item_id,
                    result_data=result.get('data'),
                    processing_time=processing_time
                )
            else:
                self.send_failed_status(
                    queue_item_id=queue_item_id,
                    error=result.get('error'),
                    processing_time=processing_time
                )

        except Exception as e:
            logger.error(f"❌ 處理任務時出錯: {queue_item_id}", exc_info=True)
            if task_logger:
                task_logger.error(f"❌ 處理任務時出錯", exc_info=True)
            processing_time = time.time() - start_time
            self.send_failed_status(
                queue_item_id=queue_item_id,
                error=str(e),
                processing_time=processing_time
            )
        finally:
            # 從處理中隊列移除
            self._redis_safe_call(
                self.redis_client.lrem,
                self.PROCESSING_KEY,
                1,
                queue_item_id
            )
            
            with self.processing_lock:
                self.is_processing = False
                self.current_task_id = None

    def _run_processing_pipeline(
        self,
        queue_item_id: str,
        video_id: str,
        input_dir: str = None,
        task_logger = None,
        timeout_seconds: int = 1800  # 默認 30 分鐘超時
    ) -> dict:
        """
        執行實際的處理流程（帶超時保護）
        
        Args:
            queue_item_id: 隊列項目 ID
            video_id: 視頻 ID
            input_dir: 輸入目錄
            task_logger: 任務 logger
            timeout_seconds: 超時時間（秒），默認 1800 秒 (30 分鐘)
            
        Returns:
            包含處理結果的字典
        """
        if task_logger is None:
            task_logger = self._setup_task_logger(queue_item_id, input_dir)
        
        # ✅ 改進：添加超時計時器
        timeout_timer = None
        timeout_event = threading.Event()
        
        def timeout_handler():
            """超時時的處理"""
            timeout_event.set()
            logger.error(f"❌ 任務超時 ({timeout_seconds}s): {queue_item_id}")
            task_logger.error(f"❌ 任務超時 ({timeout_seconds}s): {queue_item_id}")
        
        try:
            # 啟動超時計時器
            timeout_timer = threading.Timer(timeout_seconds, timeout_handler)
            timeout_timer.daemon = True
            timeout_timer.start()
            
            # TODO: 這裡應該集成實際的處理邏輯
            # 例如：
            # from functions.meshflow_stabilization import run_meshflow_stabilization
            # from functions.audio_analysis import run_audio_analysis
            # ... 等等
            
            task_logger.info(f"🔄 執行處理流程 (超時: {timeout_seconds}s)...")
            task_logger.info(f"   Queue Item ID: {queue_item_id}")
            task_logger.info(f"   Video ID: {video_id}")
            task_logger.info(f"   Input Dir: {input_dir}")
            
            # 驗證輸入目錄
            if not input_dir:
                raise ValueError("input_dir 不能為空")
            
            input_path = Path(input_dir)
            if not input_path.exists():
                raise ValueError(f"輸入目錄不存在: {input_dir}")
            
            result_data = {
                'queueItemId': queue_item_id,
                'videoId': video_id,
                'inputDir': input_dir,
                'processedAt': datetime.now().isoformat(),
                'steps': {}
            }
            
            # ✅ 步驟 1: Stabilization (MeshFlow 穩定化)
            try:
                task_logger.info(f"🎬 步驟 1/5: 執行 Stabilization...")
                from functions.meshflow_stabilization import run_meshflow_stabilization, MeshFlowConfig
                
                step_start = datetime.now()
                # MeshFlowConfig 需要 input_path 和 output_path
                
                # ✅ 改進：添加詳細的路徑調試信息
                task_logger.info(f"   查找 MP4 檔案...")
                task_logger.info(f"   Input Dir: {input_path}")
                task_logger.info(f"   Input Dir 存在: {input_path.exists()}")
                task_logger.info(f"   Input Dir 是目錄: {input_path.is_dir()}")
                
                # 列出目錄中的所有檔案
                if input_path.exists() and input_path.is_dir():
                    all_files = list(input_path.iterdir())
                    task_logger.info(f"   目錄中的檔案數: {len(all_files)}")
                    for file in all_files[:10]:  # 只顯示前 10 個檔案
                        task_logger.info(f"      - {file.name}")
                
                video_files = list(input_path.glob("*.mp4"))
                task_logger.info(f"   找到的 MP4 檔案數: {len(video_files)}")
                for vf in video_files:
                    task_logger.info(f"      - {vf.name}")
                
                if not video_files:
                    raise ValueError(f"找不到 MP4 影片檔案 (目錄: {input_path})")
                
                config = MeshFlowConfig(
                    input_path=str(input_path / f"clip.mp4"),
                    output_path=str(input_path / f"clip_stabilized.mp4")
                )
                stabilization_result = run_meshflow_stabilization(config=config)
                step_duration = (datetime.now() - step_start).total_seconds()
                
                result_data['steps']['stabilization'] = {
                    'status': 'completed',
                    'duration': step_duration,
                    'result': stabilization_result
                }
                task_logger.info(f"✅ Stabilization 完成 ({step_duration:.1f}s)")
            except Exception as e:
                task_logger.error(f"❌ Stabilization 失敗: {str(e)}", exc_info=True)
                result_data['steps']['stabilization'] = {'status': 'failed', 'error': str(e)}
            
            # ✅ 步驟 2: Audio Analysis
            try:
                task_logger.info(f"🎵 步驟 2/5: 執行 Audio Analysis...")
                from functions.audio_analysis import run_audio_analysis, AudioAnalysisConfig
                
                step_start = datetime.now()
                
                config = AudioAnalysisConfig(
                    video_path=str(input_path / f"clip_stabilized.mp4"),
                    output_dir=str(input_path)
                )
                audio_analysis_result = run_audio_analysis(config=config)
                step_duration = (datetime.now() - step_start).total_seconds()
                
                result_data['steps']['audio_analysis'] = {
                    'status': 'completed',
                    'duration': step_duration,
                    'result': audio_analysis_result
                }
                task_logger.info(f"✅ Audio Analysis 完成 ({step_duration:.1f}s)")
            except Exception as e:
                task_logger.error(f"❌ Audio Analysis 失敗: {str(e)}", exc_info=True)
                result_data['steps']['audio_analysis'] = {'status': 'failed', 'error': str(e)}
            
            # ✅ 步驟 3: Audio Scoring
            try:
                task_logger.info(f"📊 步驟 3/5: 執行 Audio Scoring...")
                from functions.audio_scoring import run_audio_scoring, AudioScoringConfig
                
                step_start = datetime.now()
                config = AudioScoringConfig(
                    csv_folder=str(input_path),
                    video_root=str(input_path)
                )
                audio_scoring_result = run_audio_scoring(config=config)
                step_duration = (datetime.now() - step_start).total_seconds()
                
                # 🎯 提取 audio_crispness 和 good_shot
                audio_crispness = None
                good_shot = None
                
                if isinstance(audio_scoring_result, dict):
                    audio_crispness = audio_scoring_result.get('audio_crispness')
                    good_shot = audio_scoring_result.get('good_shot')
                    
                    result_data['steps']['audio_scoring'] = {
                        'status': 'completed',
                        'duration': step_duration,
                        'result': 'DataFrame'  # 简化显示
                    }
                    
                    # 将提取的值添加到 audio_analysis 中供回调使用
                    if 'audio_analysis' not in result_data:
                        result_data['audio_analysis'] = {}
                    
                    result_data['audio_analysis']['audio_crispness'] = audio_crispness
                    result_data['audio_analysis']['good_shot'] = good_shot
                    
                    task_logger.info(f"✅ Audio Scoring 完成 ({step_duration:.1f}s)")
                    task_logger.info(f"   🎵 audio_crispness: {audio_crispness}")
                    task_logger.info(f"   ⭐ good_shot: {good_shot}")
                else:
                    result_data['steps']['audio_scoring'] = {
                        'status': 'completed',
                        'duration': step_duration,
                        'result': str(audio_scoring_result) if audio_scoring_result is not None else 'No result'
                    }
                    task_logger.info(f"✅ Audio Scoring 完成 ({step_duration:.1f}s)")
            except Exception as e:
                task_logger.error(f"❌ Audio Scoring 失敗: {str(e)}", exc_info=True)
                result_data['steps']['audio_scoring'] = {'status': 'failed', 'error': str(e)}
            
            # ✅ 步驟 4: OpenPose Analysis
            try:
                task_logger.info(f"🤖 步驟 4/5: 執行 OpenPose Analysis...")
                from functions.openpose_analysis import run_openpose_analysis, MediaPoseConfig
                
                step_start = datetime.now()
                config = MediaPoseConfig(
                    video_path=str(input_path / "clip_stabilized.mp4")
                )
                openpose_result = run_openpose_analysis(config=config)
                step_duration = (datetime.now() - step_start).total_seconds()
                
                result_data['steps']['openpose_analysis'] = {
                    'status': 'completed',
                    'duration': step_duration,
                    'result': str(openpose_result) if openpose_result is not None else 'No result'
                }
                task_logger.info(f"✅ OpenPose Analysis 完成 ({step_duration:.1f}s)")
            except Exception as e:
                task_logger.error(f"❌ OpenPose Analysis 失敗: {str(e)}", exc_info=True)
                result_data['steps']['openpose_analysis'] = {'status': 'failed', 'error': str(e)}
            
            # ✅ 步驟 5: Ball Tracking
            try:
                task_logger.info(f"⚽ 步驟 5/5: 執行 Ball Tracking...")
                from functions.ball_tracking import run_ball_tracking, BallTrackingConfig
                
                step_start = datetime.now()
                # BallTrackingConfig 可以在 batch_mode 或 single_video_mode
                output_tracking_dir = input_path / "ball_tracking"
                config = BallTrackingConfig(
                    batch_mode=False,
                    video_path=str(input_path / "clip_stabilized_pose_phase.mp4"),
                    output_dir=str(input_path),
                    show_main=False,  # 禁用主窗口
                    show_debug_roi=False,  # 禁用调试窗口
                )
                # 禁用检测调试显示
                config.detect_cfg_base["show_debug"] = False
                ball_tracking_result = run_ball_tracking(config=config)
                step_duration = (datetime.now() - step_start).total_seconds()
                
                result_data['steps']['ball_tracking'] = {
                    'status': 'completed',
                    'duration': step_duration,
                    'result': str(ball_tracking_result) if ball_tracking_result is not None else 'No result'
                }
                task_logger.info(f"✅ Ball Tracking 完成 ({step_duration:.1f}s)")
            except Exception as e:
                task_logger.error(f"❌ Ball Tracking 失敗: {str(e)}", exc_info=True)
                result_data['steps']['ball_tracking'] = {'status': 'failed', 'error': str(e)}
            
            # ✅ 改進：檢查是否已超時
            if timeout_event.is_set():
                return {
                    'success': False,
                    'error': f'任務超時 ({timeout_seconds}s)'
                }
            
            # 將結果追加到 processing.log
            if input_dir:
                log_file = Path(input_dir) / 'processing.log'
                with open(log_file, 'a', encoding='utf-8') as f:
                    f.write("\n" + "=" * 80 + "\n")
                    f.write(f"處理結果報告\n")
                    f.write("=" * 80 + "\n\n")
                    f.write(f"隊列項目 ID: {queue_item_id}\n")
                    f.write(f"視頻 ID: {video_id}\n")
                    f.write(f"處理時間: {result_data['processedAt']}\n\n")
                    
                    f.write("流程步驟:\n")
                    f.write("-" * 80 + "\n")
                    for step_name, step_data in result_data['steps'].items():
                        f.write(f"  {step_name}: {step_data['status']}\n")
                    
                    f.write("\n" + "=" * 80 + "\n")
                    f.write(f"完整結果 (JSON):\n")
                    f.write(json.dumps(result_data, indent=2, ensure_ascii=False, cls=NumpyEncoder))
                    f.write("\n" + "=" * 80 + "\n")
                
                task_logger.info(f"✅ 結果已追加到: {log_file}")
            
            return {
                'success': True,
                'data': result_data
            }
            
        except Exception as e:
            task_logger.error(f"❌ 執行流程時出錯: {str(e)}", exc_info=True)
            logger.error(f"❌ 執行流程時出錯: {str(e)}")
            
            # ✅ 改進：超時時返回超時錯誤
            if timeout_event.is_set():
                return {
                    'success': False,
                    'error': f'任務超時 ({timeout_seconds}s)'
                }
            
            return {
                'success': False,
                'error': str(e)
            }
        
        finally:
            # ✅ 改進：確保超時計時器被取消
            if timeout_timer is not None:
                timeout_timer.cancel()

    def _send_result_to_csharp(
        self,
        queue_item_id: str,
        success: bool = None,
        result_data: dict = None,
        error: str = None,
        processing_time: float = 0,
        status: str = None,
        progress_percent: int = None
    ):
        """
        發送處理結果回 C# Server (非同步，不阻塞主線程)
        
        Args:
            queue_item_id: 隊列項目 ID
            success: 是否成功（已棄用，改用 status）
            result_data: 結果數據
            error: 錯誤信息
            processing_time: 處理耗時
            status: 狀態 (processing/completed/failed) - 優先於 success
            progress_percent: 進度百分比 (0-100)
        """
        # ✅ 改進：在後台線程中非同步發送，不阻塞 _scheduler_loop
        send_thread = Thread(
            target=self._send_result_with_retry,
            args=(queue_item_id, success, result_data, error, processing_time, status, progress_percent),
            daemon=True
        )
        send_thread.start()
    
    def _send_result_with_retry(
        self,
        queue_item_id: str,
        success: bool,
        result_data: dict,
        error: str,
        processing_time: float,
        status: str,
        progress_percent: int,
        max_retries: int = 3
    ):
        """
        帶有重試機制的發送邏輯（在獨立線程中執行）
        
        Args:
            max_retries: 最大重試次數
        """
        try:
            callback_url = f"{self.csharp_server_url}/api/callback/processing-result"
            
            # 決定狀態
            if status is None:
                status = 'completed' if success else 'failed'
            
            payload = {
                'queueItemId': queue_item_id,
                'status': status,
                'resultData': result_data or {},
                'errorMessage': error,
                'processingDurationSeconds': processing_time
            }
            
            # ✅ 只在任務完成或失敗時才添加 completedAt
            if status in ('completed', 'failed'):
                payload['completedAt'] = datetime.utcnow().isoformat()
            
            # 如果是處理中狀態，添加進度信息
            if status == 'processing' and progress_percent is not None:
                payload['progressPercent'] = progress_percent
            
            logger.info(f"📤 發送結果回 C# Server (非同步): {callback_url}")
            logger.info(f"   QueueItemId: {queue_item_id}")
            logger.info(f"   Status: {status}")
            
            # 重試邏輯
            for attempt in range(max_retries):
                try:
                    # 使用 NumpyEncoder 序列化，避免 int64 序列化失敗
                    payload_json = json.dumps(payload, cls=NumpyEncoder)
                    response = requests.post(
                        callback_url,
                        data=payload_json,
                        headers={'Content-Type': 'application/json'},
                        timeout=10  # 縮短超時時間
                    )
                    
                    if response.status_code == 200:
                        logger.info(f"✅ 成功發送結果: {queue_item_id} (Status: {status}, 嘗試: {attempt+1})")
                        
                        # 更新 Redis 中的任務狀態
                        task_key = f"{self.TASK_DATA_PREFIX}{queue_item_id}"
                        self.redis_client.hset(task_key, 'status', status)
                        
                        # ✅ 只在任務完成或失敗時才設置 completedAt
                        if status in ('completed', 'failed'):
                            self.redis_client.hset(task_key, 'completedAt', datetime.now().isoformat())
                        
                        # 根據狀態移動到相應隊列
                        if status == 'completed':
                            self.redis_client.rpush(self.COMPLETED_KEY, queue_item_id)
                        elif status == 'failed':
                            self.redis_client.rpush(self.FAILED_KEY, queue_item_id)
                        
                        return  # 成功，結束
                    else:
                        logger.warning(
                            f"⚠️  發送結果收到非200響應: {response.status_code} (嘗試 {attempt+1}/{max_retries})")
                        
                except requests.Timeout:
                    logger.warning(f"⚠️  發送超時，重試 {attempt+1}/{max_retries}")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)  # 指數退避：2s, 4s, 8s...
                
                except requests.RequestException as e:
                    logger.warning(f"⚠️  HTTP 請求異常: {str(e)}, 重試 {attempt+1}/{max_retries}")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
            
            logger.error(f"❌ 發送結果失敗，已放棄 (經過 {max_retries} 次嘗試): {queue_item_id}")
            
        except Exception as e:
            logger.error(f"❌ 發送結果時出錯: {str(e)}", exc_info=True)

    def send_processing_status(
        self,
        queue_item_id: str,
        progress_percent: int,
        processing_time: float = 0
    ):
        """
        發送處理中的狀態更新
        
        Args:
            queue_item_id: 隊列項目 ID
            progress_percent: 進度百分比 (0-100)
            processing_time: 已消耗時間
        """
        self._send_result_to_csharp(
            queue_item_id=queue_item_id,
            success=None,
            status='processing',
            progress_percent=progress_percent,
            processing_time=processing_time
        )

    def send_completed_status(
        self,
        queue_item_id: str,
        result_data: dict,
        processing_time: float
    ):
        """
        發送處理完畢的狀態更新
        
        Args:
            queue_item_id: 隊列項目 ID
            result_data: 處理結果數據
            processing_time: 總処理時間
        """
        self._send_result_to_csharp(
            queue_item_id=queue_item_id,
            success=True,
            result_data=result_data,
            status='completed',
            processing_time=processing_time
        )

    def send_failed_status(
        self,
        queue_item_id: str,
        error: str,
        processing_time: float
    ):
        """
        發送處理失敗的狀態更新
        
        Args:
            queue_item_id: 隊列項目 ID
            error: 錯誤信息
            processing_time: 処理耗時
        """
        self._send_result_to_csharp(
            queue_item_id=queue_item_id,
            success=False,
            status='failed',
            error=error,
            processing_time=processing_time
        )

    def get_status(self) -> dict:
        """
        獲取隊列狀態
        
        Returns:
            狀態字典
        """
        try:
            # ✅ 改進：使用安全的 Redis 調用
            pending_count = self._redis_safe_call(
                self.redis_client.llen,
                self.QUEUE_KEY
            )
            processing_count = self._redis_safe_call(
                self.redis_client.llen,
                self.PROCESSING_KEY
            )
            completed_count = self._redis_safe_call(
                self.redis_client.llen,
                self.COMPLETED_KEY
            )
            failed_count = self._redis_safe_call(
                self.redis_client.llen,
                self.FAILED_KEY
            )
            
            return {
                'queueSize': pending_count,
                'processingSize': processing_count,
                'completedSize': completed_count,
                'failedSize': failed_count,
                'isProcessing': self.is_processing,
                'currentTaskId': self.current_task_id,
                'workerId': self.worker_id,
                'maxWorkers': self.max_workers,
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"❌ 獲取隊列狀態時出錯: {str(e)}")
            return {
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }

    def get_task_info(self, queue_item_id: str) -> dict:
        """
        獲取任務詳情
        
        Args:
            queue_item_id: 隊列項目 ID
            
        Returns:
            任務詳情字典
        """
        try:
            # ✅ 改進：使用安全的 Redis 調用
            task_key = f"{self.TASK_DATA_PREFIX}{queue_item_id}"
            task_data = self._redis_safe_call(
                self.redis_client.hgetall,
                task_key
            )
            
            if not task_data:
                return {'error': 'Task not found'}
            
            return task_data
        except Exception as e:
            logger.error(f"❌ 獲取任務詳情時出錯: {str(e)}")
            return {'error': str(e)}

    def cleanup_old_tasks(self, days: int = 7):
        """
        清理舊任務
        
        Args:
            days: 保留天數（默認7天）
        """
        try:
            cutoff_time = datetime.now().timestamp() - (days * 86400)
            logger.info(f"🧹 開始清理 {days} 天前的任務...")
            
            # ✅ 改進：使用安全的 Redis 調用
            deleted_count = 0
            for key in self._redis_safe_call(
                self.redis_client.scan_iter,
                f"{self.TASK_DATA_PREFIX}*"
            ):
                created_at = self._redis_safe_call(
                    self.redis_client.hget,
                    key,
                    'receivedAt'
                )
                if created_at:
                    task_time = datetime.fromisoformat(created_at).timestamp()
                    if task_time < cutoff_time:
                        self._redis_safe_call(
                            self.redis_client.delete,
                            key
                        )
                        deleted_count += 1
                        logger.info(f"✅ 已刪除任務: {key}")
            
            logger.info(f"✅ 任務清理完成 (已刪除 {deleted_count} 個任務)")
        except Exception as e:
            logger.error(f"❌ 清理任務時出錯: {str(e)}")


# 全局任務隊列實例
_task_queue_instance = None


def get_task_queue(
    csharp_server_url: str = None,
    redis_host: str = "localhost",
    redis_port: int = 6379,
    redis_db: int = 0,
    redis_password: str = None
) -> TaskQueue:
    """
    獲取或創建全局任務隊列實例
    
    Args:
        csharp_server_url: C# Server URL (第一次初始化時使用)
        redis_host: Redis 主機
        redis_port: Redis 端口
        redis_db: Redis 數據庫編號
        redis_password: Redis 密碼
        
    Returns:
        TaskQueue 實例
    """
    global _task_queue_instance
    
    if _task_queue_instance is None:
        if csharp_server_url is None:
            csharp_server_url = "https://tekswing.api.atk.tw"
        
        _task_queue_instance = TaskQueue(
            csharp_server_url=csharp_server_url,
            redis_host=redis_host,
            redis_port=redis_port,
            redis_db=redis_db,
            redis_password=redis_password
        )
    
    return _task_queue_instance
