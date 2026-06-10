import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recording_history_entry.dart';
import 'recording_history_storage.dart';

const _baseUrl = 'https://orvia.api.atk.tw';

// ── API 回傳資料結構 ─────────────────────────────────────────

class SharePrepareResult {
  final String shareCode;
  final String uploadUrl;
  final String b2FileName;
  SharePrepareResult({required this.shareCode, required this.uploadUrl, required this.b2FileName});
  factory SharePrepareResult.fromJson(Map<String, dynamic> j) => SharePrepareResult(
    shareCode: j['shareCode'] as String,
    uploadUrl: j['uploadUrl'] as String,
    b2FileName: j['b2FileName'] as String,
  );
}

class ShareGetResult {
  final String title;
  final int sizeBytes;
  final DateTime expiresAt;
  final String downloadUrl;
  final String? sharerName;
  ShareGetResult({required this.title, required this.sizeBytes, required this.expiresAt, required this.downloadUrl, this.sharerName});
  factory ShareGetResult.fromJson(Map<String, dynamic> j) => ShareGetResult(
    title: j['title'] as String,
    sizeBytes: (j['sizeBytes'] as num).toInt(),
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    downloadUrl: j['downloadUrl'] as String,
    sharerName: j['sharerName'] as String?,
  );
}

// ── Isolate 壓縮參數 ─────────────────────────────────────────

class _ZipParams {
  final String sessionDir;
  final String destZipPath;
  final SendPort sendPort;
  _ZipParams(this.sessionDir, this.destZipPath, this.sendPort);
}

void _zipIsolate(_ZipParams params) {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(params.destZipPath);
    final dir = Directory(params.sessionDir);
    for (final entry in dir.listSync()) {
      if (entry is File && !entry.path.endsWith('.zip')) {
        encoder.addFile(entry);
      }
    }
    encoder.close();
    params.sendPort.send(null); // success
  } catch (e) {
    params.sendPort.send(e.toString()); // error message
  }
}

// ── Isolate 解壓縮參數 ────────────────────────────────────────

class _UnzipParams {
  final String zipPath;
  final String destDir;
  final SendPort sendPort;
  _UnzipParams(this.zipPath, this.destDir, this.sendPort);
}

