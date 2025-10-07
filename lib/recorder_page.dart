import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer; // 專責紀錄藍牙偵錯訊息
import 'dart:io'; // 依平台動態決定權限需求

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 辨識平台層例外以補充權限提示
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
  void _logBle(String message, {Object? error, StackTrace? stackTrace}) {
    // 集中處理藍牙相關紀錄，方便於 console 追蹤 bug
    developer.log(
      message,
      name: 'BLE',
      error: error,
      stackTrace: stackTrace,
    );
  }

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
  bool _permissionsReady = false; // 記錄藍牙權限是否已完整授權
  late final Map<Permission, String> _runtimeBlePermissions; // 不同平台需申請的權限列表
  int _selectedRounds = 5; // 使用者預設要錄影的次數
  int _recordingDurationSeconds = 15; // 使用者預設每次錄影長度（秒）
  String _connectionMessage = '尚未搜尋到 IMU 裝置'; // 顯示於 UI 的狀態文字
  int? _lastRssi; // 紀錄訊號強度供顯示
  String? _foundDeviceName; // 掃描到的裝置名稱
  final Map<String, _ImuScanCandidate> _scanCandidates = {}; // 目前掃描到的藍牙裝置列表
  Completer<void>? _activeScanStopper; // 追蹤目前掃描流程以便在外部中止等待
  final Guid _nordicUartServiceUuid =
      Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'); // 依 Nordic UART 定義的服務 UUID
  final Guid _serviceBno086Uuid =
      Guid('bac2f121-a97d-4a77-b2d3-8e46e87862ab'); // BNO086 感測器服務 UUID
  final Guid _charLinearAccelerationUuid =
      Guid('7e807164-3f0b-4252-9cb0-41241af264f0'); // 線性加速度特徵值
  final Guid _charGameRotationVectorUuid =
      Guid('07afa8e1-a1c8-48c8-9f5b-102c21261901'); // Game Rotation Vector 特徵值
  final Guid _serviceButtonUuid =
      Guid('d9087473-1415-44f0-bae8-1cd97fb224a5'); // 裝置按鈕服務 UUID
  final Guid _charButtonNotifyUuid =
      Guid('4a5a11ad-3f06-4de4-a56e-abd6e974a0ab'); // 按鈕事件通知特徵值
  final Guid _serviceMotorUuid =
      Guid('7c2b4a96-bf0a-444b-b1cd-559b5e36dd6f'); // 震動馬達服務 UUID
  final Guid _charMotorToggleUuid =
      Guid('ce12d81f-1325-4e02-82f0-c3e4f9896233'); // 震動馬達開關特徵值
  final Guid _serviceBatteryUuid = Guid('0000180f-0000-1000-8000-00805f9b34fb'); // 電池服務 UUID
  final Guid _charBatteryLevelUuid = Guid('00002a19-0000-1000-8000-00805f9b34fb'); // 電量百分比
  final Guid _charBatteryVoltageUuid = Guid('0000f001-0000-1000-8000-00805f9b34fb'); // 電壓
  final Guid _charBatteryChargeCurrentUuid = Guid('0000f002-0000-1000-8000-00805f9b34fb'); // 充電電流
  final Guid _charBatteryTemperatureUuid = Guid('0000f003-0000-1000-8000-00805f9b34fb'); // 溫度
  final Guid _charBatteryRemainingUuid = Guid('0000f004-0000-1000-8000-00805f9b34fb'); // 剩餘電量 mAh
  final Guid _charBatteryTimeToEmptyUuid = Guid('0000f005-0000-1000-8000-00805f9b34fb'); // 用完時間
  final Guid _charBatteryTimeToFullUuid = Guid('0000f006-0000-1000-8000-00805f9b34fb'); // 充滿時間
  final Guid _serviceDeviceInfoUuid = Guid('0000180a-0000-1000-8000-00805f9b34fb'); // 標準裝置資訊服務
  final Guid _charDeviceModelUuid = Guid('00002a24-0000-1000-8000-00805f9b34fb'); // 型號
  final Guid _charDeviceSerialUuid = Guid('00002a25-0000-1000-8000-00805f9b34fb'); // 序號
  final Guid _charFirmwareRevisionUuid = Guid('00002a26-0000-1000-8000-00805f9b34fb'); // 韌體版本
  final Guid _charHardwareRevisionUuid = Guid('00002a27-0000-1000-8000-00805f9b34fb'); // 硬體版本
  final Guid _charSoftwareRevisionUuid = Guid('00002a28-0000-1000-8000-00805f9b34fb'); // 軟體版本
  final Guid _charManufacturerUuid = Guid('00002a29-0000-1000-8000-00805f9b34fb'); // 製造商
  final Guid _serviceDeviceNameUuid =
      Guid('3ab441e7-11f8-4bbc-a004-7716126c8868'); // 自訂裝置名稱服務
  final Guid _charDeviceNameConfigUuid =
      Guid('1b18c3ee-013a-4cb1-9923-95dc798de376'); // 自訂裝置名稱特徵值
  final List<StreamSubscription<List<int>>> _notificationSubscriptions =
      []; // 收集所有感測通知的訂閱以便統一釋放
  BluetoothCharacteristic? _linearAccelerationCharacteristic; // 線性加速度特徵引用
  BluetoothCharacteristic? _gameRotationVectorCharacteristic; // Game Rotation Vector 特徵引用
  BluetoothCharacteristic? _buttonNotifyCharacteristic; // 按鈕事件特徵引用
  BluetoothCharacteristic? _motorControlCharacteristic; // 震動馬達控制特徵引用
  BluetoothCharacteristic? _batteryLevelCharacteristic; // 電量特徵引用
  BluetoothCharacteristic? _batteryVoltageCharacteristic; // 電壓特徵引用
  BluetoothCharacteristic? _batteryChargeCurrentCharacteristic; // 充電電流特徵引用
  BluetoothCharacteristic? _batteryTemperatureCharacteristic; // 溫度特徵引用
  BluetoothCharacteristic? _batteryRemainingCharacteristic; // 剩餘電量特徵引用
  BluetoothCharacteristic? _batteryTimeToEmptyCharacteristic; // 用完時間特徵引用
  BluetoothCharacteristic? _batteryTimeToFullCharacteristic; // 充滿時間特徵引用
  BluetoothCharacteristic? _deviceModelCharacteristic; // 型號資訊特徵引用
  BluetoothCharacteristic? _deviceSerialCharacteristic; // 序號資訊特徵引用
  BluetoothCharacteristic? _firmwareRevisionCharacteristic; // 韌體版本特徵引用
  BluetoothCharacteristic? _hardwareRevisionCharacteristic; // 硬體版本特徵引用
  BluetoothCharacteristic? _softwareRevisionCharacteristic; // 軟體版本特徵引用
  BluetoothCharacteristic? _manufacturerCharacteristic; // 製造商資訊特徵引用
  BluetoothCharacteristic? _deviceNameCharacteristic; // 自訂裝置名稱特徵引用
  Map<String, dynamic>? _latestLinearAcceleration; // 最新線性加速度資料
  Map<String, dynamic>? _latestGameRotationVector; // 最新 Game Rotation Vector 資料
  String _buttonStatusText = '尚未接收到按鈕事件'; // 最近一次按鈕敘述
  int? _buttonClickTimes; // 最近一次按鈕連擊次數
  int? _buttonEventCode; // 最近一次按鈕事件代碼
  DateTime? _lastButtonEventTime; // 最近一次按鈕事件時間
  String? _batteryLevelText; // 電量百分比顯示
  String? _batteryVoltageText; // 電壓顯示
  String? _batteryChargeCurrentText; // 充電電流顯示
  String? _batteryTemperatureText; // 溫度顯示
  String? _batteryRemainingText; // 剩餘電量顯示
  String? _batteryTimeToEmptyText; // 用完時間顯示
  String? _batteryTimeToFullText; // 充滿時間顯示
  String? _deviceModelName; // 裝置型號顯示
  String? _deviceSerialNumber; // 裝置序號顯示
  String? _firmwareRevision; // 韌體版本顯示
  String? _hardwareRevision; // 硬體版本顯示
  String? _softwareRevision; // 軟體版本顯示
  String? _manufacturerName; // 製造商顯示
  String? _customDeviceName; // 自訂裝置名稱顯示
  bool _isTriggeringMotor = false; // 是否正在觸發馬達震動
  late final List<RecordingHistoryEntry> _recordingHistory =
      List<RecordingHistoryEntry>.from(widget.initialHistory); // 累積曾經錄影的檔案資訊

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    _runtimeBlePermissions = _resolveRuntimeBlePermissions(); // 先針對平台建立權限清單
    _permissionsReady = _runtimeBlePermissions.isEmpty; // 若平台無需額外權限則直接視為已備妥
    initBluetooth(); // 啟動藍牙權限申請與自動搜尋流程
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _deviceConnectionSubscription?.cancel();
    if (_activeScanStopper != null && !_activeScanStopper!.isCompleted) {
      // 若仍有掃描流程在等待，主動結束避免懸掛 Future
      _activeScanStopper!.complete();
    }
    unawaited(_clearImuSession()); // 統一釋放所有藍牙訂閱與特徵引用
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ---------- 初始化流程 ----------
  /// 初始化藍牙狀態與權限，確保錄影前完成 IMU 配對
  Future<void> initBluetooth() async {
    _logBle('初始化藍牙流程');
    final permissionReady = await _requestBluetoothPermissions();
    if (!permissionReady) {
      // 權限不足時直接更新提示，避免進入掃描流程不斷拋錯
      if (mounted) {
        setState(() {
          _connectionMessage = '請先授權藍牙與定位權限後再開始搜尋';
        });
      }
      _logBle('初始化藍牙流程：權限未完全授權，暫停後續掃描');
    }

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
      _logBle('藍牙狀態變更：$state');

      if (state == BluetoothAdapterState.on && !isImuConnected && !_isScanning && !_isConnecting) {
        scanForImu();
      }
    });

    final initialState = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;
    setState(() => _adapterState = initialState);
    _logBle('取得當前藍牙狀態：$initialState');

    final connectedDevices = FlutterBluePlus.connectedDevices;
    if (!mounted) return;

    _logBle('系統回報已連線裝置數量：${connectedDevices.length}');

    for (final device in connectedDevices) {
      final services = await device.discoverServices();
      if (!_containsImuService(services)) {
        _logBle('啟動時略過裝置：${device.remoteId} 未包含 IMU 服務');
        continue;
      }
      _connectedDevice = device;
      _listenConnectionState(device);
      await _setupImuServices(services);
      if (!mounted) return;
      setState(() {
        _connectionState = BluetoothConnectionState.connected;
        _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
      });
      _logBle('啟動時即偵測到已連線裝置：${_resolveDeviceName(device)}');
      return;
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
  Future<bool> _requestBluetoothPermissions() async {
    if (_runtimeBlePermissions.isEmpty) {
      _logBle('當前平台無需額外藍牙權限，直接進入掃描流程');
      _permissionsReady = true;
      return true;
    }

    bool allGranted = true; // 記錄是否全部授權

    for (final entry in _runtimeBlePermissions.entries) {
      final permission = entry.key;
      final label = entry.value;
      final status = await permission.request();

      // 詳細紀錄授權結果，方便在 console 中比對裝置設定
      _logBle('權限請求結果：$label -> $status');

      if (!_isPermissionStatusGranted(status)) {
        allGranted = false;

        if (status.isPermanentlyDenied) {
          _logBle('權限 $label 被永久拒絕，需引導使用者前往系統設定');
        }
      }
    }

    if (!allGranted) {
      _logBle('藍牙或定位權限尚未完整授權，將阻擋掃描流程');
    }

    _permissionsReady = allGranted;
    return allGranted;
  }

  /// 依平台回傳需要申請的權限清單，避免要求不存在的藍牙權限
  Map<Permission, String> _resolveRuntimeBlePermissions() {
    if (Platform.isAndroid) {
      return {
        Permission.bluetoothScan: 'BLUETOOTH_SCAN',
        Permission.bluetoothConnect: 'BLUETOOTH_CONNECT',
        Permission.locationWhenInUse: 'ACCESS_FINE_LOCATION',
      };
    }

    if (Platform.isIOS) {
      return {
        Permission.bluetooth: 'BLUETOOTH',
        Permission.locationWhenInUse: 'LOCATION_WHEN_IN_USE',
      };
    }

    return {
      Permission.locationWhenInUse: 'ACCESS_FINE_LOCATION',
    };
  }

  /// 將 limited / provisional 等同於已允許，避免誤判為拒絕
  bool _isPermissionStatusGranted(PermissionStatus status) {
    if (status.isGranted) {
      return true;
    }
    return status == PermissionStatus.limited || status == PermissionStatus.provisional;
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
      _logBle('掃描中止：手機藍牙尚未開啟');
      return;
    }

    if (!_permissionsReady) {
      final permissionReady = await _requestBluetoothPermissions();
      if (!permissionReady) {
        if (!mounted) return;
        setState(() {
          _connectionMessage = '權限不足，請確認已允許藍牙掃描與定位';
        });
        _logBle('掃描中止：權限不足');
        return;
      }
    }

    await _stopScan(resetFoundDevice: true); // 先停止前一次掃描，遵循 Nordic 範例先清除舊狀態

    // 建立新的 completer，之後若外部主動停止掃描即可提前結束等待
    _activeScanStopper = Completer<void>();

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _connectionMessage = '以低延遲模式掃描相容的 IMU 裝置...';
      _scanCandidates.clear();
    });
    _logBle('開始掃描目標裝置，將掃描結果同步顯示於下方列表供使用者選擇');

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted || !_isScanning) {
        return;
      }

      final Map<String, _ImuScanCandidate> updatedEntries = {};
      bool hasUpdates = false;
      BluetoothDevice? autoSelectDevice;
      String? autoSelectName;
      int? autoSelectRssi;

      for (final result in results) {
        final advertisement = result.advertisementData;
        final advertisementName = advertisement.advName;
        final deviceName = result.device.platformName;
        final displayName = deviceName.isNotEmpty
            ? deviceName
            : (advertisementName.isNotEmpty ? advertisementName : '未命名裝置');
        final matchesImuService = _isImuAdvertisement(advertisement);

        final candidate = _ImuScanCandidate(
          device: result.device,
          displayName: displayName,
          rssi: result.rssi,
          matchesImuService: matchesImuService,
          lastSeen: DateTime.now(),
        );
        final id = result.device.remoteId.str;
        updatedEntries[id] = candidate;

        final existing = _scanCandidates[id];
        if (existing == null || existing.shouldUpdate(candidate)) {
          hasUpdates = true;
          _logBle(
              '掃描結果更新：$displayName (${result.device.remoteId.str}) RSSI=${result.rssi}，符合服務=$matchesImuService');
        }

        if (matchesImuService &&
            (_foundDevice == null ||
                _foundDevice?.remoteId == result.device.remoteId)) {
          autoSelectDevice = result.device;
          autoSelectName = displayName;
          autoSelectRssi = result.rssi;
        }
      }

      if ((hasUpdates || autoSelectDevice != null) && mounted) {
        setState(() {
          for (final entry in updatedEntries.entries) {
            _scanCandidates[entry.key] = entry.value;
          }
          if (autoSelectDevice != null) {
            _foundDevice = autoSelectDevice;
            _foundDeviceName = autoSelectName;
            _lastRssi = autoSelectRssi;
            _connectionMessage =
                '偵測到 ${autoSelectName ?? 'IMU 裝置'}，請點擊配對裝置以建立連線';
          }
        });
      }
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '搜尋失敗：$error';
      });
      _logBle('掃描流程發生錯誤', error: error);
      if (_activeScanStopper != null && !_activeScanStopper!.isCompleted) {
        _activeScanStopper!.completeError(error);
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        // 依 Nordic Android Library 建議使用低延遲掃描模式以提升連線準備速度
        androidScanMode: AndroidScanMode.lowLatency,
      );
      _logBle('已向系統請求開始掃描，等待裝置回應');

      // 最多等待 12 秒或直到外部主動停止掃描，避免掃描流程無限等待
      if (_activeScanStopper != null) {
        await Future.any([
          Future.delayed(const Duration(seconds: 12)),
          _activeScanStopper!.future,
        ]);
      } else {
        await Future.delayed(const Duration(seconds: 12));
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '無法開始掃描或找不到裝置：$e';
      });
      _logBle('掃描流程例外：$e', error: e, stackTrace: stackTrace);

      // 針對常見的權限錯誤補充更清楚的提示
      if (e is PlatformException &&
          e.code == 'startScan' &&
          (e.message?.contains('BLUETOOTH_SCAN') ?? false)) {
        _logBle('掃描流程例外：缺少 BLUETOOTH_SCAN 權限，提醒使用者前往系統設定開啟');
        if (mounted) {
          setState(() {
            _connectionMessage = '系統顯示缺少藍牙掃描權限，請至設定授權後再試';
          });
        }
      }
    } finally {
      await _stopScan();
      _activeScanStopper = null;
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        if (_scanCandidates.isEmpty) {
          _connectionMessage = '未找到符合條件的裝置，請確認 IMU 已開機並靠近手機';
        }
      });
      _logBle('掃描流程結束，已重置狀態');
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
    _logBle('準備連線至裝置：${_foundDeviceName ?? _resolveDeviceName(target)}');

    try {
      // 先嘗試中斷既有連線，確保流程以乾淨狀態開始
      await target.disconnect();
    } catch (_) {
      // 若裝置原本未連線會拋錯，忽略即可
      _logBle('預斷線時裝置可能未連線，忽略錯誤');
    }

    try {
      await target.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
      _logBle('已送出連線請求，等待裝置回覆');

      // 依 Nordic 流程完成 GATT 初始化：等待真正連線並探索服務
      await target.connectionState.firstWhere(
        (state) => state == BluetoothConnectionState.connected,
      );
      _logBle('裝置狀態已回報連線，開始探索服務');
      final services = await target.discoverServices();

      try {
        await target.requestMtu(247); // 嘗試提升 MTU 以利後續傳輸
        _logBle('MTU 調整成功，已設定為 247');
      } catch (error, stackTrace) {
        // 部分裝置不支援 MTU 調整，忽略錯誤即可
        _logBle('MTU 調整失敗，裝置可能不支援：$error', error: error, stackTrace: stackTrace);
      }

      _connectedDevice = target;
      _listenConnectionState(target);
      await _setupImuServices(services);
      if (!mounted) return;
      setState(() {
        _connectionMessage = '已連線至 ${_resolveDeviceName(target)}，可開始錄影';
      });
      _logBle('成功連線並完成服務初始化，裝置：${_resolveDeviceName(target)}');
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '連線流程失敗：$e';
        _connectedDevice = null;
      });
      _logBle('連線流程發生例外：$e', error: e, stackTrace: stackTrace);
      await _restartScanWithBackoff();
    } finally {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
      });
      _logBle('連線流程結束，已更新旗標狀態');
    }
  }

  /// 停止掃描流程並視需求重置搜尋結果，避免背景掃描持續耗電
  Future<void> _stopScan({bool resetFoundDevice = false}) async {
    _logBle('停止掃描流程，reset=$resetFoundDevice');
    if (_activeScanStopper != null && !_activeScanStopper!.isCompleted) {
      // 若外部正在等待掃描結束，這裡主動完成等待，避免卡住 Future.any
      _activeScanStopper!.complete();
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
    if (resetFoundDevice) {
      _foundDevice = null;
      _foundDeviceName = null;
      _lastRssi = null;
      _logBle('已清除先前掃描結果');
    }
  }

  /// 掃描逾時或連線失敗時等待片刻再重試，模擬 Nordic 範例的退避策略
  Future<void> _restartScanWithBackoff() async {
    _logBle('啟動退避掃描策略，等待 2 秒後重試');
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || _isScanning || _isConnecting) {
      _logBle('退避結束但目前無法重新掃描，mounted=$mounted、isScanning=$_isScanning、isConnecting=$_isConnecting');
      return;
    }
    _logBle('重新啟動掃描流程');
    await scanForImu();
  }

  /// 清除目前所有藍牙相關訂閱與狀態，確保重新連線時不會殘留舊資料
  Future<void> _clearImuSession({bool resetData = false}) async {
    _logBle('清理 IMU 連線會話，resetData=$resetData');
    await _cancelNotificationSubscriptions();
    _resetCharacteristicReferences();
    if (resetData && !mounted) {
      _resetImuDataState();
    }
  }

  /// 逐一取消感測特徵的訂閱監聽，避免背景串流持續觸發
  Future<void> _cancelNotificationSubscriptions() async {
    _logBle('取消所有感測通知訂閱，共 ${_notificationSubscriptions.length} 筆');
    for (final subscription in _notificationSubscriptions) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();
  }

  /// 將所有特徵引用歸零，避免誤用已經失效的 characteristic 物件
  void _resetCharacteristicReferences() {
    _logBle('重置所有特徵引用，避免使用到舊連線物件');
    _linearAccelerationCharacteristic = null;
    _gameRotationVectorCharacteristic = null;
    _buttonNotifyCharacteristic = null;
    _motorControlCharacteristic = null;
    _batteryLevelCharacteristic = null;
    _batteryVoltageCharacteristic = null;
    _batteryChargeCurrentCharacteristic = null;
    _batteryTemperatureCharacteristic = null;
    _batteryRemainingCharacteristic = null;
    _batteryTimeToEmptyCharacteristic = null;
    _batteryTimeToFullCharacteristic = null;
    _deviceModelCharacteristic = null;
    _deviceSerialCharacteristic = null;
    _firmwareRevisionCharacteristic = null;
    _hardwareRevisionCharacteristic = null;
    _softwareRevisionCharacteristic = null;
    _manufacturerCharacteristic = null;
    _deviceNameCharacteristic = null;
  }

  /// 重置所有感測顯示資料，讓 UI 反映目前沒有有效連線的狀態
  void _resetImuDataState() {
    _logBle('重置 IMU 顯示資料，等待重新連線');
    _latestLinearAcceleration = null;
    _latestGameRotationVector = null;
    _buttonStatusText = '尚未接收到按鈕事件';
    _buttonClickTimes = null;
    _buttonEventCode = null;
    _lastButtonEventTime = null;
    _batteryLevelText = null;
    _batteryVoltageText = null;
    _batteryChargeCurrentText = null;
    _batteryTemperatureText = null;
    _batteryRemainingText = null;
    _batteryTimeToEmptyText = null;
    _batteryTimeToFullText = null;
    _deviceModelName = null;
    _deviceSerialNumber = null;
    _firmwareRevision = null;
    _hardwareRevision = null;
    _softwareRevision = null;
    _manufacturerName = null;
    _customDeviceName = null;
    _isTriggeringMotor = false;
  }

  /// 監聽裝置連線狀態，若中斷則重新搜尋
  void _listenConnectionState(BluetoothDevice device) {
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = device.connectionState.listen((state) async {
      if (!mounted) return;

      if (state == BluetoothConnectionState.connected) {
        setState(() {
          _connectionState = state;
          _connectedDevice = device;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        _logBle('裝置持續回報連線狀態：${_resolveDeviceName(device)}');
        return;
      }

      if (state == BluetoothConnectionState.disconnected) {
        await _clearImuSession(resetData: true);
        if (!mounted) return;
        setState(() {
          _connectionState = state;
          _connectedDevice = null;
          _connectionMessage = '裝置已斷線，稍後自動重新搜尋';
          _resetImuDataState();
        });
        _logBle('裝置連線中斷，準備重新掃描：${device.remoteId.str}');
        _restartScanWithBackoff();
        return;
      }

      setState(() {
        _connectionState = state;
      });
      _logBle('裝置回報其他狀態：$state');
    });
  }

  /// 掃描完成後依據各個服務設定通知與初始值讀取，讓感測資料能即時更新
  Future<void> _setupImuServices(List<BluetoothService> services) async {
    await _cancelNotificationSubscriptions();
    _resetCharacteristicReferences();

    if (mounted) {
      setState(_resetImuDataState);
    } else {
      _resetImuDataState();
    }

    _logBle('開始建立 IMU 服務訂閱，共取得 ${services.length} 組服務');

    for (final service in services) {
      if (service.uuid == _serviceBno086Uuid) {
        _logBle('匹配到 BNO086 感測服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charLinearAccelerationUuid) {
            _linearAccelerationCharacteristic = characteristic;
            _logBle('已綁定線性加速度特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charGameRotationVectorUuid) {
            _gameRotationVectorCharacteristic = characteristic;
            _logBle('已綁定 Game Rotation Vector 特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceButtonUuid) {
        _logBle('匹配到按鈕事件服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charButtonNotifyUuid) {
            _buttonNotifyCharacteristic = characteristic;
            _logBle('已綁定按鈕通知特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceMotorUuid) {
        _logBle('匹配到馬達控制服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charMotorToggleUuid) {
            _motorControlCharacteristic = characteristic;
            _logBle('已綁定馬達控制特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceBatteryUuid) {
        _logBle('匹配到電池狀態服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charBatteryLevelUuid) {
            _batteryLevelCharacteristic = characteristic;
            _logBle('已綁定電量特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryVoltageUuid) {
            _batteryVoltageCharacteristic = characteristic;
            _logBle('已綁定電壓特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryChargeCurrentUuid) {
            _batteryChargeCurrentCharacteristic = characteristic;
            _logBle('已綁定充電電流特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryTemperatureUuid) {
            _batteryTemperatureCharacteristic = characteristic;
            _logBle('已綁定電池溫度特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryRemainingUuid) {
            _batteryRemainingCharacteristic = characteristic;
            _logBle('已綁定剩餘電量特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryTimeToEmptyUuid) {
            _batteryTimeToEmptyCharacteristic = characteristic;
            _logBle('已綁定預估用完時間特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charBatteryTimeToFullUuid) {
            _batteryTimeToFullCharacteristic = characteristic;
            _logBle('已綁定預估充滿時間特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceDeviceInfoUuid) {
        _logBle('匹配到裝置資訊服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charDeviceModelUuid) {
            _deviceModelCharacteristic = characteristic;
            _logBle('已綁定型號資訊特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charDeviceSerialUuid) {
            _deviceSerialCharacteristic = characteristic;
            _logBle('已綁定序號資訊特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charFirmwareRevisionUuid) {
            _firmwareRevisionCharacteristic = characteristic;
            _logBle('已綁定韌體版本特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charHardwareRevisionUuid) {
            _hardwareRevisionCharacteristic = characteristic;
            _logBle('已綁定硬體版本特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charSoftwareRevisionUuid) {
            _softwareRevisionCharacteristic = characteristic;
            _logBle('已綁定軟體版本特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charManufacturerUuid) {
            _manufacturerCharacteristic = characteristic;
            _logBle('已綁定製造商資訊特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceDeviceNameUuid) {
        _logBle('匹配到自訂名稱服務');
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charDeviceNameConfigUuid) {
            _deviceNameCharacteristic = characteristic;
            _logBle('已綁定自訂名稱特徵：${characteristic.uuid.str}');
          }
        }
      }
    }

    if (_linearAccelerationCharacteristic == null ||
        _gameRotationVectorCharacteristic == null ||
        _buttonNotifyCharacteristic == null) {
      _logBle('關鍵感測特徵缺失，請確認韌體是否支援最新規格', error: {
        'linear': _linearAccelerationCharacteristic != null,
        'rotation': _gameRotationVectorCharacteristic != null,
        'button': _buttonNotifyCharacteristic != null,
      });
    }

    if (_linearAccelerationCharacteristic != null) {
      _logBle('準備訂閱線性加速度通知');
      await _initCharacteristic(
        characteristic: _linearAccelerationCharacteristic!,
        onData: _handleLinearAccelerationPacket,
      );
    }

    if (_gameRotationVectorCharacteristic != null) {
      _logBle('準備訂閱 Game Rotation Vector 通知');
      await _initCharacteristic(
        characteristic: _gameRotationVectorCharacteristic!,
        onData: _handleGameRotationVectorPacket,
      );
    }

    if (_buttonNotifyCharacteristic != null) {
      _logBle('準備訂閱按鈕事件通知');
      await _initCharacteristic(
        characteristic: _buttonNotifyCharacteristic!,
        onData: _handleButtonPacket,
        listenToUpdates: true,
        readInitialValue: false,
      );
    }

    if (_batteryLevelCharacteristic != null) {
      _logBle('準備讀取電池電量資訊');
      await _initCharacteristic(
        characteristic: _batteryLevelCharacteristic!,
        onData: _updateBatteryLevel,
        listenToUpdates: _batteryLevelCharacteristic!.properties.notify,
      );
    }

    if (_batteryVoltageCharacteristic != null) {
      _logBle('準備讀取電池電壓資訊');
      await _initCharacteristic(
        characteristic: _batteryVoltageCharacteristic!,
        onData: _updateBatteryVoltage,
        listenToUpdates: _batteryVoltageCharacteristic!.properties.notify,
      );
    }

    if (_batteryChargeCurrentCharacteristic != null) {
      _logBle('準備讀取充電電流資訊');
      await _initCharacteristic(
        characteristic: _batteryChargeCurrentCharacteristic!,
        onData: _updateBatteryChargeCurrent,
        listenToUpdates: _batteryChargeCurrentCharacteristic!.properties.notify,
      );
    }

    if (_batteryTemperatureCharacteristic != null) {
      _logBle('準備讀取電池溫度資訊');
      await _initCharacteristic(
        characteristic: _batteryTemperatureCharacteristic!,
        onData: _updateBatteryTemperature,
        listenToUpdates: _batteryTemperatureCharacteristic!.properties.notify,
      );
    }

    if (_batteryRemainingCharacteristic != null) {
      _logBle('準備讀取剩餘電量資訊');
      await _initCharacteristic(
        characteristic: _batteryRemainingCharacteristic!,
        onData: _updateBatteryRemaining,
        listenToUpdates: _batteryRemainingCharacteristic!.properties.notify,
      );
    }

    if (_batteryTimeToEmptyCharacteristic != null) {
      _logBle('準備讀取預估用完時間資訊');
      await _initCharacteristic(
        characteristic: _batteryTimeToEmptyCharacteristic!,
        onData: _updateBatteryTimeToEmpty,
        listenToUpdates: _batteryTimeToEmptyCharacteristic!.properties.notify,
      );
    }

    if (_batteryTimeToFullCharacteristic != null) {
      _logBle('準備讀取預估充滿時間資訊');
      await _initCharacteristic(
        characteristic: _batteryTimeToFullCharacteristic!,
        onData: _updateBatteryTimeToFull,
        listenToUpdates: _batteryTimeToFullCharacteristic!.properties.notify,
      );
    }

    if (_deviceModelCharacteristic != null) {
      _logBle('準備讀取裝置型號資訊');
    }
    await _readAndAssignString(
      _deviceModelCharacteristic,
      (value) => _deviceModelName = value,
    );
    if (_deviceSerialCharacteristic != null) {
      _logBle('準備讀取序號資訊');
    }
    await _readAndAssignString(
      _deviceSerialCharacteristic,
      (value) => _deviceSerialNumber = value,
    );
    if (_firmwareRevisionCharacteristic != null) {
      _logBle('準備讀取韌體版本');
    }
    await _readAndAssignString(
      _firmwareRevisionCharacteristic,
      (value) => _firmwareRevision = value,
    );
    if (_hardwareRevisionCharacteristic != null) {
      _logBle('準備讀取硬體版本');
    }
    await _readAndAssignString(
      _hardwareRevisionCharacteristic,
      (value) => _hardwareRevision = value,
    );
    if (_softwareRevisionCharacteristic != null) {
      _logBle('準備讀取軟體版本');
    }
    await _readAndAssignString(
      _softwareRevisionCharacteristic,
      (value) => _softwareRevision = value,
    );
    if (_manufacturerCharacteristic != null) {
      _logBle('準備讀取製造商資訊');
    }
    await _readAndAssignString(
      _manufacturerCharacteristic,
      (value) => _manufacturerName = value,
    );
    if (_deviceNameCharacteristic != null) {
      _logBle('準備讀取自訂名稱資訊');
    }
    await _readAndAssignString(
      _deviceNameCharacteristic,
      (value) => _customDeviceName = value,
    );
  }

  /// 統一處理特徵值的通知與讀取邏輯，確保監聽與初始資料都能取得
  Future<void> _initCharacteristic({
    required BluetoothCharacteristic characteristic,
    required void Function(List<int>) onData,
    bool listenToUpdates = true,
    bool readInitialValue = true,
  }) async {
    if (listenToUpdates && (characteristic.properties.notify || characteristic.properties.indicate)) {
      try {
        await characteristic.setNotifyValue(true);
        _logBle('成功開啟通知：${characteristic.uuid.str}');
      } catch (error, stackTrace) {
        // 若裝置暫不支援通知則忽略錯誤
        _logBle('開啟通知失敗：${characteristic.uuid.str}，原因：$error', error: error, stackTrace: stackTrace);
      }
      final subscription = characteristic.lastValueStream.listen(
        onData,
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _connectionMessage = '讀取 ${characteristic.uuid.str} 時發生錯誤：$error';
          });
          _logBle('特徵通知流錯誤：${characteristic.uuid.str}，錯誤：$error', error: error);
        },
      );
      _notificationSubscriptions.add(subscription);
    }

    if (readInitialValue && characteristic.properties.read) {
      try {
        final value = await characteristic.read();
        if (value.isNotEmpty) {
          onData(value);
        }
        _logBle('已讀取初始值：${characteristic.uuid.str}，長度：${value.length}');
      } catch (error, stackTrace) {
        // 初始讀取失敗時暫不處理，等待後續通知補上資料
        _logBle('初始讀取失敗：${characteristic.uuid.str}，原因：$error', error: error, stackTrace: stackTrace);
      }
    }
  }

  /// 解析線性加速度封包，僅取最新一筆資料供 UI 顯示
  void _handleLinearAccelerationPacket(List<int> value) {
    if (value.length < 16) return;
    Map<String, dynamic>? sample;
    for (int offset = 0; offset + 15 < value.length; offset += 16) {
      sample = _parseThreeAxisSample(value, offset);
    }
    if (sample == null) return;
    if (!mounted) return;
    setState(() {
      _latestLinearAcceleration = sample;
    });
  }

  /// 解析 Game Rotation Vector 封包並儲存最後一次數據
  void _handleGameRotationVectorPacket(List<int> value) {
    if (value.length < 16) return;
    Map<String, dynamic>? sample;
    for (int offset = 0; offset + 15 < value.length; offset += 16) {
      sample = _parseRotationSample(value, offset);
    }
    if (sample == null) return;
    if (!mounted) return;
    setState(() {
      _latestGameRotationVector = sample;
    });
  }

  /// 解析三軸感測資料共同欄位（線性加速度、陀螺儀等格式相同）
  Map<String, dynamic>? _parseThreeAxisSample(List<int> data, int offset) {
    final timestamp = _readUint32At(data, offset + 4);
    final x = _readInt16At(data, offset + 8);
    final y = _readInt16At(data, offset + 10);
    final z = _readInt16At(data, offset + 12);
    if (timestamp == null || x == null || y == null || z == null) {
      return null;
    }
    return {
      'id': data[offset],
      'seq': data[offset + 1],
      'status': data[offset + 2],
      'timestampUs': timestamp,
      'x': x,
      'y': y,
      'z': z,
    };
  }

  /// 解析 Game Rotation Vector 專屬的四元數資料結構
  Map<String, dynamic>? _parseRotationSample(List<int> data, int offset) {
    final timestamp = _readUint32At(data, offset + 4);
    final i = _readInt16At(data, offset + 8);
    final j = _readInt16At(data, offset + 10);
    final k = _readInt16At(data, offset + 12);
    final real = _readInt16At(data, offset + 14);
    if (timestamp == null || i == null || j == null || k == null || real == null) {
      return null;
    }
    return {
      'id': data[offset],
      'seq': data[offset + 1],
      'status': data[offset + 2],
      'timestampUs': timestamp,
      'i': i,
      'j': j,
      'k': k,
      'real': real,
    };
  }

  /// 解析按鈕通知封包，轉換為可讀描述供 UI 顯示
  void _handleButtonPacket(List<int> value) {
    if (value.isEmpty) return;
    final raw = value.first;
    final clickTimes = (raw >> 4) & 0x0F;
    final eventCode = raw & 0x0F;
    final description = _describeButtonEvent(eventCode);
    _logBle('接收到按鈕事件：code=$eventCode、click=$clickTimes、raw=${value.first}');
    if (!mounted) return;
    setState(() {
      _buttonClickTimes = clickTimes;
      _buttonEventCode = eventCode;
      _lastButtonEventTime = DateTime.now();
      if (clickTimes > 1) {
        _buttonStatusText = '$description · 連擊 $clickTimes 次';
      } else {
        _buttonStatusText = description;
      }
    });
  }

  /// 將按鈕事件代碼轉成中文說明
  String _describeButtonEvent(int code) {
    switch (code) {
      case 0x01:
        return '短按開始';
      case 0x02:
        return '短按結束';
      case 0x03:
        return '長按開始';
      case 0x04:
        return '長按保持';
      case 0x05:
        return '長按結束';
      default:
        return '未知事件 (0x${code.toRadixString(16)})';
    }
  }

  /// 將單位為百分比的電量更新至狀態
  void _updateBatteryLevel(List<int> value) {
    if (value.isEmpty) return;
    final int level = value.first.clamp(0, 100).toInt();
    if (!mounted) return;
    setState(() {
      _batteryLevelText = '$level%';
    });
  }

  /// 解析毫伏資料
  void _updateBatteryVoltage(List<int> value) {
    final voltage = _readUint32At(value, 0);
    if (voltage == null || !mounted) return;
    setState(() {
      _batteryVoltageText = '${(voltage / 1000.0).toStringAsFixed(2)} V';
    });
  }

  /// 解析充電電流（mA）
  void _updateBatteryChargeCurrent(List<int> value) {
    final current = _readUint32At(value, 0);
    if (current == null || !mounted) return;
    setState(() {
      _batteryChargeCurrentText = '$current mA';
    });
  }

  /// 解析電池溫度（攝氏）
  void _updateBatteryTemperature(List<int> value) {
    final temperature = _readUint32At(value, 0);
    if (temperature == null || !mounted) return;
    setState(() {
      _batteryTemperatureText = '${(temperature / 100.0).toStringAsFixed(1)} °C';
    });
  }

  /// 解析剩餘電量（mAh）
  void _updateBatteryRemaining(List<int> value) {
    final remaining = _readUint32At(value, 0);
    if (remaining == null || !mounted) return;
    setState(() {
      _batteryRemainingText = '$remaining mAh';
    });
  }

  /// 解析剩餘使用時間（分鐘）
  void _updateBatteryTimeToEmpty(List<int> value) {
    final minutes = _readUint32At(value, 0);
    if (minutes == null || !mounted) return;
    setState(() {
      _batteryTimeToEmptyText = _formatMinutes(minutes);
    });
  }

  /// 解析充滿所需時間（分鐘）
  void _updateBatteryTimeToFull(List<int> value) {
    final minutes = _readUint32At(value, 0);
    if (minutes == null || !mounted) return;
    setState(() {
      _batteryTimeToFullText = _formatMinutes(minutes);
    });
  }

  /// 嘗試讀取 32bit 無號整數（小端序），若資料長度不足則回傳 null
  int? _readUint32At(List<int> data, int offset) {
    if (offset + 3 >= data.length) return null;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// 嘗試讀取 16bit 有號整數（小端序），若資料長度不足則回傳 null
  int? _readInt16At(List<int> data, int offset) {
    if (offset + 1 >= data.length) return null;
    final value = data[offset] | (data[offset + 1] << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  /// 將分鐘轉為可讀格式
  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainMinutes = minutes % 60;
    if (hours == 0) {
      return '$remainMinutes 分鐘';
    }
    return '${hours} 小時 ${remainMinutes} 分';
  }

  /// 讀取 UTF-8 編碼字串並清除尾端的 0x00
  Future<void> _readAndAssignString(
    BluetoothCharacteristic? characteristic,
    void Function(String value) assign,
  ) async {
    if (characteristic == null || !characteristic.properties.read) {
      _logBle('跳過讀取字串：特徵不存在或不可讀 ${characteristic?.uuid.str ?? 'null'}');
      return;
    }
    try {
      final value = await characteristic.read();
      final text = _decodeUtf8String(value);
      if (!mounted) return;
      setState(() {
        assign(text);
      });
      _logBle('成功讀取字串特徵：${characteristic.uuid.str}，內容：$text');
    } catch (error, stackTrace) {
      // 裝置若暫時無法讀取字串則忽略錯誤
      _logBle('讀取字串特徵失敗：${characteristic.uuid.str}，原因：$error', error: error, stackTrace: stackTrace);
    }
  }

  /// 將 byte array 轉為可讀字串，並移除尾端補零
  String _decodeUtf8String(List<int> data) {
    final trimmed = data.takeWhile((value) => value != 0).toList();
    if (trimmed.isEmpty) {
      return '';
    }
    return utf8.decode(trimmed, allowMalformed: true);
  }

  /// 透過寫入馬達特徵值觸發短暫震動，驗證馬達控制能力
  Future<void> _triggerMotorPulse() async {
    final characteristic = _motorControlCharacteristic;
    if (characteristic == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未取得馬達控制特徵，請確認裝置已連線。')),
      );
      return;
    }
    if (_isTriggeringMotor) {
      return; // 避免重複觸發造成裝置阻塞
    }
    setState(() => _isTriggeringMotor = true);

    final supportsWriteWithResponse = characteristic.properties.write;
    final supportsWriteWithoutResponse = characteristic.properties.writeWithoutResponse;
    final useWithoutResponse = !supportsWriteWithResponse && supportsWriteWithoutResponse;

    try {
      await characteristic.write([1], withoutResponse: useWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 600));
      await characteristic.write([0], withoutResponse: useWithoutResponse);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('啟動震動失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTriggeringMotor = false);
      } else {
        _isTriggeringMotor = false;
      }
    }
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

  /// 判斷服務列表是否包含 TekSwing IMU 相關 UUID
  bool _containsImuService(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid == _serviceBno086Uuid || service.uuid == _nordicUartServiceUuid) {
        return true;
      }
    }
    return false;
  }

  /// 根據廣播資料判斷是否為 IMU 裝置
  bool _isImuAdvertisement(AdvertisementData data) {
    // 以服務 UUID 為主進行比對，避免依賴容易變動的名稱
    final serviceUuids = data.serviceUuids;
    if (serviceUuids.contains(_serviceBno086Uuid) || serviceUuids.contains(_nordicUartServiceUuid)) {
      return true;
    }

    // 若廣播未列出 serviceUuids，改從 serviceData key 再檢查一次
    final serviceDataKeys = data.serviceData.keys;
    for (final key in serviceDataKeys) {
      if (key == _serviceBno086Uuid || key == _nordicUartServiceUuid) {
        return true;
      }
    }
    return false;
  }

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

  /// 共用的資訊列樣式，左側顯示圖示右側呈現標題與描述
  Widget _buildInfoRow(
    IconData icon,
    String title,
    String value, {
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF123B70)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 13, color: Color(0xFF465A71), height: 1.3),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8B6)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 感測資料區塊，整合按鈕、線性加速度與旋轉向量狀態
  Widget _buildSensorDataSection() {
    final linearSummary = _formatLinearAccelerationSummary(_latestLinearAcceleration);
    final linearMeta = _formatThreeAxisMeta(_latestLinearAcceleration);
    final rotationSummary = _formatRotationSummary(_latestGameRotationVector);
    final rotationMeta = _formatRotationMeta(_latestGameRotationVector);
    final List<String> buttonDetails = [];
    if (_buttonClickTimes != null && _buttonClickTimes! > 0) {
      buttonDetails.add('連擊 ${_buttonClickTimes!} 次');
    }
    if (_buttonEventCode != null) {
      buttonDetails.add('代碼 0x${_buttonEventCode!.toRadixString(16).padLeft(2, '0')}');
    }
    if (_lastButtonEventTime != null) {
      buttonDetails.add('最近 ${_formatTimeOfDay(_lastButtonEventTime!)}');
    }
    final buttonSubtitle = buttonDetails.isEmpty ? null : buttonDetails.join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '感測資料',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF123B70),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.smart_button, '按鈕事件', _buttonStatusText, subtitle: buttonSubtitle),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.trending_up, '線性加速度', linearSummary, subtitle: linearMeta),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.threed_rotation, 'Game Rotation Vector', rotationSummary, subtitle: rotationMeta),
      ],
    );
  }

  /// 電池與充電狀態資訊
  Widget _buildBatterySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '電池資訊',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF123B70),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.battery_full, '電量', _batteryLevelText ?? '等待裝置回報'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.bolt, '電壓', _batteryVoltageText ?? '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.flash_on, '充電電流', _batteryChargeCurrentText ?? '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.thermostat, '電池溫度', _batteryTemperatureText ?? '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.storage, '剩餘電量', _batteryRemainingText ?? '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.timer, '使用時間預估', _batteryTimeToEmptyText ?? '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.hourglass_bottom, '充滿所需時間', _batteryTimeToFullText ?? '--'),
      ],
    );
  }

  /// 裝置資訊區塊，顯示韌體與硬體等資料
  Widget _buildDeviceInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '裝置資訊',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF123B70),
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.badge, '自訂名稱', _customDeviceName?.isNotEmpty == true ? _customDeviceName! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.device_hub, '裝置型號', _deviceModelName?.isNotEmpty == true ? _deviceModelName! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.confirmation_number, '序號', _deviceSerialNumber?.isNotEmpty == true ? _deviceSerialNumber! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.system_update, '韌體版本', _firmwareRevision?.isNotEmpty == true ? _firmwareRevision! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.memory, '硬體版本', _hardwareRevision?.isNotEmpty == true ? _hardwareRevision! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.code, '軟體版本', _softwareRevision?.isNotEmpty == true ? _softwareRevision! : '--'),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.factory, '製造商', _manufacturerName?.isNotEmpty == true ? _manufacturerName! : '--'),
      ],
    );
  }

  /// 震動馬達測試按鈕，協助確認馬達控制是否可用
  Widget _buildMotorControlSection() {
    final bool motorAvailable = _motorControlCharacteristic != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.vibration, color: Color(0xFF123B70)),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '點擊可觸發裝置震動，確認提醒功能是否正常運作。',
            style: TextStyle(fontSize: 13, color: Color(0xFF465A71)),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(
          onPressed: motorAvailable && !_isTriggeringMotor ? _triggerMotorPulse : null,
          child: _isTriggeringMotor
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('震動測試'),
        ),
      ],
    );
  }

  /// 將線性加速度資料轉成可讀摘要
  String _formatLinearAccelerationSummary(Map<String, dynamic>? sample) {
    if (sample == null) {
      return '等待裝置傳送資料';
    }
    final x = sample['x'];
    final y = sample['y'];
    final z = sample['z'];
    return 'X: $x · Y: $y · Z: $z (raw)';
  }

  /// 顯示線性加速度額外資訊（序號、狀態、時間）
  String? _formatThreeAxisMeta(Map<String, dynamic>? sample) {
    if (sample == null) {
      return null;
    }
    final seq = sample['seq'];
    final status = sample['status'];
    final timestamp = sample['timestampUs'];
    return '序號 $seq · 狀態 $status · 時間標籤 ${timestamp ?? '--'} μs';
  }

  /// 將四元數資訊轉成摘要文字
  String _formatRotationSummary(Map<String, dynamic>? sample) {
    if (sample == null) {
      return '等待裝置傳送資料';
    }
    final i = sample['i'];
    final j = sample['j'];
    final k = sample['k'];
    final real = sample['real'];
    return 'i: $i · j: $j · k: $k · real: $real';
  }

  /// 顯示四元數額外資訊
  String? _formatRotationMeta(Map<String, dynamic>? sample) {
    if (sample == null) {
      return null;
    }
    final seq = sample['seq'];
    final status = sample['status'];
    final timestamp = sample['timestampUs'];
    return '序號 $seq · 狀態 $status · 時間標籤 ${timestamp ?? '--'} μs';
  }

  /// 將時間格式化為 HH:mm:ss 字串
  String _formatTimeOfDay(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  /// 建構 IMU 連線卡片，提示使用者完成藍牙配對
  Widget _buildImuConnectionCard() {
    final bool connected = isImuConnected;
    final bool hasCandidate = _foundDevice != null;
    final String displayName = connected
        ? _resolveDeviceName(_connectedDevice!)
        : (_foundDeviceName ?? 'IMU 裝置');
    final String signalText = _lastRssi != null ? '訊號 ${_lastRssi} dBm' : '訊號偵測中';

    final String batteryOverview = _batteryLevelText ?? '電量讀取中';
    final String firmwareOverview =
        (_firmwareRevision?.isNotEmpty == true) ? _firmwareRevision! : '韌體資訊更新中';

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
                      '電量 $batteryOverview · $firmwareOverview',
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
                onPressed:
                    (connected || _isConnecting || !hasCandidate) ? null : connectToImu,
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
                        connected
                            ? '已連線'
                            : (hasCandidate ? '配對裝置' : '等待裝置'),
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
          if (!connected) ...[
            const SizedBox(height: 20),
            _buildScanCandidatesSection(),
          ],
          if (connected) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            _buildSensorDataSection(),
            const SizedBox(height: 20),
            _buildBatterySection(),
            const SizedBox(height: 20),
            _buildDeviceInfoSection(),
            const SizedBox(height: 20),
            _buildMotorControlSection(),
          ],
        ],
      ),
    );
  }

  /// 建構掃描結果列表，列出目前搜尋到的藍牙裝置供使用者挑選
  Widget _buildScanCandidatesSection() {
    if (_scanCandidates.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E8F0)),
        ),
        child: Text(
          _isScanning
              ? '正在掃描中，請稍候數秒以取得周邊裝置列表。'
              : '尚未掃描到符合條件的裝置，請確認 IMU 已開機並靠近手機。',
          style: const TextStyle(fontSize: 13, color: Color(0xFF7D8B9A)),
        ),
      );
    }

    final List<_ImuScanCandidate> entries = _scanCandidates.values.toList()
      ..sort((a, b) {
        if (a.matchesImuService != b.matchesImuService) {
          return a.matchesImuService ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '掃描到的裝置',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF123B70),
          ),
        ),
        const SizedBox(height: 12),
        for (final candidate in entries) _buildScanCandidateTile(candidate),
      ],
    );
  }

  /// 建構單一掃描結果卡片，提供裝置資訊與選擇按鈕
  Widget _buildScanCandidateTile(_ImuScanCandidate candidate) {
    final bool isSelected =
        _foundDevice?.remoteId == candidate.device.remoteId;
    final bool matchesService = candidate.matchesImuService;
    final Color borderColor = isSelected
        ? const Color(0xFF123B70)
        : (matchesService ? const Color(0xFF1E8E5A) : const Color(0xFFE1E8F0));
    final Color iconColor = matchesService
        ? const Color(0xFF1E8E5A)
        : const Color(0xFF7D8B9A);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE8F0FF) : const Color(0xFFF9FBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Row(
        children: [
          Icon(
            matchesService ? Icons.sensors : Icons.bluetooth_searching,
            color: iconColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF123B70),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${matchesService ? '含 IMU 服務' : '未標示 IMU 服務'} · RSSI ${candidate.rssi} dBm',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7D8B9A)),
                ),
                const SizedBox(height: 2),
                Text(
                  '最後出現：${_formatTimeOfDay(candidate.lastSeen)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9AA8B6)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: _isConnecting ? null : () => _selectScanCandidate(candidate),
            child: Text(isSelected ? '準備連線' : '選擇'),
          ),
        ],
      ),
    );
  }

  /// 設定使用者選取的藍牙裝置並更新提示文字
  void _selectScanCandidate(_ImuScanCandidate candidate) {
    if (_isConnecting) {
      return; // 連線流程進行中時避免切換目標造成混亂
    }
    _logBle('使用者選取裝置：${candidate.displayName} (${candidate.device.remoteId.str})');
    if (!mounted) return;
    setState(() {
      _foundDevice = candidate.device;
      _foundDeviceName = candidate.displayName;
      _lastRssi = candidate.rssi;
      _connectionMessage = '已選擇 ${candidate.displayName}，請按下方按鈕開始配對';
    });
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

/// 代表一次掃描到的藍牙裝置資訊，便於建立列表顯示與更新判斷
class _ImuScanCandidate {
  final BluetoothDevice device; // 對應的藍牙裝置物件
  final String displayName; // 顯示於 UI 的名稱
  final int rssi; // 訊號強度，單位 dBm
  final bool matchesImuService; // 是否包含 IMU 相關服務 UUID
  final DateTime lastSeen; // 最近一次在掃描結果中出現的時間

  const _ImuScanCandidate({
    required this.device,
    required this.displayName,
    required this.rssi,
    required this.matchesImuService,
    required this.lastSeen,
  });

  /// 判斷是否需要以新的掃描結果覆蓋目前資料
  bool shouldUpdate(_ImuScanCandidate other) {
    if (other.matchesImuService != matchesImuService) {
      return true;
    }
    if (other.rssi != rssi) {
      return true;
    }
    // 若超過 1 秒未更新則刷新顯示時間，確保列表資訊保持即時
    return other.lastSeen.difference(lastSeen).inSeconds.abs() >= 1;
  }
}
