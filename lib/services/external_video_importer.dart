import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 內部影片預處理：特定平台底層檔案轉換或最佳化
class InternalVideoProcessor {
  const InternalVideoProcessor();

  /// 若影片未符合應用支援格式則轉檔，或回傳原始路徑
  Future<String> optimizeIfNeeded(
    String sourcePath, {
    String? baseName,
  }) async {
    // 支援格式直接回傳
    if (_isNativeFormat(sourcePath)) {
      return sourcePath;
    }

    // 若未來需進行轉檔等操作，在此處擴展邏輯
    // 目前先複製到暫存區保持兼容
    final cacheDir = await getTemporaryDirectory();
    final fileName = baseName != null
        ? '$baseName${p.extension(sourcePath)}'
        : p.basename(sourcePath);
    final persistedPath = p.join(cacheDir.path, fileName);
    if (!await File(persistedPath).exists()) {
      await File(sourcePath).copy(persistedPath);
    }
    return persistedPath;
  }

  /// 判斷格式是否為原生支援
  static bool _isNativeFormat(String filePath) {
    const supportedFormats = ['.mp4', '.mov', '.avi', '.mkv'];
    final ext = p.extension(filePath).toLowerCase();
    return supportedFormats.contains(ext);
  }
}
