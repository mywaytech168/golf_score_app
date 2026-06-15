import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 相機 + 麥克風權限統一處理。
///
/// - [requestSilently]：App 一啟動就呼叫，僅觸發系統權限詢問（已決定則 no-op），
///   不顯示任何後續引導 UI，避免一進 App 就彈自訂對話框。
/// - [ensure]：進入錄影 / SHOT 模式前呼叫；被拒時顯示引導對話框
///   （永久拒絕 → 開系統設定），回傳 false 表示不應繼續開相機。
///   兩處（錄影/SHOT）共用此邏輯，達成「在攝影/SHOT 模式可重複要求」。
class CameraPermissionService {
  const CameraPermissionService._();

  /// App 啟動時呼叫：僅對「尚未決定」的權限觸發系統對話框，不做任何 UI 引導。
  /// 已授權 / 已拒絕者一律不再請求（避免 iOS 對已決定權限重複 request 的異常）。
  static Future<void> requestSilently() async {
    if (!await Permission.camera.isGranted) {
      await Permission.camera.request();
    }
    if (!await Permission.microphone.isGranted) {
      await Permission.microphone.request();
    }
  }

  /// 確保相機 + 麥克風權限；被拒時引導使用者至設定。
  /// 回傳 false 表示權限不足，呼叫端不應繼續開相機。
  ///
  /// ★ 先查現況：已授權直接放行、不再 request——iOS 對「已授權」權限再呼叫
  ///   list `.request()` 可能回傳非 granted 狀態，導致明明已開卻卡住開不了相機。
  ///   僅對尚未授權者個別請求。
  static Future<bool> ensure(BuildContext context) async {
    var cam = await Permission.camera.status;
    var mic = await Permission.microphone.status;
    if (cam.isGranted && mic.isGranted) return true;

    if (!cam.isGranted) cam = await Permission.camera.request();
    if (!mic.isGranted) mic = await Permission.microphone.request();
    final camOk = cam.isGranted;
    final micOk = mic.isGranted;
    if (camOk && micOk) return true;

    final permanentlyDenied =
        cam.isPermanentlyDenied || mic.isPermanentlyDenied;
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.recordPermissionTitle),
          content: Text(camOk
              ? l10n.recordPermissionMicOnly
              : l10n.recordPermissionCameraAndMic),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (permanentlyDenied) openAppSettings();
              },
              child: Text(permanentlyDenied ? l10n.recordGoToSettings : l10n.recordGotIt),
            ),
          ],
        ),
      );
    }
    return false;
  }
}
