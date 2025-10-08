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
import 'services/imu_data_logger.dart';
import 'services/recording_history_storage.dart';

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

/// 定義 IMU 佩戴位置的插槽，方便多裝置管理
enum _ImuSlotType { rightWrist, chest }

extension _ImuSlotInfo on _ImuSlotType {
  /// CSV 檔案名稱需使用英文字面固定格式
  String get csvName => this == _ImuSlotType.rightWrist ? 'RIGHT_WRIST' : 'CHEST';

  /// 顯示於 UI 的中文名稱
  String get displayLabel => this == _ImuSlotType.rightWrist ? '右手腕 IMU' : '胸前 IMU';
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
  StreamSubscription<BluetoothConnectionState>? _secondDeviceConnectionSubscription; // 胸前 IMU 連線狀態監聽

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown; // 目前藍牙狀態
  BluetoothDevice? _foundDevice; // 已搜尋到的目標 IMU 裝置
  BluetoothDevice? _connectedDevice; // 已成功連線的 IMU 裝置（預設視為右手腕）
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected; // 右手腕 IMU 連線狀態
  BluetoothDevice? _secondDevice; // 已成功連線的胸前 IMU 裝置
  BluetoothConnectionState _secondConnectionState =
      BluetoothConnectionState.disconnected; // 胸前 IMU 連線狀態

