import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pages/recording_session_page.dart';
import 'models/recording_history_entry.dart';

/// 錄影入口頁面：專責處理藍牙 IMU 配對與引導使用者前往錄影畫面
class RecorderPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 傳入所有可用鏡頭
  final List<RecordingHistoryEntry> initialHistory; // 外部帶入的歷史紀錄
  final ValueChanged<List<RecordingHistoryEntry>> onHistoryChanged; // 回傳更新後的歷史資料

  const RecorderPage({
    super.key,
    required this.cameras,
    required this.initialHistory,
    required this.onHistoryChanged,
  });

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  // ---------- 狀態變數區 ----------
  StreamSubscription<List<ScanResult>>? _scanSubscription; // 藍牙掃描訂閱
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription; // 藍牙狀態監聽
  StreamSubscription<BluetoothConnectionState>? _deviceConnectionSubscription; // 裝置連線狀態監聽

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown; // 目前藍牙狀態
  BluetoothDevice? _foundDevice; // 已搜尋到的目標 IMU 裝置
  BluetoothDevice? _connectedDevice; // 已成功連線的 IMU 裝置
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected; // IMU 連線狀態

  bool _isScanning = false; // 是否正在搜尋裝置
  bool _isConnecting = false; // 是否正處於連線流程
  bool _isOpeningSession = false; // 是否正在切換至錄影頁面
  int _selectedRounds = 5; // 使用者預設要錄影的次數
  int _recordingDurationSeconds = 15; // 使用者預設每次錄影長度（秒）
  String _connectionMessage = '尚未搜尋到 IMU 裝置'; // 顯示於 UI 的狀態文字
  int? _lastRssi; // 紀錄訊號強度供顯示
  String? _foundDeviceName; // 掃描到的裝置名稱
  final String _targetNameKeyword = 'TekSwing-IMU'; // 目標裝置名稱關鍵字
  final Guid _nordicUartServiceUuid =
      Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'); // 依 Nordic UART 定義的服務 UUID
  final String _mockBatteryLevel = '82%'; // 假資料電量資訊（尚無實作藍牙服務）
  final String _mockFirmwareVersion = '韌體 1.0.3'; // 假資料韌體版本（待後續串接）
  late final List<RecordingHistoryEntry> _recordingHistory =
      List<RecordingHistoryEntry>.from(widget.initialHistory); // 累積曾經錄影的檔案資訊

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    initBluetooth(); // 啟動藍牙權限申請與自動搜尋流程
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _deviceConnectionSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ---------- 初始化流程 ----------
  /// 初始化藍牙狀態與權限，確保錄影前完成 IMU 配對
  Future<void> initBluetooth() async {
    await _requestBluetoothPermissions();

    // 監聽手機藍牙開關狀態，並視情況重新觸發掃描
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _adapterState = state;
        if (state == BluetoothAdapterState.off) {
          _connectedDevice = null;
          _connectionState = BluetoothConnectionState.disconnected;
          _connectionMessage = '請開啟藍牙以搜尋裝置';
        }
      });

      if (state == BluetoothAdapterState.on && !isImuConnected && !_isScanning && !_isConnecting) {
        scanForImu();
      }
    });

    final initialState = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;
    setState(() => _adapterState = initialState);

    final connectedDevices = FlutterBluePlus.connectedDevices;
    if (!mounted) return;

    for (final device in connectedDevices) {
      if (_matchTarget(device.platformName)) {
        _connectedDevice = device;
        _listenConnectionState(device);
        setState(() {
          _connectionState = BluetoothConnectionState.connected;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        return;
      }
    }

    if (initialState == BluetoothAdapterState.on) {
      await scanForImu();
    } else {
      setState(() {
        _connectionMessage = '請先開啟藍牙功能後再開始搜尋';
      });
    }
  }

  /// 申請藍牙與定位權限，避免掃描過程被拒
  Future<void> _requestBluetoothPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.locationWhenInUse.request();
  }

  // ---------- 方法區 ----------
  /// 掃描 TekSwing IMU 裝置並更新顯示資訊
  Future<void> scanForImu() async {
    if (_adapterState != BluetoothAdapterState.on) {
      // 若藍牙尚未開啟則優先提示，避免重複觸發掃描與錯誤訊息
      if (!mounted) return;
      setState(() {
        _connectionMessage = '請先開啟藍牙功能後再進行搜尋';
      });
      return;
    }

    await _stopScan(resetFoundDevice: true); // 先停止前一次掃描，遵循 Nordic 範例先清除舊狀態

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _connectionMessage = '以低延遲模式掃描 $_targetNameKeyword...';
    });

    final completer = Completer<void>();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted || _foundDevice != null || _isConnecting) {
        return; // 若已找到裝置或正在連線則忽略後續結果
      }

      for (final result in results) {
        final advertisementName = result.advertisementData.advName;
        final deviceName = result.device.platformName;
        final displayName = deviceName.isNotEmpty
            ? deviceName
            : (advertisementName.isNotEmpty ? advertisementName : _targetNameKeyword);

        if (_matchTarget(displayName)) {
          if (!mounted) return;
          setState(() {
            // Nordic Library 建議選到目標後即停止掃描並交由連線流程處理
            _foundDevice = result.device;
            _foundDeviceName = displayName;
            _lastRssi = result.rssi;
            _connectionMessage = '偵測到 $displayName，準備建立安全連線';
          });
          if (!completer.isCompleted) {
            completer.complete();
          }
          break;
        }
      }
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '搜尋失敗：$error';
      });
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        // 依 Nordic Android Library 建議使用低延遲掃描模式以提升連線準備速度
        androidScanMode: BluetoothScanMode.lowLatency,
        withServices: [_nordicUartServiceUuid],
      );

      // 最多等待 10 秒取得第一筆目標裝置，逾時則回報失敗
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (!completer.isCompleted) {
            completer.completeError('未在時間內找到裝置');
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '無法開始掃描或找不到裝置：$e';
      });
    } finally {
      await _stopScan();
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// 嘗試連線到掃描到的 IMU 裝置，並遵循 Nordic BLE Library 建議的手動連線流程
  Future<void> connectToImu() async {
    final target = _foundDevice ?? _connectedDevice;
    if (target == null) {
      await scanForImu();
      return;
    }

    await _stopScan(); // 連線前先停止掃描，避免造成頻寬干擾

    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _connectionMessage = '正在與 ${_foundDeviceName ?? _resolveDeviceName(target)} 建立連線...';
    });

    try {
      // 先嘗試中斷既有連線，確保流程以乾淨狀態開始
      await target.disconnect();
    } catch (_) {
      // 若裝置原本未連線會拋錯，忽略即可
    }

    try {
      await target.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );

      // 依 Nordic 流程完成 GATT 初始化：等待真正連線並探索服務
      await target.connectionState.firstWhere(
        (state) => state == BluetoothConnectionState.connected,
      );
      await target.discoverServices();

      try {
        await target.requestMtu(247); // 嘗試提升 MTU 以利後續傳輸
      } catch (_) {
        // 部分裝置不支援 MTU 調整，忽略錯誤即可
      }

      _connectedDevice = target;
      _listenConnectionState(target);
      if (!mounted) return;
      setState(() {
        _connectionMessage = '已連線至 ${_resolveDeviceName(target)}，可開始錄影';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '連線流程失敗：$e';
        _connectedDevice = null;
      });
      await _restartScanWithBackoff();
    } finally {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
      });
    }
  }

  /// 停止掃描流程並視需求重置搜尋結果，避免背景掃描持續耗電
  Future<void> _stopScan({bool resetFoundDevice = false}) async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
    if (resetFoundDevice) {
      _foundDevice = null;
      _foundDeviceName = null;
      _lastRssi = null;
    }
  }

  /// 掃描逾時或連線失敗時等待片刻再重試，模擬 Nordic 範例的退避策略
  Future<void> _restartScanWithBackoff() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || _isScanning || _isConnecting) {
      return;
    }
    await scanForImu();
  }

  /// 監聽裝置連線狀態，若中斷則重新搜尋
  void _listenConnectionState(BluetoothDevice device) {
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = device.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        } else if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _connectionMessage = '裝置已斷線，稍後自動重新搜尋';
        }
      });

      if (state == BluetoothConnectionState.disconnected) {
        _restartScanWithBackoff();
      }
    });
  }

  /// 判斷目前是否已建立 IMU 連線
  bool get isImuConnected =>
      _connectedDevice != null && _connectionState == BluetoothConnectionState.connected;

  /// 根據裝置資訊推算顯示名稱
  String _resolveDeviceName(BluetoothDevice device) {
    if (device.platformName.isNotEmpty) {
      return device.platformName;
    }
    return device.remoteId.str;
  }

  /// 比對字串是否符合目標關鍵字
  bool _matchTarget(String name) => name.contains(_targetNameKeyword);

  /// 切換至錄影專用頁面，讓錄影與配對流程分離
  Future<void> _openRecordingSession() async {
    if (_isOpeningSession) return; // 避免重複點擊快速開啟多個頁面

    if (widget.cameras.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有可用鏡頭，無法開始錄影。')),
      );
      return;
    }

    setState(() => _isOpeningSession = true);

    // 進入錄影前先彈出設定視窗，讓使用者選擇要錄影的次數與長度
    final config = await _showRecordingConfigDialog();
    if (config == null) {
      if (!mounted) return;
      setState(() => _isOpeningSession = false);
      return; // 使用者取消設定則不進入錄影畫面
    }

    setState(() {
      _selectedRounds = config['rounds']!;
      _recordingDurationSeconds = config['seconds']!;
    });

    final historyFromSession = await Navigator.push<List<RecordingHistoryEntry>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingSessionPage(
          cameras: widget.cameras,
          isImuConnected: isImuConnected,
          totalRounds: _selectedRounds,
          durationSeconds: _recordingDurationSeconds,
        ),
      ),
    );
    if (!mounted) return;
    if (historyFromSession != null && historyFromSession.isNotEmpty) {
      setState(() {
        final existingPaths = _recordingHistory.map((e) => e.filePath).toSet();
        for (final entry in historyFromSession) {
          if (!existingPaths.contains(entry.filePath)) {
            _recordingHistory.insert(0, entry);
          }
        }
      });
      widget.onHistoryChanged(
        List<RecordingHistoryEntry>.from(_recordingHistory),
      ); // 即時回傳最新清單給首頁同步顯示
    }
    setState(() => _isOpeningSession = false);
  }

  /// 顯示設定錄影次數與秒數的彈窗，確保使用者可以自訂錄影需求
  Future<Map<String, int>?> _showRecordingConfigDialog() async {
    int rounds = _selectedRounds;
    int seconds = _recordingDurationSeconds;

    return showDialog<Map<String, int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('設定錄影參數'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '請選擇本次錄影的輪數與每輪秒數，稍後錄影畫面將依據設定自動執行。',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  _buildConfigSlider(
                    label: '錄影次數',
                    description: '可自訂本次要錄影的輪數，建議依自身練習需求調整。',
                    value: rounds.toDouble(),
                    min: 1,
                    max: 12,
                    division: 11,
                    unit: '次',
                    onChanged: (value) {
                      // 透過 round() 與上下界控制確保數值落在合法範圍
                      setModalState(() {
                        rounds = value.round();
                        if (rounds < 1) rounds = 1;
                        if (rounds > 12) rounds = 12;
                      });
                    },
                    onInputChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        setModalState(() {
                          rounds = parsed;
                          if (rounds < 1) rounds = 1;
                          if (rounds > 12) rounds = 12;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildConfigSlider(
                    label: '每次長度',
                    description: '調整每輪錄影秒數，支援 3 至 60 秒細緻設定。',
                    value: seconds.toDouble(),
                    min: 3,
                    max: 60,
                    division: 57,
                    unit: '秒',
                    onChanged: (value) {
                      setModalState(() {
                        seconds = value.round();
                        if (seconds < 3) seconds = 3;
                        if (seconds > 60) seconds = 60;
                      });
                    },
                    onInputChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        setModalState(() {
                          seconds = parsed;
                          if (seconds < 3) seconds = 3;
                          if (seconds > 60) seconds = 60;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, {'rounds': rounds, 'seconds': seconds}),
                  child: const Text('確定開始'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 建構設定錄影參數的滑桿與輸入欄位，提供使用者細緻調整能力
  Widget _buildConfigSlider({
    required String label,
    required String description,
    required double value,
    required double min,
    required double max,
    required int division,
    required String unit,
    required ValueChanged<double> onChanged,
    required ValueChanged<String> onInputChanged,
  }) {
    final controller = TextEditingController(text: value.round().toString());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B86)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: division,
          label: '${value.round()} $unit',
          onChanged: onChanged,
        ),
        Row(
          children: [
            // 透過 IconButton 提供快速微調
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                final nextValue = (value - 1).clamp(min, max);
                onChanged(nextValue);
              },
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  suffixText: unit,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: onInputChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                final nextValue = (value + 1).clamp(min, max);
                onChanged(nextValue);
              },
            ),
            const Spacer(),
            Text(
              '範圍 ${min.round()}~${max.round()} $unit',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9AA6B2)),
            ),
          ],
        ),
      ],
    );
  }

  /// 建構 IMU 連線卡片，提示使用者完成藍牙配對
  Widget _buildImuConnectionCard() {
    final bool connected = isImuConnected;
    final String displayName = connected
        ? _resolveDeviceName(_connectedDevice!)
        : (_foundDeviceName ?? 'TekSwing-IMU-A12');
    final String signalText = _lastRssi != null ? '訊號 ${_lastRssi} dBm' : '訊號偵測中';

    final Color statusColor = connected
        ? const Color(0xFF1E8E5A)
        : (_adapterState == BluetoothAdapterState.on
            ? const Color(0xFF7D8B9A)
            : const Color(0xFFD9534F));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '連線裝置（自動對設備配對）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF123B70),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E8E5A), width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF123B70), Color(0xFF1E8E5A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.sports_golf, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '電量 $_mockBatteryLevel · $_mockFirmwareVersion',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7D8B9A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _connectionMessage,
                      style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      signalText,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8B6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: connected || _isConnecting ? null : connectToImu,
                style: FilledButton.styleFrom(
                  backgroundColor: connected ? const Color(0xFF1E8E5A) : const Color(0xFF123B70),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        connected ? '已連線' : (_foundDevice != null ? '配對裝置' : '搜尋中'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isScanning ? null : scanForImu,
                icon: Icon(
                  _isScanning ? Icons.hourglass_empty : Icons.sync,
                  color: const Color(0xFF123B70),
                ),
                label: Text(
                  _isScanning ? '掃描中' : '重新搜尋',
                  style: const TextStyle(color: Color(0xFF123B70)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF123B70)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(width: 12),
              if (!connected)
                Expanded(
                  child: Text(
                    '未連線 IMU 亦可錄影，建議配對以取得揮桿數據。',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7D8B9A)),
                    textAlign: TextAlign.right,
                  ),
                )
              else
                const Expanded(
                  child: Text(
                    '裝置已就緒，可以開始錄影流程。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E8E5A)),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 說明錄影流程的卡片，提醒使用者會切換到新畫面
  Widget _buildRecordingGuideCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '錄影流程說明',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF123B70),
            ),
          ),
          SizedBox(height: 12),
          Text(
            '開始錄影後會跳轉至新的錄影畫面，錄影畫面專注於鏡頭預覽、倒數與波形，避免與 IMU 配對資訊混在一起。',
            style: TextStyle(fontSize: 13, color: Color(0xFF465A71), height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            '若尚未連線 IMU，新的錄影畫面仍可啟動純錄影模式，稍後可再返回此頁重新配對。',
            style: TextStyle(fontSize: 13, color: Color(0xFF465A71), height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            '錄影完成後的歷史影片已移至首頁的「錄影歷史」按鈕中，方便集中管理。',
            style: TextStyle(fontSize: 13, color: Color(0xFF465A71), height: 1.4),
          ),
        ],
      ),
    );
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Golf Recorder')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          _buildImuConnectionCard(),
          const SizedBox(height: 8),
          _buildRecordingGuideCard(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '本次將錄影 $_selectedRounds 次，每次 $_recordingDurationSeconds 秒。',
                style: const TextStyle(fontSize: 13, color: Color(0xFF465A71)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _isOpeningSession ? null : _openRecordingSession,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  backgroundColor: const Color(0xFF123B70),
                ),
                child: Text(
                  isImuConnected ? '進入錄影畫面' : '進入錄影畫面（純錄影）',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
