import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// IMU 原始資料紀錄器：集中管理多裝置的 CSV 寫入流程，確保影片與感測資料對應。
class ImuDataLogger {
  ImuDataLogger._();

  /// 單例存取點，方便錄影頁與藍牙頁共用狀態。
  static final ImuDataLogger instance = ImuDataLogger._();

  final Map<String, _ImuDeviceInfo> _devices = {}; // 目前已連線的裝置資訊
  final Map<String, _ActiveImuLog> _activeLogs = {}; // 當前錄影輪次的寫入器

  Directory? _storageDirectory; // 應用專屬儲存資料夾

  /// 最多允許同時寫入的裝置數量（依需求限制為 2 台）。
  static const int _maxDevices = 2;

  /// 登記成功連線的藍牙裝置，後續啟動錄影時會建立對應 CSV。
  void registerDevice(
    BluetoothDevice device, {
    required String displayName,
    required String slotAlias,
  }) {
    final deviceId = device.remoteId.str;
    _devices[deviceId] = _ImuDeviceInfo(
      deviceId: deviceId,
      displayName: displayName,
      slotAlias: slotAlias,
      connectedAt: DateTime.now(),
    );
  }

  /// 連線斷開時移除裝置資訊，避免後續繼續寫入失效檔案。
  void unregisterDevice(String deviceId) {
    _devices.remove(deviceId);
    _activeLogs.remove(deviceId)?.dispose(deleteFile: true);
  }

  /// 依照錄影輪次產生具可讀性的檔名基底（round_序號_時間戳）。
  String buildBaseFileName({required int roundIndex, DateTime? timestamp}) {
    final time = timestamp ?? DateTime.now();
    final buffer = StringBuffer('round_')
      ..write(roundIndex)
      ..write('_')
      ..write(time.year.toString().padLeft(4, '0'))
      ..write(time.month.toString().padLeft(2, '0'))
      ..write(time.day.toString().padLeft(2, '0'))
      ..write('_')
      ..write(time.hour.toString().padLeft(2, '0'))
      ..write(time.minute.toString().padLeft(2, '0'))
      ..write(time.second.toString().padLeft(2, '0'));
    return buffer.toString();
  }

