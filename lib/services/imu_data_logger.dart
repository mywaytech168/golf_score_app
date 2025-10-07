import 'dart:async';
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
  void registerDevice(BluetoothDevice device, {required String displayName}) {
    final deviceId = device.remoteId.str;
    _devices[deviceId] = _ImuDeviceInfo(
      deviceId: deviceId,
      displayName: displayName,
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
      final alias = 'dev${i + 1}_${info.shortName}';
      final filePath = p.join(directory.path, '${baseName}_$alias.csv');
      final sink = File(filePath).openWrite(mode: FileMode.writeOnlyAppend);
      sink.writeln(
        'device_alias,type,id,seq,status,timestamp_us,x,y,z,i,j,k,real,raw_hex',
      );
      _activeLogs[info.deviceId] = _ActiveImuLog(
        alias: alias,
        filePath: filePath,
        sink: sink,
      );
    }
  }

  /// 寫入線性加速度封包，保留所有欄位與原始十六進位內容。
  void logLinearAcceleration(
    String deviceId,
    Map<String, dynamic> sample,
    List<int> rawBytes,
  ) {
    final log = _activeLogs[deviceId];
    if (log == null) return;
    final line = StringBuffer()
      ..write(log.alias)
      ..write(',linear,')
      ..write(sample['id'])
      ..write(',')
      ..write(sample['seq'])
      ..write(',')
      ..write(sample['status'])
      ..write(',')
      ..write(sample['timestampUs'])
      ..write(',')
      ..write(sample['x'])
      ..write(',')
      ..write(sample['y'])
      ..write(',')
      ..write(sample['z'])
      ..write(',,,,')
      ..write(_formatRawBytes(rawBytes));
    log.sink.writeln(line.toString());
  }

  /// 寫入 Game Rotation Vector 封包資料。
  void logGameRotationVector(
    String deviceId,
    Map<String, dynamic> sample,
    List<int> rawBytes,
  ) {
    final log = _activeLogs[deviceId];
    if (log == null) return;
    final line = StringBuffer()
      ..write(log.alias)
      ..write(',rotation,')
      ..write(sample['id'])
      ..write(',')
      ..write(sample['seq'])
      ..write(',')
      ..write(sample['status'])
      ..write(',')
      ..write(sample['timestampUs'])
      ..write(',,,')
      ..write(sample['i'])
      ..write(',')
      ..write(sample['j'])
      ..write(',')
      ..write(sample['k'])
      ..write(',')
      ..write(sample['real'])
      ..write(',')
      ..write(_formatRawBytes(rawBytes));
    log.sink.writeln(line.toString());
  }

  /// 結束目前錄影輪次，關閉檔案並回傳裝置對應的 CSV 路徑。
  Future<Map<String, String>> finishRoundLogging() async {
    final results = <String, String>{};
    for (final entry in _activeLogs.entries) {
      await entry.value.sink.flush();
      await entry.value.sink.close();
      results[entry.key] = entry.value.filePath;
    }
    _activeLogs.clear();
    return results;
  }

  /// 若錄影中途取消，刪除尚未完成的 CSV 以免留下空檔。
  Future<void> abortActiveRound() async {
    for (final entry in _activeLogs.entries) {
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

  /// 將原始位元組轉為十六進位字串，方便除錯比對。
  String _formatRawBytes(List<int> bytes) {
    return bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}

/// 封裝裝置資訊，保留連線時間供排序使用。
class _ImuDeviceInfo {
  final String deviceId;
  final String displayName;
  final DateTime connectedAt;

  _ImuDeviceInfo({
    required this.deviceId,
    required this.displayName,
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
}