void _unzipIsolate(_UnzipParams params) {
  try {
    final bytes = File(params.zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outPath = '${params.destDir}/${file.name}';
      if (file.isFile) {
        File(outPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      }
    }
    params.sendPort.send(null);
  } catch (e) {
    params.sendPort.send(e.toString());
  }
}

// ── ShareService ─────────────────────────────────────────────

class ShareService {
  static final _dio = Dio();

  /// 壓縮 session 資料夾 → zip，回傳 zip 檔案路徑
  /// [onProgress] 回傳 0.0~1.0（目前只有 0 和 1，壓縮沒有逐步進度）
  static Future<String> compressSession(
    String sessionDir, {
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(0.0);

    final tmp = await getTemporaryDirectory();
    final zipPath = '${tmp.path}/share_${DateTime.now().millisecondsSinceEpoch}.zip';

    final receivePort = ReceivePort();
    await Isolate.spawn(
      _zipIsolate,
      _ZipParams(sessionDir, zipPath, receivePort.sendPort),
    );

    final result = await receivePort.first;
    if (result != null) throw Exception('壓縮失敗：$result');

    onProgress?.call(1.0);
    return zipPath;
  }

  /// Step 1: 向 server 取得 pre-signed B2 upload URL
  static Future<SharePrepareResult> prepare({
    required String title,
    required int sizeBytes,
    String? sharerName,
  }) async {
    final resp = await _dio.post(
      '$_baseUrl/api/share/prepare',
      data: {'title': title, 'sizeBytes': sizeBytes, 'sharerName': sharerName},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    if (resp.statusCode != 200) throw Exception('prepare 失敗 ${resp.statusCode}');
    return SharePrepareResult.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Step 2: 直傳 zip 到 B2，透過 dio 回報上傳進度
  static Future<void> uploadToB2({
    required String uploadUrl,
    required String zipPath,
    void Function(double)? onProgress,
  }) async {
    final file = File(zipPath);
    final size = file.lengthSync();

    await _dio.put(
      uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          'Content-Type': 'application/zip',
          'Content-Length': size,
        },
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 2),
      ),
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
  }

  /// Step 3: 告知 server 上傳完成
  static Future<void> confirm(String shareCode) async {
    final resp = await _dio.post(
      '$_baseUrl/api/share/confirm',
      data: {'shareCode': shareCode},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    if (resp.statusCode != 200) throw Exception('confirm 失敗 ${resp.statusCode}');
  }

  /// 查詢分享碼資訊（下載端）
  static Future<ShareGetResult> getShareInfo(String shareCode) async {
    try {
      final resp = await _dio.get('$_baseUrl/api/share/$shareCode');
      return ShareGetResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw Exception('分享碼不存在或已過期');
      throw Exception('伺服器錯誤 ${e.response?.statusCode}');
    }
  }

  /// 下載 zip 並解壓縮，建立 RecordingHistoryEntry 加入歷史
  static Future<RecordingHistoryEntry> downloadAndImport({
    required ShareGetResult info,
    required String shareCode,
    void Function(double)? onDownloadProgress,
    void Function(String)? onStatus,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sessionDir = '${appDir.path}/golf_recordings/${shareCode}_$timestamp';
    Directory(sessionDir).createSync(recursive: true);

    // 下載 zip
    final zipPath = '$sessionDir/session.zip';
    onStatus?.call('下載中…');
    await _dio.download(
      info.downloadUrl,
      zipPath,
      onReceiveProgress: (recv, total) {
        if (total > 0) onDownloadProgress?.call(recv / total);
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
      ),
    );

    // 解壓縮
    onStatus?.call('解壓縮中…');
    final receivePort = ReceivePort();
    await Isolate.spawn(
      _unzipIsolate,
      _UnzipParams(zipPath, sessionDir, receivePort.sendPort),
    );
    final unzipResult = await receivePort.first;
    if (unzipResult != null) throw Exception('解壓縮失敗：$unzipResult');

    // 刪除 zip
    File(zipPath).deleteSync();

    // 找主影片（優先 swing.mp4，次選 clip.mp4）
    String? mainVideo;
    for (final name in ['swing.mp4', 'clip.mp4', 'analyzed.mp4']) {
      final f = File('$sessionDir/$name');
      if (f.existsSync()) { mainVideo = f.path; break; }
    }
    if (mainVideo == null) throw Exception('解壓縮後找不到影片檔案');

    // 讀取 session_meta.json 重建 entry（含原始分析結果）
    RecordingHistoryEntry entry;
    final metaFile = File('$sessionDir/session_meta.json');
    if (metaFile.existsSync()) {
      final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      final original = RecordingHistoryEntry.fromJson(json);

      // 路徑重映射：將原始 filePath 換成本機解壓縮後的路徑
      // thumbnailPath 若存在於 sessionDir 也一起重映射，否則清空
      String? remappedThumb;
      if (original.thumbnailPath != null) {
        final thumbName = p.basename(original.thumbnailPath!);
        final localThumb = File('$sessionDir/$thumbName');
        remappedThumb = localThumb.existsSync() ? localThumb.path : null;
      }

      final existing = await RecordingHistoryStorage.instance.loadHistory();
      final nextIndex = existing.isEmpty ? 1
          : existing.map((e) => e.roundIndex).reduce((a, b) => a > b ? a : b) + 1;

      entry = original.copyWith(
        filePath: mainVideo,
        roundIndex: nextIndex,
        thumbnailPath: remappedThumb,
        createdAt: DateTime.now(),   // 匯入時刻，確保出現在歷史最上方
        shareCode: null,
        shareExpiresAt: null,
        sharerName: info.sharerName,
      );
    } else {
      // fallback：meta 不存在時用最基本資料建立
      final existing = await RecordingHistoryStorage.instance.loadHistory();
      final nextIndex = existing.isEmpty ? 1
          : existing.map((e) => e.roundIndex).reduce((a, b) => a > b ? a : b) + 1;

      entry = RecordingHistoryEntry(
        filePath: mainVideo,
        roundIndex: nextIndex,
        recordedAt: DateTime.now(),
        createdAt: DateTime.now(),
        durationSeconds: 0,
        customName: info.title,
        isAnalyzed: File('$sessionDir/analyzed.mp4').existsSync(),
      );
    }

    await RecordingHistoryStorage.instance.upsertEntry(entry);

    return entry;
  }
}
