import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// 影片匯出 / 下載服務
///
/// Android: MediaStore API 直接存到「下載」資料夾
///   - API 29+：無需額外權限
///   - API 28-：需 WRITE_EXTERNAL_STORAGE（manifest 已宣告 maxSdkVersion="28"）
///
/// iOS: PHPhotoLibrary 存到「相機膠卷」（Photos App）
///   - 需 NSPhotoLibraryAddUsageDescription（Info.plist 已設）
///   - 權限被拒時 fallback 到 Share Sheet
class VideoExportService {
  const VideoExportService._();

  static const _channel =
      MethodChannel('com.example.golf_score_app/video_export');

  // ────────────────────────────────────────────────────────────

  /// 選取目前 session 中最佳的可下載影片路徑
  ///   final.mp4 > skeleton.mp4 > swing.mp4（依分析完整度排序）
  static String? bestVideoPath(String sessionDir) {
    for (final name in ['final.mp4', 'skeleton.mp4', 'swing.mp4', 'swing.mov']) {
      final f = File(p.join(sessionDir, name));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────

  /// 下載影片到裝置
  ///   [videoPath]  : 要下載的影片完整路徑
  ///   [displayName]: 儲存時顯示的檔名（不含副檔名）
  static Future<ExportResult> download(
    String videoPath, {
    String? displayName,
  }) async {
    final file = File(videoPath);
    if (!file.existsSync()) {
      return ExportResult._(ExportStatus.failed, '影片檔案不存在');
    }

    final ext      = p.extension(videoPath).toLowerCase(); // .mp4 or .mov
    final base     = displayName ?? _defaultName(videoPath);
    final fileName = '$base$ext';

    if (Platform.isAndroid) {
      return _downloadAndroid(videoPath, fileName);
    } else if (Platform.isIOS) {
      return _saveToPhotosIOS(videoPath, fileName);
    } else {
      return _shareViaSheet(videoPath, fileName);
    }
  }

  // ── Android：存到「下載」資料夾 ──────────────────────────────

  static Future<ExportResult> _downloadAndroid(
    String srcPath,
    String fileName,
  ) async {
    try {
      final savedPath = await _channel.invokeMethod<String>(
        'saveToDownloads',
        {'srcPath': srcPath, 'fileName': fileName},
      );
      if (savedPath != null && savedPath.isNotEmpty) {
        debugPrint('[VideoExport] ✅ Android Downloads: $savedPath');
        return ExportResult._(ExportStatus.savedToDownloads, savedPath);
      }
      return ExportResult._(ExportStatus.failed, '儲存失敗（未回傳路徑）');
    } on PlatformException catch (e) {
      debugPrint('[VideoExport] ❌ saveToDownloads 失敗: ${e.message}，fallback 到 Share Sheet');
      return _shareViaSheet(srcPath, fileName);
    }
  }

  // ── iOS：存到相機膠卷 ─────────────────────────────────────────

  static Future<ExportResult> _saveToPhotosIOS(
    String srcPath,
    String fileName,
  ) async {
    try {
      final rawResult = await _channel.invokeMethod<String>(
        'saveToDownloads',
        {'srcPath': srcPath, 'fileName': fileName},
      );
      debugPrint('[VideoExport] iOS result: $rawResult');
      if (rawResult == 'saved_to_photos') {
        return ExportResult._(ExportStatus.savedToPhotos, null);
      } else if (rawResult == 'share_sheet') {
        // fallback Share Sheet was shown (permission denied)
        return ExportResult._(ExportStatus.sharedViaSheet, null);
      }
      return ExportResult._(ExportStatus.failed, '未知回傳: $rawResult');
    } on PlatformException catch (e) {
      debugPrint('[VideoExport] ❌ iOS saveToDownloads 失敗: ${e.message}');
      return _shareViaSheet(srcPath, fileName);
    }
  }

  // ── Share Sheet（fallback）────────────────────────────────────

  static Future<ExportResult> _shareViaSheet(
    String srcPath,
    String fileName,
  ) async {
    try {
      await Share.shareXFiles(
        [XFile(srcPath, name: fileName, mimeType: _mime(srcPath))],
        subject: fileName,
      );
      return ExportResult._(ExportStatus.sharedViaSheet, null);
    } catch (e) {
      debugPrint('[VideoExport] ❌ shareXFiles 失敗: $e');
      return ExportResult._(ExportStatus.failed, e.toString());
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  static String _defaultName(String path) {
    final now = DateTime.now();
    final ts  = '${now.year}'
        '${now.month.toString().padLeft(2, "0")}'
        '${now.day.toString().padLeft(2, "0")}'
        '_${now.hour.toString().padLeft(2, "0")}'
        '${now.minute.toString().padLeft(2, "0")}';
    return 'golf_swing_$ts';
  }

  static String _mime(String path) =>
      path.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
}

// ────────────────────────────────────────────────────────────────

enum ExportStatus {
  savedToDownloads,  // Android: 存到「下載」資料夾
  savedToPhotos,     // iOS: 存到相機膠卷
  sharedViaSheet,    // 透過 Share Sheet（iOS 權限被拒 fallback / 其他平台）
  failed,
}

class ExportResult {
  final ExportStatus status;
  final String?      detail;  // 成功時為路徑或 null，失敗時為錯誤訊息

  const ExportResult._(this.status, this.detail);

  bool get success => status != ExportStatus.failed;
}
