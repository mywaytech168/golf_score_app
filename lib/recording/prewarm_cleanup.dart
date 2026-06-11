import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 清理殘留的 pre-warm 錄影目錄。
///
/// pre-warm 預備了 session 目錄但使用者未開始錄影（取消/離開頁面）時，
/// 目錄會留在磁碟（內容只有 `swing.mp4.recording` 暫存或為空）。
/// 真正的錄影 session 一定有 `swing.mp4` 或 `clip.mp4`，不會被誤刪。
/// 僅清理超過 1 小時的目錄，避免動到進行中的 pre-warm。
Future<void> cleanupStalePrewarmDirs() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'golf_recordings'));
    if (!await root.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));

    await for (final ent in root.list()) {
      if (ent is! Directory) continue;
      final name = p.basename(ent.path);
      if (!name.startsWith('pw_') && !name.startsWith('shot_pw_')) continue;
      try {
        if ((await ent.stat()).modified.isAfter(cutoff)) continue;
        final hasVideo = File(p.join(ent.path, 'swing.mp4')).existsSync() ||
            File(p.join(ent.path, 'clip.mp4')).existsSync();
        if (hasVideo) continue;
        await ent.delete(recursive: true);
        debugPrint('[PrewarmCleanup] 已清理殘留目錄: $name');
      } catch (_) {}
    }
  } catch (e) {
    debugPrint('[PrewarmCleanup] 清理失敗: $e');
  }
}
