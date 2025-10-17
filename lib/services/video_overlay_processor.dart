import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 封裝原生影片覆蓋處理的呼叫，確保頁面僅需關心輸入與錯誤處理。
class VideoOverlayProcessor {
  static const MethodChannel _channel = MethodChannel('video_overlay_channel');

  /// 將個人頭像與文字疊加到指定影片，若兩項皆未啟用則直接回傳原路徑。
  static Future<String?> process({
    required String inputPath,
    required bool attachAvatar,
    required String? avatarPath,
    required bool attachCaption,
    required String caption,
  }) async {
    // 沒有任何覆蓋需求時直接回傳來源路徑，避免不必要的檔案複製。
    if (!attachAvatar && (!attachCaption || caption.trim().isEmpty)) {
      return inputPath;
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.mp4';

    try {
      final result = await _channel.invokeMethod<String>('processVideo', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'attachAvatar': attachAvatar,
        'avatarPath': attachAvatar ? avatarPath : null,
        'attachCaption': attachCaption,
        'caption': caption.trim(),
      });

      if (result == null) {
        // 原生側若發生錯誤會回傳 null，因此在此加上判斷避免頁面直接使用無效路徑。
        return null;
      }

      // 若 Native 實作未產出檔案，移除空檔案以免殘留垃圾並回傳失敗。
      final file = File(result);
      if (!file.existsSync()) {
        return null;
      }
      return result;
    } on MissingPluginException {
      // iOS 或尚未實作的平台直接退回原路徑，確保功能仍可使用。
      return inputPath;
    } on PlatformException {
      return null;
    }
  }
}