  /// 啟動新的錄影輪次，為每台裝置建立 CSV 檔頭。
  Future<void> startRoundLogging(String baseName) async {
    await abortActiveRound(); // 確保先前輪次完整清除
    if (_devices.isEmpty) {
      return; // 沒有裝置連線時不建立任何檔案
    }

    final directory = await _ensureStorageDirectory();

    final devices = _devices.values.toList()
      ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));

    for (int i = 0; i < devices.length && i < _maxDevices; i++) {
      final info = devices[i];
      final alias = info.slotAlias;
      final filePath = p.join(directory.path, '${baseName}_$alias.csv');
      final file = File(filePath);
      final existed = await file.exists();
      final sink = file.openWrite(mode: FileMode.writeOnlyAppend);

      // ---------- CSV 檔頭區 ----------
      // 若為首次建立檔案，補上格式宣告行，模擬參考專案中的 saveToCSVFile_V3 行為。
      if (!existed) {
        sink.writeln('CODI_RAW_V1');
      } else {
        // 續寫時額外加上空行分隔不同錄影輪次的資料。
        sink.writeln();
      }
      // 先寫入裝置名稱方便離線處理鎖定目標裝置，接著依指定順序輸出四元數與線性加速度欄位。
      sink.writeln('Device:${info.displayName}');
      sink.writeln('QuatI,QuatJ,QuatK,QuatW,AccelX,AccelY,AccelZ');

      _activeLogs[info.deviceId] = _ActiveImuLog(
        alias: alias,
        filePath: filePath,
        sink: sink,
      );
    }
  }

  /// 暫存線性加速度封包，待旋轉資料到齊後依序寫入。
  void logLinearAcceleration(
    String deviceId,
    Map<String, dynamic> sample,
    List<int> _rawBytes,
  ) {
    final log = _activeLogs[deviceId];
    if (log == null) return;
    // ---------- 線性加速度入隊 ----------
    log.linearQueue.add(Map<String, dynamic>.from(sample));
    _drainSynchronizedSamples(log);
  }

  /// 暫存 Game Rotation Vector 封包資料，待線性資料到齊後依序寫入。
  void logGameRotationVector(
    String deviceId,
    Map<String, dynamic> sample,
    List<int> _rawBytes,
  ) {
    final log = _activeLogs[deviceId];
    if (log == null) return;
    // ---------- Game Rotation Vector 入隊 ----------
    log.rotationQueue.add(Map<String, dynamic>.from(sample));
    _drainSynchronizedSamples(log);
  }

  /// 結束目前錄影輪次，關閉檔案並回傳裝置對應的 CSV 路徑。
  Future<Map<String, String>> finishRoundLogging() async {
    final results = <String, String>{};
    for (final entry in _activeLogs.entries) {
      _flushPendingSamples(entry.value, force: true);
      await entry.value.sink.flush();
      await entry.value.sink.close();
      final alias = _devices[entry.key]?.slotAlias ?? entry.key;
      results[alias] = entry.value.filePath;
    }
    _activeLogs.clear();
    return results;
  }

  /// 若錄影中途取消，刪除尚未完成的 CSV 以免留下空檔。
  Future<void> abortActiveRound() async {
    for (final entry in _activeLogs.entries) {
      entry.value.clearQueues();
      await entry.value.sink.close();
      final file = File(entry.value.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _activeLogs.clear();
  }

  /// 將臨時影片複製到專屬資料夾，並與 CSV 使用相同檔名基底。
  Future<String> persistVideoFile({
    required String sourcePath,
    required String baseName,
  }) async {
    final directory = await _ensureStorageDirectory();
    final targetPath = p.join(directory.path, '$baseName.mp4');
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);
    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  /// 判斷目前是否仍有尚未完成的 CSV 寫入流程。
  bool get hasActiveRound => _activeLogs.isNotEmpty;

  /// 取得當前儲存資料夾，若不存在則建立。
  Future<Directory> _ensureStorageDirectory() async {
    if (_storageDirectory != null) {
      return _storageDirectory!;
    }
    final baseDir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(baseDir.path, 'imu_records'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    _storageDirectory = target;
    return target;
  }

  /// 從隊列中同步線性與旋轉資料，忽略時間戳以先進先出方式合併。
  void _drainSynchronizedSamples(_ActiveImuLog log) {
    while (log.linearQueue.isNotEmpty && log.rotationQueue.isNotEmpty) {
      final linear = log.linearQueue.removeFirst();
      final rotation = log.rotationQueue.removeFirst();
      _writeCombinedSample(log, linear, rotation);
    }
  }

  /// 在輪次結束或逾時時輸出剩餘資料，force=true 代表即使缺資料也要寫出。
  void _flushPendingSamples(_ActiveImuLog log, {required bool force}) {
    if (!force) {
      _drainSynchronizedSamples(log);
      return;
    }

    // force=true 時仍只保留最小長度的有效資料，多出的項目直接丟棄避免欄位錯位。
    while (log.linearQueue.isNotEmpty && log.rotationQueue.isNotEmpty) {
      final linear = log.linearQueue.removeFirst();
      final rotation = log.rotationQueue.removeFirst();
      _writeCombinedSample(log, linear, rotation);
    }

    // 任何尚未配對的殘餘資料都直接清除，確保輸出長度一致。
    log.linearQueue.clear();
    log.rotationQueue.clear();
  }

  /// 寫出單列資料，缺少的欄位以空字串補齊保持欄位順序。
  void _writeCombinedSample(
    _ActiveImuLog log,
    Map<String, dynamic>? linear,
    Map<String, dynamic>? rotation,
  ) {
    if (linear == null && rotation == null) {
      return;
    }
    final values = <String>[
      _formatNumeric(rotation?['i']),
      _formatNumeric(rotation?['j']),
      _formatNumeric(rotation?['k']),
      _formatNumeric(rotation?['real']),
      _formatNumeric(linear?['x']),
      _formatNumeric(linear?['y']),
      _formatNumeric(linear?['z']),
    ];
    log.sink.writeln(values.join(','));
  }

  /// 將非空數值轉為字串，避免 null 導致欄位錯位。
  String _formatNumeric(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is num) {
      return value.toStringAsFixed(6);
    }
    final parsed = double.tryParse(value.toString());
    return parsed?.toStringAsFixed(6) ?? value.toString();
  }
}

/// 封裝裝置資訊，保留連線時間供排序使用。
class _ImuDeviceInfo {
  final String deviceId;
  final String displayName;
  final String slotAlias;
  final DateTime connectedAt;

  _ImuDeviceInfo({
    required this.deviceId,
    required this.displayName,
    required this.slotAlias,
    required this.connectedAt,
  });

  /// 產生適合用於檔名的縮短標籤，移除特殊字元。
  String get shortName {
    final sanitized = displayName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return sanitized.isEmpty ? 'imu' : sanitized.toLowerCase();
  }
}

/// 單一裝置在錄影輪次中的寫入資訊。
class _ActiveImuLog {
  final String alias; // 方便辨識裝置的簡短代號
  final String filePath; // 對應的 CSV 完整路徑
  final IOSink sink; // 寫入串流
  final ListQueue<Map<String, dynamic>> linearQueue = ListQueue(); // 線性加速度 FIFO
  final ListQueue<Map<String, dynamic>> rotationQueue = ListQueue(); // 旋轉向量 FIFO

  _ActiveImuLog({
    required this.alias,
    required this.filePath,
    required this.sink,
  });

  /// 關閉寫入器並視需求刪除檔案。
  Future<void> dispose({bool deleteFile = false}) async {
    await sink.close();
    if (deleteFile) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// 清空所有佇列，通常用於取消錄影時同步重置狀態。
  void clearQueues() {
    linearQueue.clear();
    rotationQueue.clear();
  }
}