  bool _isScanning = false; // 是否正在搜尋裝置
  bool _isConnecting = false; // 是否正處於連線流程
  bool _isOpeningSession = false; // 是否正在切換至錄影頁面
  bool _permissionsReady = false; // 記錄藍牙權限是否已完整授權
  late final Map<Permission, String> _runtimeBlePermissions; // 不同平台需申請的權限列表
  int _selectedRounds = 5; // 使用者預設要錄影的次數
  int _recordingDurationSeconds = 15; // 使用者預設每次錄影長度（秒）
  String _connectionMessage = '尚未搜尋到 IMU 裝置'; // 右手腕 IMU 狀態文字
  String _chestConnectionMessage = '尚未搜尋到胸前 IMU 裝置'; // 胸前 IMU 狀態文字
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
  final Guid _cccdUuid = Guid('00002902-0000-1000-8000-00805f9b34fb'); // 通知控制描述符 UUID
  final List<StreamSubscription<List<int>>> _notificationSubscriptions =
      []; // 右手腕感測通知訂閱
  final List<StreamSubscription<List<int>>> _secondNotificationSubscriptions =
      []; // 胸前感測通知訂閱
  BluetoothCharacteristic? _linearAccelerationCharacteristic; // 線性加速度特徵引用
  BluetoothCharacteristic? _gameRotationVectorCharacteristic; // Game Rotation Vector 特徵引用
  BluetoothCharacteristic? _secondLinearAccelerationCharacteristic; // 胸前線性加速度特徵引用
  BluetoothCharacteristic? _secondGameRotationVectorCharacteristic; // 胸前 Game Rotation Vector 特徵引用
  BluetoothCharacteristic? _buttonNotifyCharacteristic; // 按鈕事件特徵引用（右手腕專用）
  BluetoothCharacteristic? _motorControlCharacteristic; // 右手腕震動馬達控制特徵
  BluetoothCharacteristic? _secondMotorControlCharacteristic; // 胸前震動馬達控制特徵
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
  Map<String, dynamic>? _latestLinearAcceleration; // 右手腕線性加速度資料
  Map<String, dynamic>? _latestGameRotationVector; // 右手腕 Game Rotation Vector 資料
  Map<String, dynamic>? _secondLatestLinearAcceleration; // 胸前線性加速度資料
  Map<String, dynamic>? _secondLatestGameRotationVector; // 胸前 Game Rotation Vector 資料
  Timer? _gameRotationFallbackTimer; // 右手腕 Game Rotation Vector 補償讀取計時器
  bool _isGameRotationFallbackReading = false; // 避免補償讀取重入
  DateTime? _lastGameRotationUpdate; // 右手腕最近一次 Game Rotation Vector 時間
  int? _lastGameRotationSeq; // 右手腕 Game Rotation Vector 序號
  int? _lastGameRotationTimestamp; // 右手腕 Game Rotation Vector 時間戳
  Timer? _secondGameRotationFallbackTimer; // 胸前 Game Rotation Vector 補償讀取計時器
  bool _isSecondGameRotationFallbackReading = false; // 胸前補償讀取重入保護
  DateTime? _secondLastGameRotationUpdate; // 胸前最近一次 Game Rotation Vector 時間
  int? _secondLastGameRotationSeq; // 胸前 Game Rotation Vector 序號
  int? _secondLastGameRotationTimestamp; // 胸前 Game Rotation Vector 時間戳
  String _buttonStatusText = '尚未接收到按鈕事件'; // 最近一次按鈕敘述
  int? _buttonClickTimes; // 最近一次按鈕連擊次數
  int? _buttonEventCode; // 最近一次按鈕事件代碼
  DateTime? _lastButtonEventTime; // 最近一次按鈕事件時間
  DateTime? _lastButtonTriggerTime; // 最近一次透過按鈕自動開啟錄影的時間
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
  bool _isTriggeringRightMotor = false; // 右手腕震動是否進行中
  bool _isTriggeringChestMotor = false; // 胸前震動是否進行中
  late final List<RecordingHistoryEntry> _recordingHistory =
      List<RecordingHistoryEntry>.from(widget.initialHistory); // 累積曾經錄影的檔案資訊
  final _BleOperationQueue _bleOperationQueue =
      _BleOperationQueue(); // 排程 BLE 寫入請求，避免同時寫入造成忙碌錯誤
  final StreamController<void> _imuButtonController = StreamController<void>.broadcast();
  // IMU 按鈕事件廣播器，讓錄影頁面可以同步收到硬體按鈕觸發
  bool _isSessionPageVisible = false; // 是否已顯示錄影頁面，避免重複開啟

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    unawaited(_restorePersistedHistory()); // 優先同步既有歷史，避免清單被清空
    _runtimeBlePermissions = _resolveRuntimeBlePermissions(); // 先針對平台建立權限清單
    _permissionsReady = _runtimeBlePermissions.isEmpty; // 若平台無需額外權限則直接視為已備妥
    initBluetooth(); // 啟動藍牙權限申請與自動搜尋流程
  }

  /// 從本機檔案還原歷史紀錄，確保重整頁面後資料仍存在
  Future<void> _restorePersistedHistory() async {
    final stored = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;

    if (stored.isEmpty) {
      return; // 本地沒有紀錄時維持原狀，避免誤清空記憶中的清單
    }

    final currentPaths = _recordingHistory.map((e) => e.filePath).toList();
    final storedPaths = stored.map((e) => e.filePath).toList();
    final isSameLength = currentPaths.length == storedPaths.length;
    var isSameOrder = isSameLength;
    if (isSameOrder) {
      for (var i = 0; i < currentPaths.length; i++) {
        if (currentPaths[i] != storedPaths[i]) {
          isSameOrder = false;
          break;
        }
      }
    }

    if (isSameOrder) {
      return; // 若內容一致則不重複觸發重繪
    }

    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(stored);
    });
    widget.onHistoryChanged(List<RecordingHistoryEntry>.from(_recordingHistory));
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _deviceConnectionSubscription?.cancel();
    _secondDeviceConnectionSubscription?.cancel();
    if (_activeScanStopper != null && !_activeScanStopper!.isCompleted) {
      // 若仍有掃描流程在等待，主動結束避免懸掛 Future
      _activeScanStopper!.complete();
    }
    if (_connectedDevice != null) {
      ImuDataLogger.instance.unregisterDevice(_connectedDevice!.remoteId.str);
    }
    if (_secondDevice != null) {
      ImuDataLogger.instance.unregisterDevice(_secondDevice!.remoteId.str);
    }
    unawaited(_clearImuSession()); // 統一釋放所有藍牙訂閱與特徵引用
    unawaited(_clearSecondImuSession()); // 同步釋放第二顆 IMU 的資源
    FlutterBluePlus.stopScan();
    _bleOperationQueue.dispose(); // 中止尚未執行的 BLE 任務，避免頁面離開後仍呼叫底層 API
    _imuButtonController.close(); // 關閉按鈕事件廣播，避免記憶體洩漏
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
      if (_connectedDevice == null) {
        _connectedDevice = device;
        _listenConnectionState(device);
        ImuDataLogger.instance.registerDevice(
          device,
          displayName: _resolveDeviceName(device),
          slotAlias: _ImuSlotType.rightWrist.csvName,
        );
        await _setupPrimaryImuServices(services);
        if (!mounted) return;
        setState(() {
          _connectionState = BluetoothConnectionState.connected;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        _logBle('啟動時即偵測到右手腕 IMU：${_resolveDeviceName(device)}');
        continue;
      }

      if (_secondDevice == null) {
        _secondDevice = device;
        _listenSecondConnectionState(device);
        ImuDataLogger.instance.registerDevice(
          device,
          displayName: _resolveDeviceName(device),
          slotAlias: _ImuSlotType.chest.csvName,
        );
        await _setupSecondImuServices(services);
        if (!mounted) return;
        setState(() {
          _secondConnectionState = BluetoothConnectionState.connected;
          _chestConnectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        _logBle('啟動時即偵測到胸前 IMU：${_resolveDeviceName(device)}');
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
  Future<void> connectToImu({
    _ImuSlotType slot = _ImuSlotType.rightWrist,
    BluetoothDevice? candidate,
    String? candidateName,
  }) async {
    final target = candidate ??
        (slot == _ImuSlotType.rightWrist
            ? (_foundDevice ?? _connectedDevice)
            : _secondDevice);
    if (target == null) {
      await scanForImu();
      return;
    }

    final displayName = candidateName ?? _resolveDeviceName(target);

    await _stopScan();

    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      if (slot == _ImuSlotType.rightWrist) {
        _connectionMessage = '正在與 $displayName 建立連線...';
      } else {
        _chestConnectionMessage = '正在與 $displayName 建立連線...';
      }
    });
    _logBle('準備連線至 ${slot.displayLabel}：$displayName');

    try {
      await target.disconnect();
    } catch (_) {
      _logBle('預斷線時裝置可能未連線，忽略錯誤');
    }

    if (slot == _ImuSlotType.rightWrist && _connectedDevice != null) {
      ImuDataLogger.instance.unregisterDevice(_connectedDevice!.remoteId.str);
    }
    if (slot == _ImuSlotType.chest && _secondDevice != null) {
      ImuDataLogger.instance.unregisterDevice(_secondDevice!.remoteId.str);
    }

    if (slot == _ImuSlotType.rightWrist) {
      await _clearImuSession();
    } else {
      await _clearSecondImuSession();
    }

    try {
      await target.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
      _logBle('已送出連線請求，等待裝置回覆');

      await target.connectionState.firstWhere(
        (state) => state == BluetoothConnectionState.connected,
      );
      _logBle('裝置狀態已回報連線，開始探索服務');
      final services = await target.discoverServices();

      try {
        await target.requestMtu(247);
        _logBle('MTU 調整成功，已設定為 247');
      } catch (error, stackTrace) {
        _logBle('MTU 調整失敗，裝置可能不支援：$error',
            error: error, stackTrace: stackTrace);
      }

      if (slot == _ImuSlotType.rightWrist) {
        _connectedDevice = target;
        _listenConnectionState(target);
        ImuDataLogger.instance.registerDevice(
          target,
          displayName: displayName,
          slotAlias: slot.csvName,
        );
        await _setupPrimaryImuServices(services);
        if (!mounted) return;
        setState(() {
          _connectionMessage = '已連線至 $displayName，右手腕感測資料就緒';
        });
      } else {
        _secondDevice = target;
        _listenSecondConnectionState(target);
        ImuDataLogger.instance.registerDevice(
          target,
          displayName: displayName,
          slotAlias: slot.csvName,
        );
        await _setupSecondImuServices(services);
        if (!mounted) return;
        setState(() {
          _chestConnectionMessage = '已連線至 $displayName，胸前感測資料就緒';
        });
      }

      _logBle('成功連線並完成服務初始化：${slot.displayLabel} -> $displayName');
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        if (slot == _ImuSlotType.rightWrist) {
          _connectionMessage = '連線流程失敗：$e';
          _connectedDevice = null;
        } else {
          _chestConnectionMessage = '連線流程失敗：$e';
          _secondDevice = null;
        }
      });
      if (slot == _ImuSlotType.rightWrist) {
        await _clearImuSession(resetData: true);
      } else {
        await _clearSecondImuSession(resetData: true);
      }
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
    _cancelGameRotationFallbackTimer();
    _resetCharacteristicReferences();
    if (resetData) {
      if (mounted) {
        setState(_resetImuDataState);
      } else {
        _resetImuDataState();
      }
    }
  }

  /// 清除第二顆 IMU 的連線資訊與感測訂閱
  Future<void> _clearSecondImuSession({bool resetData = false}) async {
    _logBle('清理第二顆 IMU 連線會話，resetData=$resetData');
    await _cancelSecondNotificationSubscriptions();
    _cancelSecondGameRotationFallbackTimer();
    _resetSecondCharacteristicReferences();
    if (resetData) {
      if (mounted) {
        setState(_resetSecondImuDataState);
      } else {
        _resetSecondImuDataState();
      }
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

  /// 取消胸前 IMU 的所有通知訂閱
  Future<void> _cancelSecondNotificationSubscriptions() async {
    _logBle('取消胸前 IMU 通知訂閱，共 ${_secondNotificationSubscriptions.length} 筆');
    for (final subscription in _secondNotificationSubscriptions) {
      await subscription.cancel();
    }
    _secondNotificationSubscriptions.clear();
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

  /// 重置胸前 IMU 的特徵引用
  void _resetSecondCharacteristicReferences() {
    _secondLinearAccelerationCharacteristic = null;
    _secondGameRotationVectorCharacteristic = null;
    _secondMotorControlCharacteristic = null;
  }

  /// 重置所有感測顯示資料，讓 UI 反映目前沒有有效連線的狀態
  void _resetImuDataState() {
    _logBle('重置 IMU 顯示資料，等待重新連線');
    _latestLinearAcceleration = null;
    _latestGameRotationVector = null;
    _lastGameRotationUpdate = null;
    _lastGameRotationSeq = null;
    _lastGameRotationTimestamp = null;
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
    _isTriggeringRightMotor = false;
  }

  /// 重置胸前 IMU 的顯示資料，主要影響 CSV 與除錯資訊
  void _resetSecondImuDataState() {
    _secondLatestLinearAcceleration = null;
    _secondLatestGameRotationVector = null;
    _secondLastGameRotationUpdate = null;
    _secondLastGameRotationSeq = null;
    _secondLastGameRotationTimestamp = null;
    _isTriggeringChestMotor = false;
  }

  /// 依插槽取得對應的馬達控制特徵，方便共用判斷邏輯
  BluetoothCharacteristic? _motorCharacteristicForSlot(_ImuSlotType slot) =>
      slot == _ImuSlotType.rightWrist ? _motorControlCharacteristic : _secondMotorControlCharacteristic;

  /// 檢查指定插槽是否仍在執行震動任務，避免重複送出寫入
  bool _isMotorBusyForSlot(_ImuSlotType slot) =>
      slot == _ImuSlotType.rightWrist ? _isTriggeringRightMotor : _isTriggeringChestMotor;

  /// 更新震動狀態並同步考量元件是否仍掛載，確保不會在 dispose 後 setState
  void _setMotorBusyForSlot(_ImuSlotType slot, bool value) {
    if (!mounted) {
      if (slot == _ImuSlotType.rightWrist) {
        _isTriggeringRightMotor = value;
      } else {
        _isTriggeringChestMotor = value;
      }
      return;
    }

    setState(() {
      if (slot == _ImuSlotType.rightWrist) {
        _isTriggeringRightMotor = value;
      } else {
        _isTriggeringChestMotor = value;
      }
    });
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
        ImuDataLogger.instance.unregisterDevice(device.remoteId.str);
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

  /// 監聽胸前 IMU 的連線狀態
  void _listenSecondConnectionState(BluetoothDevice device) {
    _secondDeviceConnectionSubscription?.cancel();
    _secondDeviceConnectionSubscription = device.connectionState.listen((state) async {
      if (!mounted) return;

      if (state == BluetoothConnectionState.connected) {
        setState(() {
          _secondConnectionState = state;
          _secondDevice = device;
          _chestConnectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        _logBle('胸前裝置持續回報連線狀態：${_resolveDeviceName(device)}');
        return;
      }

      if (state == BluetoothConnectionState.disconnected) {
        await _clearSecondImuSession(resetData: true);
        ImuDataLogger.instance.unregisterDevice(device.remoteId.str);
        if (!mounted) return;
        setState(() {
          _secondConnectionState = state;
          _secondDevice = null;
          _chestConnectionMessage = '胸前裝置已斷線，稍後自動重新搜尋';
          _resetSecondImuDataState();
        });
        _logBle('胸前裝置連線中斷，準備重新掃描：${device.remoteId.str}');
        _restartScanWithBackoff();
        return;
      }

      setState(() {
        _secondConnectionState = state;
      });
      _logBle('胸前裝置回報其他狀態：$state');
    });
  }

  /// 掃描完成後依據各個服務設定通知與初始值讀取，讓感測資料能即時更新
  Future<void> _setupPrimaryImuServices(List<BluetoothService> services) async {
    await _cancelNotificationSubscriptions();
    _cancelGameRotationFallbackTimer();
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
      final characteristic = _gameRotationVectorCharacteristic!;
      final isListening = await _initCharacteristic(
        characteristic: characteristic,
        onData: _handleGameRotationVectorPacket,
        readInitialValue: false, // 避免裝置禁止讀取時立刻拋出例外
      );
      _startGameRotationFallbackTimer(
        notificationActive: isListening,
        canReadCharacteristic: characteristic.properties.read,
      );
    }

    if (_buttonNotifyCharacteristic != null) {
      _logBle('準備訂閱按鈕事件通知');
      await _initCharacteristic(
        characteristic: _buttonNotifyCharacteristic!,
        onData: (_, value) => _handleButtonPacket(value),
        listenToUpdates: true,
        readInitialValue: false,
      );
    }

    if (_batteryLevelCharacteristic != null) {
      _logBle('準備讀取電池電量資訊');
      await _initCharacteristic(
        characteristic: _batteryLevelCharacteristic!,
        onData: (_, value) => _updateBatteryLevel(value),
        listenToUpdates: _batteryLevelCharacteristic!.properties.notify,
      );
    }

    if (_batteryVoltageCharacteristic != null) {
      _logBle('準備讀取電池電壓資訊');
      await _initCharacteristic(
        characteristic: _batteryVoltageCharacteristic!,
        onData: (_, value) => _updateBatteryVoltage(value),
        listenToUpdates: _batteryVoltageCharacteristic!.properties.notify,
      );
    }

    if (_batteryChargeCurrentCharacteristic != null) {
      _logBle('準備讀取充電電流資訊');
      await _initCharacteristic(
        characteristic: _batteryChargeCurrentCharacteristic!,
        onData: (_, value) => _updateBatteryChargeCurrent(value),
        listenToUpdates: _batteryChargeCurrentCharacteristic!.properties.notify,
      );
    }

    if (_batteryTemperatureCharacteristic != null) {
      _logBle('準備讀取電池溫度資訊');
      await _initCharacteristic(
        characteristic: _batteryTemperatureCharacteristic!,
        onData: (_, value) => _updateBatteryTemperature(value),
        listenToUpdates: _batteryTemperatureCharacteristic!.properties.notify,
      );
    }

    if (_batteryRemainingCharacteristic != null) {
      _logBle('準備讀取剩餘電量資訊');
      await _initCharacteristic(
        characteristic: _batteryRemainingCharacteristic!,
        onData: (_, value) => _updateBatteryRemaining(value),
        listenToUpdates: _batteryRemainingCharacteristic!.properties.notify,
      );
    }

    if (_batteryTimeToEmptyCharacteristic != null) {
      _logBle('準備讀取預估用完時間資訊');
      await _initCharacteristic(
        characteristic: _batteryTimeToEmptyCharacteristic!,
        onData: (_, value) => _updateBatteryTimeToEmpty(value),
        listenToUpdates: _batteryTimeToEmptyCharacteristic!.properties.notify,
      );
    }

    if (_batteryTimeToFullCharacteristic != null) {
      _logBle('準備讀取預估充滿時間資訊');
      await _initCharacteristic(
        characteristic: _batteryTimeToFullCharacteristic!,
        onData: (_, value) => _updateBatteryTimeToFull(value),
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
  ///
  /// 回傳值代表是否成功維持通知監聽（true 表示已建立監聽，false 則僅執行讀取）
  Future<bool> _enableNotificationWithRetry(
    BluetoothCharacteristic characteristic,
  ) async {
    // ---------- 多次嘗試開啟通知 ----------
    // 部分裝置剛連線時 CCCD 仍在初始化，直接呼叫 setNotifyValue 會被 GATT 拒絕。
    // 這裡提供 3 次退避重試機制，確保在韌體就緒後仍能成功啟用通知。
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      var requireLongDelay = false; // 若收到忙碌訊號則增加等待時間
      try {
        // ---------- 排入序列化佇列 ----------
        // Flutter 層同時對多個 CCCD 寫入時，Android 端會回報 BUSY。
        // 透過佇列確保一次僅發出一個 setNotifyValue 呼叫，降低 writeDescriptor 忙碌機率。
        await _bleOperationQueue.enqueue(
          () async {
            _logBle('排程啟用通知請求（第${attempt + 1}次）：${characteristic.uuid.str}');
            await characteristic.setNotifyValue(true);
          },
          spacing: const Duration(milliseconds: 180), // 預留時間讓韌體處理前一筆 GATT 請求
        );
        _logBle('成功啟用通知（第${attempt + 1}次嘗試）：${characteristic.uuid.str}');
        return true;
      } on FlutterBluePlusException catch (error, stackTrace) {
        // ---------- 解析 flutter_blue_plus 例外內容 ----------
        // errorString 會帶有原生層回傳的描述字串，先轉為小寫方便判斷忙碌或權限類型。
        final message = (error.errorString ?? '').toLowerCase();
        if (message.contains('busy')) {
          requireLongDelay = true;
          _logBle('偵測到底層回報忙碌，將延後下次重試：${characteristic.uuid.str}');
        }
        _logBle(
          '開啟通知失敗（FlutterBluePlusException，第${attempt + 1}次）：${characteristic.uuid.str} -> $error',
          error: error,
          stackTrace: stackTrace,
        );
      } on PlatformException catch (error, stackTrace) {
        _logBle(
          '開啟通知失敗（PlatformException，第${attempt + 1}次）：${characteristic.uuid.str} -> ${error.code}:${error.message}',
          error: error,
          stackTrace: stackTrace,
        );
        final lowerMessage = error.message?.toLowerCase() ?? '';
        if (lowerMessage.contains('busy')) {
          requireLongDelay = true;
          _logBle('GATT 回應忙碌（${characteristic.uuid.str}），延長等待時間後再試');
        }
        if (lowerMessage.contains('not permitted') ||
            lowerMessage.contains('not supported')) {
          // ---------- GATT 明確拒絕 ----------
          // 若韌體回報沒有通知權限，持續重試沒有意義，直接跳出等待補償機制。
          _logBle('偵測到 GATT 拒絕通知，停止重試：${characteristic.uuid.str}');
          return false;
        }
      } catch (error, stackTrace) {
        _logBle(
          '開啟通知發生未預期例外（第${attempt + 1}次）：${characteristic.uuid.str} -> $error',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (attempt < maxAttempts - 1) {
        final baseDelay = requireLongDelay ? 700 : 400;
        final delay = Duration(milliseconds: baseDelay * (attempt + 1));
        _logBle('通知啟用失敗，${delay.inMilliseconds}ms 後重試：${characteristic.uuid.str}');
        await Future.delayed(delay);
      }
    }

    _logBle('多次嘗試仍無法啟用通知，改採僅讀取模式：${characteristic.uuid.str}');
    return false;
  }

  Future<bool> _initCharacteristic({
    required BluetoothCharacteristic characteristic,
    required void Function(String deviceId, List<int>) onData,
    bool listenToUpdates = true,
    bool readInitialValue = true,
    List<StreamSubscription<List<int>>>? targetSubscriptions,
    void Function(String message)? onErrorMessage,
  }) async {
    bool shouldListen =
        listenToUpdates && (characteristic.properties.notify || characteristic.properties.indicate);

    if (shouldListen) {
      try {
        if (characteristic.descriptors.isEmpty) {
          // ---------- 某些裝置不會回報描述符 ----------
          // 仍強制嘗試開啟通知，避免因缺少 CCCD 而錯失資料
          _logBle('特徵 ${characteristic.uuid.str} 未附帶描述符，改以直接開啟通知');
        } else {
          final hasCccd =
              characteristic.descriptors.any((descriptor) => descriptor.uuid == _cccdUuid);
          if (!hasCccd) {
            // ---------- 找不到 CCCD ----------
            // 仍嘗試開啟通知，同時輸出除錯資訊方便排查韌體設定
      _logBle('裝置未回傳 CCCD，改以直接開啟通知：${characteristic.uuid.str}');
      }
    }

    if (!characteristic.isNotifying) {
          // ---------- 尚未啟用通知，交給重試機制處理 ----------
          shouldListen = await _enableNotificationWithRetry(characteristic);
        } else {
          // ---------- 避免重複啟用 ----------
          _logBle('通知已開啟，略過重複設定：${characteristic.uuid.str}');
        }
      } catch (error, stackTrace) {
        // 若裝置暫不支援通知則忽略錯誤，改以初始讀取補救
        shouldListen = false;
        _logBle('開啟通知失敗：${characteristic.uuid.str}，原因：$error',
            error: error, stackTrace: stackTrace);
      }
    }

    if (shouldListen) {
      final deviceId = characteristic.remoteId.str;
      final subscription = characteristic.lastValueStream.listen(
        (value) => onData(deviceId, value),
        onError: (error) {
          if (!mounted) return;
          if (onErrorMessage != null) {
            onErrorMessage('讀取 ${characteristic.uuid.str} 時發生錯誤：$error');
          } else {
            setState(() {
              _connectionMessage = '讀取 ${characteristic.uuid.str} 時發生錯誤：$error';
            });
          }
          _logBle('特徵通知流錯誤：${characteristic.uuid.str}，錯誤：$error', error: error);
        },
      );
      (targetSubscriptions ?? _notificationSubscriptions).add(subscription);
    }

    if (readInitialValue && characteristic.properties.read) {
      try {
        final value = await characteristic.read();
        if (value.isNotEmpty) {
          onData(characteristic.remoteId.str, value);
        }
        _logBle('已讀取初始值：${characteristic.uuid.str}，長度：${value.length}');
      } catch (error, stackTrace) {
        // 初始讀取失敗時暫不處理，等待後續通知補上資料
        _logBle('初始讀取失敗：${characteristic.uuid.str}，原因：$error', error: error, stackTrace: stackTrace);
      }
    }
    return shouldListen;
  }

  /// 建立胸前 IMU 的感測特徵訂閱
  Future<void> _setupSecondImuServices(List<BluetoothService> services) async {
    await _cancelSecondNotificationSubscriptions();
    _cancelSecondGameRotationFallbackTimer();
    _resetSecondCharacteristicReferences();
    _resetSecondImuDataState();

    _logBle('開始建立胸前 IMU 服務訂閱，共取得 ${services.length} 組服務');

    for (final service in services) {
      if (service.uuid == _serviceBno086Uuid) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charLinearAccelerationUuid) {
            _secondLinearAccelerationCharacteristic = characteristic;
            _logBle('胸前 IMU 綁定線性加速度特徵：${characteristic.uuid.str}');
          } else if (characteristic.uuid == _charGameRotationVectorUuid) {
            _secondGameRotationVectorCharacteristic = characteristic;
            _logBle('胸前 IMU 綁定 Game Rotation Vector 特徵：${characteristic.uuid.str}');
          }
        }
      } else if (service.uuid == _serviceMotorUuid) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _charMotorToggleUuid) {
            _secondMotorControlCharacteristic = characteristic;
            _logBle('胸前 IMU 綁定馬達控制特徵：${characteristic.uuid.str}');
          }
        }
      }
    }

    final linearCharacteristic = _secondLinearAccelerationCharacteristic;
    final rotationCharacteristic = _secondGameRotationVectorCharacteristic;

    if (linearCharacteristic == null || rotationCharacteristic == null) {
      _logBle('胸前 IMU 缺少線性加速度或旋轉特徵，無法啟用感測記錄');
      if (mounted) {
        setState(() {
          _chestConnectionMessage = '裝置未提供完整的感測特徵，請重新配對';
        });
      }
      return;
    }

    await _initCharacteristic(
      characteristic: linearCharacteristic,
      onData: _handleLinearAccelerationPacket,
      targetSubscriptions: _secondNotificationSubscriptions,
      onErrorMessage: (message) {
        if (!mounted) return;
        setState(() => _chestConnectionMessage = message);
      },
    );

    final isListening = await _initCharacteristic(
      characteristic: rotationCharacteristic,
      onData: _handleGameRotationVectorPacket,
      targetSubscriptions: _secondNotificationSubscriptions,
      onErrorMessage: (message) {
        if (!mounted) return;
        setState(() => _chestConnectionMessage = message);
      },
    );

    if (!isListening && rotationCharacteristic.properties.read) {
      _secondGameRotationFallbackTimer = Timer.periodic(
        const Duration(seconds: 3),
        (timer) async {
          if (_isSecondGameRotationFallbackReading) {
            return;
          }
          _isSecondGameRotationFallbackReading = true;
          try {
            final value = await rotationCharacteristic.read();
            if (value.isNotEmpty) {
              _handleGameRotationVectorPacket(rotationCharacteristic.remoteId.str, value);
            }
          } catch (error) {
            _logBle('胸前 IMU 補償讀取失敗：$error');
          } finally {
            _isSecondGameRotationFallbackReading = false;
          }
        },
      );
      _logBle('胸前 IMU Game Rotation Vector 以補償讀取模式運作');
    }

    if (mounted) {
      setState(() {
        _chestConnectionMessage = '胸前 IMU 感測資料已就緒';
      });
    }
  }

  /// 解析線性加速度封包，並同步寫入 CSV 與更新最新顯示資料
  void _handleLinearAccelerationPacket(String deviceId, List<int> value) {
    if (value.length < 16) return;
    Map<String, dynamic>? sample;
    for (int offset = 0; offset + 15 < value.length; offset += 16) {
      final parsed = _parseThreeAxisSample(value, offset);
      if (parsed == null) continue;
      sample = parsed;
      ImuDataLogger.instance.logLinearAcceleration(
        deviceId,
        parsed,
        value.sublist(offset, offset + 16),
      );
    }
    if (sample == null) return;
    if (!mounted) return;
    final isPrimary = _isPrimaryDevice(deviceId);
    final isChest = _isChestDevice(deviceId);
    if (!isPrimary && !isChest) {
      return;
    }
    setState(() {
      if (isPrimary) {
        _latestLinearAcceleration = sample;
      }
      if (isChest) {
        _secondLatestLinearAcceleration = sample;
      }
    });
  }

  /// 解析 Game Rotation Vector 封包並同步紀錄原始資料
  void _handleGameRotationVectorPacket(String deviceId, List<int> value) {
    if (value.isEmpty) {
      return; // 沒有資料時直接結束
    }

    Map<String, dynamic>? sample;
    int offset = 0;

    final slotLabel = _isPrimaryDevice(deviceId)
        ? '右手腕'
        : (_isChestDevice(deviceId) ? '胸前' : '未知');

    // 逐步解析通知內容，支援 16 bytes（基本欄位）與 20 bytes（額外 accuracy、reserved）封包
    while (offset < value.length) {
      final remaining = value.length - offset;
      final chunkSize = _determineRotationChunkSize(remaining);
      if (chunkSize == null) {
        _logBle('Game Rotation Vector 封包長度不足，剩餘 $remaining bytes 無法解析');
        break;
      }

      final parsed = _parseRotationSample(value, offset, chunkSize);
      if (parsed == null) {
        _logBle('Game Rotation Vector 封包解析失敗，offset=$offset、length=$chunkSize');
        break;
      }

      _setLastRotationUpdate(deviceId, DateTime.now());

      final seq = parsed['seq'] as int?;
      final timestamp = parsed['timestampUs'] as int?;
      final lastSeq = _getLastRotationSeq(deviceId);
      final lastTimestamp = _getLastRotationTimestamp(deviceId);
      final isDuplicate = seq != null &&
          timestamp != null &&
          lastSeq == seq &&
          lastTimestamp == timestamp;
      if (isDuplicate) {
        _logBle('[$slotLabel] Game Rotation Vector 收到重複封包：seq=$seq、timestamp=$timestamp，略過寫入與顯示');
        offset += chunkSize;
        continue;
      }

      _setLastRotationSeq(deviceId, seq);
      _setLastRotationTimestamp(deviceId, timestamp);

      sample = parsed;
      ImuDataLogger.instance.logGameRotationVector(
        deviceId,
        parsed,
        value.sublist(offset, offset + chunkSize),
      );
      offset += chunkSize;
    }

    if (sample == null || !mounted) {
      return;
    }

    _logBle(
      '[$slotLabel] Game Rotation Vector 更新：seq=${sample['seq']}、i=${_formatNumericLabel(sample['i'] as num?, digits: 4)}、j=${_formatNumericLabel(sample['j'] as num?, digits: 4)}、k=${_formatNumericLabel(sample['k'] as num?, digits: 4)}、w=${_formatNumericLabel(sample['real'] as num?, digits: 4)}',
    );

    final isPrimary = _isPrimaryDevice(deviceId);
    final isChest = _isChestDevice(deviceId);
    if (!isPrimary && !isChest) {
      return;
    }

    setState(() {
      if (isPrimary) {
        _latestGameRotationVector = sample;
      }
      if (isChest) {
        _secondLatestGameRotationVector = sample;
      }
    });
  }

  /// 啟動 Game Rotation Vector 的補償讀取計時器，避免通知失敗時持續顯示等待
  void _startGameRotationFallbackTimer({
    required bool notificationActive,
    required bool canReadCharacteristic,
  }) {
    _cancelGameRotationFallbackTimer();
    if (_gameRotationVectorCharacteristic == null) {
      return; // 沒有特徵可讀取時直接離開
    }

    if (!canReadCharacteristic) {
      // 裝置僅允許透過通知傳送資料時，留下紀錄並停止補償計時器
      _logBle('Game Rotation Vector 特徵未提供讀取權限，僅能等待通知資料更新');
      return;
    }

    const interval = Duration(seconds: 3);
    _logBle(
      '啟動 Game Rotation Vector 補償讀取計時器，通知啟動=$notificationActive、間隔=${interval.inSeconds} 秒',
    );

    _gameRotationFallbackTimer = Timer.periodic(interval, (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final characteristic = _gameRotationVectorCharacteristic;
      if (characteristic == null) {
        timer.cancel();
        return;
      }

      final lastUpdate = _lastGameRotationUpdate;
      if (lastUpdate != null && DateTime.now().difference(lastUpdate) < interval) {
        return; // 最近已有資料更新，無需補償讀取
      }

      if (!characteristic.properties.read) {
        _logBle('Game Rotation Vector 特徵不支援讀取，無法執行補償流程');
        timer.cancel();
        return;
      }

      if (_isGameRotationFallbackReading) {
        return; // 上一次補償讀取尚未完成
      }

      _isGameRotationFallbackReading = true;
      try {
        _logBle('Game Rotation Vector 超過 ${interval.inSeconds} 秒未更新，嘗試補償讀取');
        final value = await characteristic.read();
        if (value.isNotEmpty) {
          _handleGameRotationVectorPacket(characteristic.remoteId.str, value);
        } else {
          _logBle('Game Rotation Vector 補償讀取回傳空陣列，等待下次機會');
        }
      } catch (error, stackTrace) {
        _logBle('Game Rotation Vector 補償讀取失敗：$error', error: error, stackTrace: stackTrace);
        // 若裝置明確回報禁止讀取，立即停止補償流程避免持續拋錯
        if (error is FlutterBluePlusException) {
          // 某些平台可能不會回傳錯誤字串，因此先進行空值處理後再比對內容
          final errorMessage = error.errorString ?? '';
          if (errorMessage.contains('GATT_READ_NOT_PERMITTED')) {
            _logBle('裝置不允許讀取 Game Rotation Vector，停止補償計時器');
            timer.cancel();
          }
        }
      } finally {
        _isGameRotationFallbackReading = false;
      }
    });
  }

  /// 停止 Game Rotation Vector 補償讀取計時器
  void _cancelGameRotationFallbackTimer() {
    _gameRotationFallbackTimer?.cancel();
    _gameRotationFallbackTimer = null;
    _isGameRotationFallbackReading = false;
  }

  /// 停止胸前 IMU 的 Game Rotation Vector 補償讀取計時器
  void _cancelSecondGameRotationFallbackTimer() {
    _secondGameRotationFallbackTimer?.cancel();
    _secondGameRotationFallbackTimer = null;
    _isSecondGameRotationFallbackReading = false;
  }

  /// 解析三軸感測資料共同欄位（線性加速度、陀螺儀等格式相同）
  Map<String, dynamic>? _parseThreeAxisSample(List<int> data, int offset) {
    final timestamp = _readUint32At(data, offset + 4);
    final rawX = _readInt16At(data, offset + 8);
    final rawY = _readInt16At(data, offset + 10);
    final rawZ = _readInt16At(data, offset + 12);
    if (timestamp == null || rawX == null || rawY == null || rawZ == null) {
      return null;
    }

    const double scale = 0.001; // ---------- 依照規格轉換為公尺每秒平方 ----------
    final double x = rawX * scale;
    final double y = rawY * scale;
    final double z = rawZ * scale;

    return {
      'id': data[offset],
      'seq': data[offset + 1],
      'status': data[offset + 2],
      'timestampUs': timestamp,
      'x': x,
      'y': y,
      'z': z,
      'rawX': rawX,
      'rawY': rawY,
      'rawZ': rawZ,
    };
  }

  /// 解析 Game Rotation Vector 專屬的四元數資料結構
  Map<String, dynamic>? _parseRotationSample(
    List<int> data,
    int offset,
    int length,
  ) {
    if (offset + length > data.length) {
      return null; // 長度超出原始陣列界線時直接忽略
    }

    final timestamp = _readUint32At(data, offset + 4);
    final rawI = _readInt16At(data, offset + 8);
    final rawJ = _readInt16At(data, offset + 10);
    final rawK = _readInt16At(data, offset + 12);
    final rawReal = _readInt16At(data, offset + 14);
    if (timestamp == null || rawI == null || rawJ == null || rawK == null || rawReal == null) {
      return null;
    }

    const double qpScaling = 1.0 / 16384.0; // ---------- Q14 固定小數點轉浮點 ----------
    final double i = rawI * qpScaling;
    final double j = rawJ * qpScaling;
    final double k = rawK * qpScaling;
    final double real = rawReal * qpScaling;

    // accuracy 與 reserved 僅存在於較新的韌體（20 bytes 封包），舊版則保持 null
    int? accuracy;
    int? reserved;
    if (length >= 18) {
      accuracy = _readInt16At(data, offset + 16);
    }
    if (length >= 20) {
      reserved = _readInt16At(data, offset + 18);
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
      'w': real,
      'rawI': rawI,
      'rawJ': rawJ,
      'rawK': rawK,
      'rawReal': rawReal,
      'accuracy': accuracy,
      'reserved': reserved,
      'packetLength': length,
    };
  }

  /// 判斷 Game Rotation Vector 封包長度，根據剩餘位元組推算應使用的解析長度
  int? _determineRotationChunkSize(int remaining) {
    if (remaining >= 20 && remaining % 20 == 0 && remaining % 16 != 0) {
      return 20; // 偏好整除 20 的情境，代表每筆資料都附帶 accuracy/reserved
    }
    if (remaining >= 16 && remaining % 16 == 0) {
      return 16; // 整除 16 代表舊版韌體僅有基本欄位
    }
    if (remaining >= 20) {
      return 20; // 儘管無法整除，也優先嘗試較大的封包以保留額外欄位
    }
    if (remaining >= 16) {
      return 16; // 最小需求 16 bytes（含四元數基本欄位）
    }
    return null;
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

    // ---------- 以右手腕短按啟動錄影 ----------
    if (!mounted) {
      return;
    }

    // ---------- 針對短按開始或結束觸發錄影 ----------
    final bool isShortPressEvent = eventCode == 0x01 || eventCode == 0x02;
    if (isShortPressEvent && clickTimes <= 1) {
      final now = DateTime.now();
      final shouldTrigger = _lastButtonTriggerTime == null ||
          now.difference(_lastButtonTriggerTime!).inMilliseconds > 800;
      if (!shouldTrigger) {
        _logBle('按鈕事件與前次觸發過於接近，避免重複開啟錄影');
        return;
      }
      _lastButtonTriggerTime = now; // 記錄此次觸發時間，避免短時間內重複響應

      if (_isSessionPageVisible) {
        // 若錄影頁面已開啟，直接轉交事件給錄影頁啟動倒數
        _logBle('錄影頁面已開啟，轉交硬體按鈕觸發倒數錄影');
        _imuButtonController.add(null);
        return;
      }
      if (_isOpeningSession) {
        _logBle('按鈕觸發錄影但畫面尚在開啟中，略過重複事件');
        return;
      }
      _logBle('偵測到短按事件（code=$eventCode），準備自動開啟錄影畫面並預約自動倒數');
      // 透過硬體按鈕觸發時，直接沿用使用者目前的錄影次數／秒數設定，避免再跳出彈窗
      unawaited(_openRecordingSession(triggeredByImuButton: true));
    }
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

  /// 依插槽觸發短暫震動，方便使用者確認手上設備的位置
  Future<void> _triggerMotorPulseForSlot(_ImuSlotType slot) async {
    final characteristic = _motorCharacteristicForSlot(slot);
    if (characteristic == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${slot.displayLabel} 尚未取得震動控制特徵，請確認裝置已連線。')),
      );
      return;
    }

    if (_isMotorBusyForSlot(slot)) {
      _logBle('${slot.displayLabel} 震動命令仍在執行中，略過重複請求');
      return;
    }
    _setMotorBusyForSlot(slot, true);

    final bool supportsWriteWithResponse = characteristic.properties.write;
    final bool supportsWriteWithoutResponse = characteristic.properties.writeWithoutResponse;
    final bool useWithoutResponse = !supportsWriteWithResponse && supportsWriteWithoutResponse;

    try {
      await _bleOperationQueue.enqueue(() async {
        await characteristic.write([1], withoutResponse: useWithoutResponse);
        await Future.delayed(const Duration(milliseconds: 500));
        await characteristic.write([0], withoutResponse: useWithoutResponse);
      }, spacing: const Duration(milliseconds: 320));
    } catch (error, stackTrace) {
      _logBle('震動命令失敗：${characteristic.uuid.str}，原因：$error',
          error: error, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${slot.displayLabel} 震動失敗：$error')),
        );
      }
    } finally {
      _setMotorBusyForSlot(slot, false);
    }
  }

  /// 判斷目前是否已建立右手腕 IMU 連線
  bool get isPrimaryImuConnected =>
      _connectedDevice != null && _connectionState == BluetoothConnectionState.connected;

  /// 判斷目前是否已建立胸前 IMU 連線
  bool get isChestImuConnected =>
      _secondDevice != null && _secondConnectionState == BluetoothConnectionState.connected;

  /// 只要任一 IMU 已連線即視為可搭配錄影
  bool get isImuConnected => isPrimaryImuConnected || isChestImuConnected;

  /// 檢查給定裝置識別碼是否對應右手腕 IMU
  bool _isPrimaryDevice(String deviceId) =>
      _connectedDevice != null && _connectedDevice!.remoteId.str == deviceId;

  /// 檢查給定裝置識別碼是否對應胸前 IMU
  bool _isChestDevice(String deviceId) =>
      _secondDevice != null && _secondDevice!.remoteId.str == deviceId;

  DateTime? _getLastRotationUpdate(String deviceId) =>
      _isPrimaryDevice(deviceId) ? _lastGameRotationUpdate : (_isChestDevice(deviceId) ? _secondLastGameRotationUpdate : null);

  void _setLastRotationUpdate(String deviceId, DateTime? value) {
    if (_isPrimaryDevice(deviceId)) {
      _lastGameRotationUpdate = value;
    } else if (_isChestDevice(deviceId)) {
      _secondLastGameRotationUpdate = value;
    }
  }

  int? _getLastRotationSeq(String deviceId) =>
      _isPrimaryDevice(deviceId) ? _lastGameRotationSeq : (_isChestDevice(deviceId) ? _secondLastGameRotationSeq : null);

  void _setLastRotationSeq(String deviceId, int? value) {
    if (_isPrimaryDevice(deviceId)) {
      _lastGameRotationSeq = value;
    } else if (_isChestDevice(deviceId)) {
      _secondLastGameRotationSeq = value;
    }
  }

  int? _getLastRotationTimestamp(String deviceId) => _isPrimaryDevice(deviceId)
      ? _lastGameRotationTimestamp
      : (_isChestDevice(deviceId) ? _secondLastGameRotationTimestamp : null);

  void _setLastRotationTimestamp(String deviceId, int? value) {
    if (_isPrimaryDevice(deviceId)) {
      _lastGameRotationTimestamp = value;
    } else if (_isChestDevice(deviceId)) {
      _secondLastGameRotationTimestamp = value;
    }
  }

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
  Future<void> _openRecordingSession({bool triggeredByImuButton = false}) async {
    if (_isOpeningSession) return; // 避免重複點擊快速開啟多個頁面

    if (widget.cameras.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有可用鏡頭，無法開始錄影。')),
      );
      return;
    }

    setState(() => _isOpeningSession = true);

    Map<String, int>? config;
    if (triggeredByImuButton) {
      // ---------- 硬體按鈕自動啟動 ----------
      // 直接沿用目前頁面記錄的設定值，避免在揮桿時還要操作彈窗
      config = {
        'rounds': _selectedRounds,
        'seconds': _recordingDurationSeconds,
      };
    } else {
      // ---------- 手動點擊按鈕 ----------
      // 進入錄影前先彈出設定視窗，讓使用者選擇要錄影的次數與長度
      config = await _showRecordingConfigDialog();
      if (config == null) {
        if (!mounted) return;
        setState(() => _isOpeningSession = false);
        return; // 使用者取消設定則不進入錄影畫面
      }

      setState(() {
        _selectedRounds = config!['rounds']!;
        _recordingDurationSeconds = config['seconds']!;
      });
    }

    config ??= {
      'rounds': _selectedRounds,
      'seconds': _recordingDurationSeconds,
    };
    final int rounds = config['rounds'] ?? _selectedRounds;
    final int seconds = config['seconds'] ?? _recordingDurationSeconds;

    List<RecordingHistoryEntry>? historyFromSession;
    _isSessionPageVisible = true; // 標記錄影頁面已開啟，後續按鈕事件直接轉交
    try {
      historyFromSession = await Navigator.push<List<RecordingHistoryEntry>>(
        context,
        MaterialPageRoute(
          builder: (_) => RecordingSessionPage(
            cameras: widget.cameras,
            isImuConnected: isImuConnected,
            totalRounds: rounds,
            durationSeconds: seconds,
            autoStartOnReady: triggeredByImuButton,
            imuButtonStream: _imuButtonController.stream,
          ),
        ),
      );
    } finally {
      _isSessionPageVisible = false; // 不論結果如何都重設狀態
    }
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
      unawaited(
        RecordingHistoryStorage.instance.saveHistory(_recordingHistory),
      ); // 將結果寫入檔案，避免重啟後遺失
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

  /// 感測資料區塊，整合兩顆 IMU 的最新狀態
  Widget _buildSensorDataSection() {
    final List<Widget> groups = [];

    // ---------- 右手腕 IMU ----------
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
    final String primaryTitle = _connectedDevice != null
        ? _resolveDeviceName(_connectedDevice!)
        : '右手腕 IMU';
    groups.add(
      _buildSensorDataGroup(
        title: primaryTitle,
        headerIcon: Icons.sports_golf,
        buttonStatus: _buttonStatusText,
        buttonSubtitle: buttonDetails.isEmpty ? null : buttonDetails.join(' · '),
        linearSummary: _formatLinearAccelerationSummary(_latestLinearAcceleration),
        linearMeta: _formatThreeAxisMeta(_latestLinearAcceleration),
        rotationSummary: _formatRotationSummary(_latestGameRotationVector),
        rotationMeta: _formatRotationMeta(_latestGameRotationVector),
      ),
    );

    // ---------- 胸前 IMU ----------
    final bool hasChestData =
        _secondLatestLinearAcceleration != null || _secondLatestGameRotationVector != null || isChestImuConnected;
    if (hasChestData) {
      final String chestTitle =
          _secondDevice != null ? _resolveDeviceName(_secondDevice!) : '胸前 IMU';
      groups.add(const SizedBox(height: 14));
      groups.add(
        _buildSensorDataGroup(
          title: chestTitle,
          headerIcon: Icons.accessibility_new,
          buttonStatus: null,
          buttonSubtitle: null,
          linearSummary: _formatLinearAccelerationSummary(_secondLatestLinearAcceleration),
          linearMeta: _formatThreeAxisMeta(_secondLatestLinearAcceleration),
          rotationSummary: _formatRotationSummary(_secondLatestGameRotationVector),
          rotationMeta: _formatRotationMeta(_secondLatestGameRotationVector),
        ),
      );
    }

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
        ...groups,
      ],
    );
  }

  /// 個別 IMU 的感測摘要卡片，統一顯示按鈕、加速度與旋轉資訊
  Widget _buildSensorDataGroup({
    required String title,
    required IconData headerIcon,
    required String linearSummary,
    required String rotationSummary,
    String? linearMeta,
    String? rotationMeta,
    String? buttonStatus,
    String? buttonSubtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(headerIcon, color: const Color(0xFF123B70)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF123B70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (buttonStatus != null) ...[
            _buildInfoRow(Icons.smart_button, '按鈕事件', buttonStatus, subtitle: buttonSubtitle),
            const SizedBox(height: 10),
          ],
          _buildInfoRow(Icons.trending_up, '線性加速度', linearSummary, subtitle: linearMeta),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.threed_rotation,
            'Game Rotation Vector',
            rotationSummary,
            subtitle: rotationMeta,
          ),
        ],
      ),
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
    final bool primaryAvailable = _motorControlCharacteristic != null;
    final bool chestAvailable = _secondMotorControlCharacteristic != null;

    if (!primaryAvailable && !chestAvailable) {
      return Row(
        children: const [
          Icon(Icons.vibration, color: Color(0xFF123B70)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '尚未取得震動控制特徵，可重新連線後再嘗試震動識別。',
              style: TextStyle(fontSize: 13, color: Color(0xFF465A71)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.vibration, color: Color(0xFF123B70)),
            SizedBox(width: 8),
            Text(
              '震動測試',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF123B70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '點擊下方按鈕可讓指定 IMU 短暫震動，協助辨識目前手持的裝置。',
          style: TextStyle(fontSize: 13, color: Color(0xFF465A71)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (primaryAvailable) _buildMotorTestButton(_ImuSlotType.rightWrist),
            if (chestAvailable) _buildMotorTestButton(_ImuSlotType.chest),
          ],
        ),
      ],
    );
  }

  /// 個別插槽專屬的震動按鈕
  Widget _buildMotorTestButton(_ImuSlotType slot) {
    final bool busy = _isMotorBusyForSlot(slot);
    final String label = slot == _ImuSlotType.rightWrist ? '右手腕震動' : '胸前震動';
    return FilledButton.tonalIcon(
      onPressed: busy ? null : () => _triggerMotorPulseForSlot(slot),
      icon: const Icon(Icons.vibration),
      label: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  /// 將線性加速度資料轉成可讀摘要
  String _formatLinearAccelerationSummary(Map<String, dynamic>? sample) {
    if (sample == null) {
      return '等待裝置傳送資料';
    }
    final x = sample['x'] as num?;
    final y = sample['y'] as num?;
    final z = sample['z'] as num?;
    return 'X: ${_formatNumericLabel(x)} · Y: ${_formatNumericLabel(y)} · Z: ${_formatNumericLabel(z)} (g)';
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
    final i = sample['i'] as num?;
    final j = sample['j'] as num?;
    final k = sample['k'] as num?;
    final real = sample['real'] as num?;
    return 'i: ${_formatNumericLabel(i, digits: 4)} · j: ${_formatNumericLabel(j, digits: 4)} · k: ${_formatNumericLabel(k, digits: 4)} · w: ${_formatNumericLabel(real, digits: 4)}';
  }

  /// 顯示四元數額外資訊
  String? _formatRotationMeta(Map<String, dynamic>? sample) {
    if (sample == null) {
      return null;
    }
    final seq = sample['seq'];
    final status = sample['status'];
    final timestamp = sample['timestampUs'];
    final accuracy = sample['accuracy'];
    final packetLength = sample['packetLength'];
    final buffer = <String>[
      '序號 $seq',
      '狀態 $status',
      '時間標籤 ${timestamp ?? '--'} μs',
    ];
    if (accuracy != null) {
      buffer.add('準確度 $accuracy');
    }
    if (packetLength != null) {
      buffer.add('封包 ${packetLength} bytes');
    }
    return buffer.join(' · ');
  }

  /// 將數值統一格式化，避免 UI 出現過長的小數或 null 字樣
  String _formatNumericLabel(num? value, {int digits = 3}) {
    if (value == null) {
      return '--';
    }
    return value.toStringAsFixed(digits);
  }

  /// 將時間格式化為 HH:mm:ss 字串
  String _formatTimeOfDay(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
  }

  /// 建構 IMU 連線卡片，提示使用者完成藍牙配對
  Widget _buildImuConnectionCard() {
    final bool primaryConnected = isPrimaryImuConnected;
    final bool hasCandidate = _foundDevice != null;
    final String primaryTitle = primaryConnected
        ? _resolveDeviceName(_connectedDevice!)
        : (_foundDeviceName ?? '右手腕 IMU');
    final String primarySignal =
        _lastRssi != null ? '訊號 ${_lastRssi} dBm' : '訊號偵測中';
    final String batteryOverview = _batteryLevelText ?? '電量讀取中';
    final String firmwareOverview =
        (_firmwareRevision?.isNotEmpty == true) ? _firmwareRevision! : '韌體資訊更新中';

    final bool chestConnected = isChestImuConnected;
    final String chestTitle = chestConnected
        ? _resolveDeviceName(_secondDevice!)
        : '胸前 IMU';
    final String chestDetail = chestConnected ? '資料串流中' : '等待綁定';
    final bool anyConnected = primaryConnected || chestConnected;
    final bool allSlotsConnected = primaryConnected && chestConnected;
    final bool showScanSection = !allSlotsConnected;

    // 根據目前配對狀態決定提示文字與顏色，協助使用者理解下一步
    final String readinessText;
    final Color readinessColor;
    if (allSlotsConnected) {
      readinessText = '兩顆 IMU 已完成配對，可立即開始錄影流程。';
      readinessColor = const Color(0xFF1E8E5A);
    } else if (anyConnected) {
      readinessText = '已連線至少一顆 IMU，仍可透過重新搜尋綁定另一顆裝置。';
      readinessColor = const Color(0xFF123B70);
    } else {
      readinessText = '未連線 IMU 亦可錄影，建議配對以取得揮桿數據。';
      readinessColor = const Color(0xFF7D8B9A);
    }

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
              Expanded(
                child: Column(
                  children: [
                    _buildImuSlotRow(
                      slot: _ImuSlotType.rightWrist,
                      title: primaryTitle,
                      statusText: _connectionMessage,
                      detailText: '電量 $batteryOverview · $firmwareOverview · $primarySignal',
                      connected: primaryConnected,
                      onConnectPressed: (_isConnecting || (!primaryConnected && !hasCandidate))
                          ? null
                          : () => connectToImu(slot: _ImuSlotType.rightWrist),
                    ),
                    const SizedBox(height: 14),
                    _buildImuSlotRow(
                      slot: _ImuSlotType.chest,
                      title: chestTitle,
                      statusText: _chestConnectionMessage,
                      detailText: chestDetail,
                      connected: chestConnected,
                      onConnectPressed:
                          _isConnecting ? null : () => connectToImu(slot: _ImuSlotType.chest),
                    ),
                  ],
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
              Expanded(
                child: Text(
                  readinessText,
                  style: TextStyle(fontSize: 12, color: readinessColor),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (showScanSection) ...[
            const SizedBox(height: 20),
            _buildScanCandidatesSection(),
          ],
          if (anyConnected) ...[
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

  Widget _buildImuSlotRow({
    required _ImuSlotType slot,
    required String title,
    required String statusText,
    required String detailText,
    required bool connected,
    required VoidCallback? onConnectPressed,
  }) {
    final Color statusColor = connected ? const Color(0xFF1E8E5A) : const Color(0xFF7D8B9A);
    final IconData icon =
        slot == _ImuSlotType.rightWrist ? Icons.sports_golf : Icons.accessibility_new;
    final List<Color> gradientColors = slot == _ImuSlotType.rightWrist
        ? const [Color(0xFF123B70), Color(0xFF1E8E5A)]
        : const [Color(0xFF6A1B9A), Color(0xFF26A69A)];
    final String buttonText = connected
        ? '重新連線'
        : (slot == _ImuSlotType.rightWrist ? '配對右手腕' : '配對胸前');
    final bool motorAvailable = _motorCharacteristicForSlot(slot) != null;
    final bool motorBusy = _isMotorBusyForSlot(slot);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                statusText,
                style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                detailText,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7D8B9A)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: onConnectPressed,
              style: FilledButton.styleFrom(
                backgroundColor: connected ? const Color(0xFF1E8E5A) : const Color(0xFF123B70),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _isConnecting && onConnectPressed == null
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
            ),
            if (motorAvailable) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: motorBusy ? null : () => _triggerMotorPulseForSlot(slot),
                icon: const Icon(Icons.vibration, size: 18),
                label: Text(motorBusy ? '震動中…' : '震動識別'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF123B70),
                ),
              ),
            ],
          ],
        ),
      ],
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
    final bool isPrimaryAssigned =
        _connectedDevice?.remoteId == candidate.device.remoteId;
    final bool isChestAssigned =
        _secondDevice?.remoteId == candidate.device.remoteId;

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: _isConnecting || isPrimaryAssigned
                    ? null
                    : () => connectToImu(
                          slot: _ImuSlotType.rightWrist,
                          candidate: candidate.device,
                          candidateName: candidate.displayName,
                        ),
                child: Text(isPrimaryAssigned ? '已綁定右手腕' : '綁定右手腕'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _isConnecting || isChestAssigned
                    ? null
                    : () => connectToImu(
                          slot: _ImuSlotType.chest,
                          candidate: candidate.device,
                          candidateName: candidate.displayName,
                        ),
                child: Text(isChestAssigned ? '已綁定胸前' : '綁定胸前'),
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
                onPressed:
                    _isOpeningSession ? null : () => _openRecordingSession(),
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

/// 將底層藍牙請求排成序列，避免多個 setNotifyValue 同時進行造成 BUSY 例外
class _BleOperationQueue {
  final List<_BleQueuedTask> _queue = <_BleQueuedTask>[]; // 儲存等待執行的任務
  bool _isRunning = false; // 是否已有任務正在執行
  bool _isDisposed = false; // 頁面是否已釋放，避免離開後繼續操作藍牙

  /// 將任務加入佇列並依序執行，可設定每筆任務之間的緩衝時間
  Future<void> enqueue(
    Future<void> Function() action, {
    Duration spacing = const Duration(milliseconds: 150),
  }) {
    if (_isDisposed) {
      // 若頁面已銷毀則不再排程，直接回傳已完成的 Future 避免外部 await 卡住
      return Future.value();
    }

    final completer = Completer<void>();
    _queue.add(
      _BleQueuedTask(
        run: () async {
          try {
            await action();
            if (!completer.isCompleted) {
              completer.complete();
            }
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        spacing: spacing,
      ),
    );
    _processQueue();
    return completer.future;
  }

  /// 清除所有待執行任務，並阻止後續 enqueue 進入
  void dispose() {
    _isDisposed = true;
    _queue.clear();
  }

  void _processQueue() {
    if (_isDisposed || _isRunning || _queue.isEmpty) {
      return;
    }
    _isRunning = true;
    _runNext();
  }

  void _runNext() {
    if (_isDisposed || _queue.isEmpty) {
      _isRunning = false;
      return;
    }
    final task = _queue.removeAt(0);
    task.run().whenComplete(() async {
      if (task.spacing > Duration.zero) {
        await Future.delayed(task.spacing);
      }
      _runNext();
    });
  }
}

/// 描述一筆待處理的 BLE 任務與其間隔設定
class _BleQueuedTask {
  final Future<void> Function() run; // 實際執行內容
  final Duration spacing; // 與下一筆任務的間隔時間

  const _BleQueuedTask({
    required this.run,
    required this.spacing,
  });
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
