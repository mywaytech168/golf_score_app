import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 影片覆蓋燒錄結果。
class VideoOverlayResult {
  const VideoOverlayResult({required this.path, required this.burned});

  /// 可供後續使用的影片路徑（燒錄失敗時為原始輸入路徑）。
  final String path;

  /// 是否真的完成頭像 / 字幕燒錄。
  final bool burned;
}

/// 封裝原生影片覆蓋處理的呼叫，確保頁面僅需關心輸入與錯誤處理。
class VideoOverlayProcessor {
  static const MethodChannel _channel = MethodChannel('video_overlay_channel');

  /// 將個人頭像與文字疊加到指定影片並重新編碼（雙平台原生燒錄）。
  ///
  /// - 若兩項皆未啟用，直接回傳原路徑（burned=false）。
  /// - 原生燒錄失敗時 fallback 回原始路徑（burned=false），不會丟例外，
  ///   呼叫端可依 [VideoOverlayResult.burned] 判斷是否真的疊加成功。
  static Future<VideoOverlayResult> process({
    required String inputPath,
    required bool attachAvatar,
    required String? avatarPath,
    required bool attachCaption,
    required String caption,
  }) async {
    // 沒有任何覆蓋需求時直接回傳來源路徑，避免不必要的轉檔。
    if (!attachAvatar && (!attachCaption || caption.trim().isEmpty)) {
      return VideoOverlayResult(path: inputPath, burned: false);
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.mp4';

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'processVideo',
        {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'attachAvatar': attachAvatar,
          'avatarPath': attachAvatar ? avatarPath : null,
          'attachCaption': attachCaption,
          'caption': caption.trim(),
        },
      );

      final path = result?['path'] as String?;
      final burned = result?['burned'] as bool? ?? false;
      if (path == null || !File(path).existsSync()) {
        // 原生側回報成功但檔案不存在 → 視為失敗，退回原始影片。
        return VideoOverlayResult(path: inputPath, burned: false);
      }
      return VideoOverlayResult(path: path, burned: burned);
    } on MissingPluginException {
      // 尚未實作的平台直接退回原路徑，確保功能仍可使用。
      return VideoOverlayResult(path: inputPath, burned: false);
    } on PlatformException {
      // 燒錄失敗 fallback：維持原本「不會壞」的行為，回傳原始影片。
      return VideoOverlayResult(path: inputPath, burned: false);
    }
  }
}
