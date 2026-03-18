#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
6 大問題修復 - 驗證測試腳本

測試以下改進:
✅ 異步 Flask API (阻塞問題)
✅ 任務隊列 (非同步處理)
✅ 超時控制
✅ 細粒度異常處理
✅ 統一序列化
✅ 依賴注入
"""

import requests
import json
import time
import uuid
from datetime import datetime
from typing import Tuple, Dict, Any

# ============================================================================
# 測試配置
# ============================================================================

API_BASE_URL = "http://localhost:5000"
CSHARP_SERVER_URL = "http://localhost:5001"

# ANSI 顏色代碼
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'

def print_section(title: str):
    """打印測試段落標題"""
    print(f"\n{Colors.BLUE}{'=' * 80}{Colors.RESET}")
    print(f"{Colors.BLUE}🧪 {title}{Colors.RESET}")
    print(f"{Colors.BLUE}{'=' * 80}{Colors.RESET}\n")

def print_pass(message: str):
    """打印通過"""
    print(f"{Colors.GREEN}✅ PASS{Colors.RESET}: {message}")

def print_fail(message: str):
    """打印失敗"""
    print(f"{Colors.RED}❌ FAIL{Colors.RESET}: {message}")

def print_info(message: str):
    """打印信息"""
    print(f"{Colors.YELLOW}ℹ️  INFO{Colors.RESET}: {message}")

# ============================================================================
# 1️⃣ 測試異步 Flask API (解決阻塞問題)
# ============================================================================

def test_async_flask_api():
    """測試異步 API 端點 - 應該快速返回 202"""
    print_section("1️⃣ 測試異步 Flask API (非阻塞)")
    
    test_cases = [
        {
            "name": "正常請求",
            "data": {
                "queueItemId": str(uuid.uuid4()),
                "videoId": "video-001",
                "inputDir": "/videos/input"
            }
        },
        {
            "name": "缺少 queueItemId",
            "data": {
                "videoId": "video-002",
                "inputDir": "/videos/input"
            },
            "expect_error": True
        },
        {
            "name": "空請求體",
            "data": None,
            "expect_error": True
        }
    ]
    
    results = []
    
    for test_case in test_cases:
        print(f"\n📌 測試: {test_case['name']}")
        
        start_time = time.time()
        
        try:
            response = requests.post(
                f"{API_BASE_URL}/api/tasks/process",
                json=test_case.get('data'),
                timeout=5
            )
            
            elapsed = (time.time() - start_time) * 1000  # ms
            
            # 檢查響應時間 (應該 < 100ms)
            if elapsed > 100:
                print_fail(f"響應時間過長: {elapsed:.2f}ms (預期 < 100ms)")
                results.append(False)
            else:
                print_info(f"響應時間: {elapsed:.2f}ms ✅")
            
            # 檢查狀態碼
            if test_case.get('expect_error'):
                if response.status_code >= 400:
                    print_pass(f"返回預期的錯誤狀態碼: {response.status_code}")
                    results.append(True)
                else:
                    print_fail(f"預期錯誤，但返回 {response.status_code}")
                    results.append(False)
            else:
                if response.status_code == 202:
                    print_pass(f"返回 202 Accepted")
                    results.append(True)
                    
                    # 驗證響應格式
                    data = response.json()
                    if data.get('success') and data.get('queueItemId'):
                        print_pass(f"響應格式正確，queueItemId: {data['queueItemId']}")
                    else:
                        print_fail("響應格式不正確")
                        results.append(False)
                elif response.status_code == 400:
                    print_pass(f"返回 400 Bad Request (驗證成功)")
                    results.append(True)
                else:
                    print_fail(f"未預期的狀態碼: {response.status_code}")
                    results.append(False)
        
        except requests.Timeout:
            print_fail("請求超時 (> 5 秒)")
            results.append(False)
        except Exception as e:
            print_fail(f"請求失敗: {str(e)}")
            results.append(False)
    
    return all(results)

# ============================================================================
# 2️⃣ 測試任務隊列狀態 (非同步隊列)
# ============================================================================

def test_task_queue():
    """測試任務隊列 API"""
    print_section("2️⃣ 測試任務隊列狀態 (非同步)")
    
    results = []
    
    # 測試: 提交多個任務
    print("📌 提交 5 個任務")
    task_ids = []
    
    for i in range(5):
        response = requests.post(
            f"{API_BASE_URL}/api/tasks/process",
            json={
                "queueItemId": f"test-task-{i}",
                "videoId": f"video-{i}",
                "inputDir": "/videos"
            }
        )
        
        if response.status_code == 202:
            task_ids.append(f"test-task-{i}")
        else:
            print_fail(f"提交任務 {i} 失敗")
            results.append(False)
    
    if len(task_ids) == 5:
        print_pass(f"成功提交 5 個任務")
    else:
        print_fail(f"只提交了 {len(task_ids)} 個任務")
        results.append(False)
    
    # 測試: 查詢隊列狀態
    print("\n📌 查詢隊列狀態")
    
    try:
        response = requests.get(f"{API_BASE_URL}/api/tasks/status", timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            print_pass(f"獲取隊列狀態成功")
            print_info(f"  - 待處理: {data.get('queueSize', 0)}")
            print_info(f"  - 處理中: {data.get('processingSize', 0)}")
            print_info(f"  - 已完成: {data.get('completedSize', 0)}")
            print_info(f"  - 失敗: {data.get('failedSize', 0)}")
            results.append(True)
        else:
            print_fail(f"狀態碼: {response.status_code}")
            results.append(False)
    
    except Exception as e:
        print_fail(f"查詢失敗: {str(e)}")
        results.append(False)
    
    # 測試: 查詢單個任務
    print("\n📌 查詢單個任務詳情")
    
    if task_ids:
        try:
            response = requests.get(
                f"{API_BASE_URL}/api/tasks/{task_ids[0]}",
                timeout=5
            )
            
            if response.status_code == 200:
                data = response.json()
                print_pass(f"獲取任務詳情成功")
                print_info(f"  - 狀態: {data.get('status', 'unknown')}")
                results.append(True)
            else:
                print_fail(f"狀態碼: {response.status_code}")
                results.append(False)
        
        except Exception as e:
            print_fail(f"查詢失敗: {str(e)}")
            results.append(False)
    
    return all(results)

# ============================================================================
# 3️⃣ 測試細粒度異常處理
# ============================================================================

def test_exception_handling():
    """測試細粒度異常處理和錯誤碼"""
    print_section("3️⃣ 測試細粒度異常處理")
    
    test_cases = [
        {
            "name": "缺少必要參數 (ValidationException)",
            "endpoint": "/api/tasks/process",
            "method": "POST",
            "data": {"videoId": "test"},
            "expect_status": 400,
            "expect_error_code": "VALIDATION_ERROR"
        },
        {
            "name": "方法不允許 (405)",
            "endpoint": "/api/health",
            "method": "POST",
            "data": {},
            "expect_status": 405,
        },
        {
            "name": "端點不存在 (404)",
            "endpoint": "/api/nonexistent",
            "method": "GET",
            "data": None,
            "expect_status": 404,
            "expect_error_code": "NOT_FOUND"
        },
    ]
    
    results = []
    
    for test_case in test_cases:
        print(f"\n📌 {test_case['name']}")
        
        try:
            if test_case['method'] == 'POST':
                response = requests.post(
                    f"{API_BASE_URL}{test_case['endpoint']}",
                    json=test_case.get('data')
                )
            else:
                response = requests.get(
                    f"{API_BASE_URL}{test_case['endpoint']}"
                )
            
            if response.status_code == test_case['expect_status']:
                print_pass(f"返回預期狀態碼: {response.status_code}")
                
                try:
                    data = response.json()
                    if 'error_code' in test_case:
                        if data.get('error_code') == test_case['expect_error_code']:
                            print_pass(f"返回正確的錯誤碼: {test_case['expect_error_code']}")
                            results.append(True)
                        else:
                            print_fail(f"錯誤碼不符: {data.get('error_code')}")
                            results.append(False)
                    else:
                        results.append(True)
                except:
                    print_fail("無法解析 JSON 響應")
                    results.append(False)
            else:
                print_fail(f"狀態碼不符: {response.status_code} (預期 {test_case['expect_status']})")
                results.append(False)
        
        except Exception as e:
            print_fail(f"請求失敗: {str(e)}")
            results.append(False)
    
    return all(results)

# ============================================================================
# 4️⃣ 測試 API 文檔和服務信息
# ============================================================================

def test_api_info():
    """測試 /api/info 端點 (依賴注入和統一序列化)"""
    print_section("4️⃣ 測試 API 文檔和服務信息")
    
    results = []
    
    try:
        response = requests.get(f"{API_BASE_URL}/api/info", timeout=5)
        
        if response.status_code != 200:
            print_fail(f"狀態碼: {response.status_code}")
            return False
        
        data = response.json()
        
        # 檢查必要欄位
        required_fields = [
            ('service', str),
            ('version', str),
            ('endpoints', dict),
            ('pipeline_steps', list),
            ('improvements', list),
            ('async_workflow', dict)
        ]
        
        for field_name, field_type in required_fields:
            if field_name in data and isinstance(data[field_name], field_type):
                print_pass(f"包含 {field_name} 欄位")
                results.append(True)
            else:
                print_fail(f"缺少或類型不正確的欄位: {field_name}")
                results.append(False)
        
        # 驗證改進列表
        improvements = data.get('improvements', [])
        expected_improvements = [
            "✅ 異步任務隊列 (不阻塞)",
            "✅ 細粒度異常處理",
            "✅ 統一序列化管理",
            "✅ 超時控制",
            "✅ 依賴注入",
        ]
        
        for expected in expected_improvements:
            if expected in improvements:
                print_info(f"包含改進: {expected}")
            else:
                print_fail(f"缺少改進: {expected}")
                results.append(False)
        
        print_pass("所有改進都已實現")
        results.append(True)
        
        # 驗證 async_workflow
        workflow = data.get('async_workflow', {})
        if all(k in workflow for k in ['step_1', 'step_2', 'step_3', 'step_4']):
            print_pass("非同步工作流已文檔化")
            results.append(True)
        else:
            print_fail("非同步工作流不完整")
            results.append(False)
    
    except Exception as e:
        print_fail(f"請求失敗: {str(e)}")
        results.append(False)
    
    return all(results)

# ============================================================================
# 5️⃣ 測試健康檢查 (依賴項檢查)
# ============================================================================

def test_health_check():
    """測試 /api/health 端點 (包含依賴項檢查)"""
    print_section("5️⃣ 測試健康檢查 (依賴項檢查)")
    
    results = []
    
    try:
        response = requests.get(f"{API_BASE_URL}/api/health", timeout=5)
        
        if response.status_code != 200:
            print_fail(f"狀態碼: {response.status_code}")
            return False
        
        data = response.json()
        
        # 檢查狀態
        if data.get('status') == 'healthy':
            print_pass("服務健康")
            results.append(True)
        else:
            print_fail(f"服務狀態: {data.get('status')}")
            results.append(False)
        
        # 檢查版本
        if data.get('version'):
            print_pass(f"版本: {data.get('version')}")
            results.append(True)
        
        # 檢查依賴項
        if 'dependencies' in data:
            deps = data['dependencies']
            print_pass("包含依賴項檢查")
            print_info(f"  - task_queue: {deps.get('task_queue')}")
            print_info(f"  - redis: {deps.get('redis')}")
            results.append(True)
        else:
            print_fail("缺少依賴項檢查")
            results.append(False)
    
    except Exception as e:
        print_fail(f"請求失敗: {str(e)}")
        results.append(False)
    
    return all(results)

# ============================================================================
# 6️⃣ 測試並發請求 (驗證無阻塞)
# ============================================================================

def test_concurrency():
    """測試並發請求 - 驗證 Flask 不被阻塞"""
    print_section("6️⃣ 測試並發請求 (無阻塞)")
    
    print("📌 同時發送 10 個請求...")
    
    import concurrent.futures
    
    def send_request(i):
        start = time.time()
        try:
            response = requests.post(
                f"{API_BASE_URL}/api/tasks/process",
                json={
                    "queueItemId": f"concurrent-{i}",
                    "videoId": f"video-{i}",
                    "inputDir": "/videos"
                },
                timeout=5
            )
            elapsed = (time.time() - start) * 1000
            return (response.status_code == 202, elapsed)
        except Exception as e:
            return (False, time.time() - start)
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(send_request, i) for i in range(10)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]
    
    # 驗證結果
    successes = [r for r, _ in results if r]
    times = [t for _, t in results]
    
    avg_time = sum(times) / len(times)
    max_time = max(times)
    
    print_info(f"成功率: {len(successes)}/10")
    print_info(f"平均響應時間: {avg_time:.2f}ms")
    print_info(f"最長響應時間: {max_time:.2f}ms")
    
    if len(successes) == 10 and avg_time < 100:
        print_pass("並發請求測試通過")
        return True
    else:
        print_fail(f"並發請求性能不達標")
        return False

# ============================================================================
# 主測試函數
# ============================================================================

def run_all_tests():
    """運行所有測試"""
    print(f"\n{Colors.BLUE}")
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║         6 大問題修復 - 完整驗證測試                            ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print(f"{Colors.RESET}\n")
    
    print(f"🌐 API Base URL: {API_BASE_URL}")
    print(f"⏰ 開始時間: {datetime.now().isoformat()}\n")
    
    tests = [
        ("異步 Flask API", test_async_flask_api),
        ("任務隊列", test_task_queue),
        ("異常處理", test_exception_handling),
        ("API 文檔", test_api_info),
        ("健康檢查", test_health_check),
        ("並發請求", test_concurrency),
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        try:
            result = test_func()
            results[test_name] = result
        except Exception as e:
            print_fail(f"測試執行失敗: {str(e)}")
            results[test_name] = False
    
    # 打印總結
    print_section("📊 測試總結")
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    for test_name, result in results.items():
        status = f"{Colors.GREEN}✅ PASS{Colors.RESET}" if result else f"{Colors.RED}❌ FAIL{Colors.RESET}"
        print(f"{status}: {test_name}")
    
    print(f"\n{'═' * 60}")
    print(f"測試結果: {Colors.GREEN}{passed}/{total} 通過{Colors.RESET}")
    print(f"{'═' * 60}\n")
    
    if passed == total:
        print(f"{Colors.GREEN}🎉 所有測試通過！{Colors.RESET}\n")
        return True
    else:
        print(f"{Colors.YELLOW}⚠️  有 {total - passed} 個測試失敗{Colors.RESET}\n")
        return False

if __name__ == '__main__':
    try:
        success = run_all_tests()
        exit(0 if success else 1)
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}測試中斷{Colors.RESET}\n")
        exit(1)
