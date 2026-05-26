import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// 顯示更新對話框。
///
/// - [result.isForced] = true → 強制更新，無法關閉
/// - [result.isForced] = false → 非強制，可選「稍後提醒」跳過
///
/// 回傳 true = 使用者點了「立即更新」；false / null = 跳過（非強制）
Future<bool?> showUpdateDialog(
  BuildContext context,
  AppUpdateResult result,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: !result.isForced,
    builder: (_) => _UpdateDialog(result: result),
  );
}

// ─────────────────────────────────────────────────────────────────

class _UpdateDialog extends StatelessWidget {
  final AppUpdateResult result;
  const _UpdateDialog({required this.result});

  Future<void> _snooze(BuildContext context) async {
    await AppUpdateService.snoozeVersion(result.latestVersion);
    if (!context.mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _openStore(BuildContext context) async {
    if (result.updateUrl.isEmpty) return;
    final uri = Uri.parse(result.updateUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).updateCannotOpenStore)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 強制更新時攔截返回鍵，使用者無法跳過
      canPop: !result.isForced,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 頂部標題條 ──────────────────────────────────────
            _Header(isForced: result.isForced),

            // ── 主要內容 ────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 版本資訊列
                    _VersionRow(result: result),
                    const SizedBox(height: 16),

                    // 更新內容
                    if (result.releaseNotes.isNotEmpty) ...[
                      Text(
                        AppLocalizations.of(context).updateNotes,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0A3D2E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...result.releaseNotes.map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(
                                      color: kPrimaryGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Expanded(
                                child: Text(
                                  note,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF333333),
                                      height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // 強制更新提示
                    if (result.isForced) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).updateForcedWarning,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── 按鈕區 ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  // 立即更新
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openStore(context),
                      icon: const Icon(Icons.system_update_rounded, size: 18),
                      label: Text(AppLocalizations.of(context).updateNow,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                  // 非強制才顯示「稍後提醒」與「不再提醒」
                  if (!result.isForced) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(AppLocalizations.of(context).updateRemindLater,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () => _snooze(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade500,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(AppLocalizations.of(context).updateDontRemind,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 子元件
// ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isForced;
  const _Header({required this.isForced});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isForced
              ? [const Color(0xFFB71C1C), const Color(0xFFE53935)]
              : [const Color(0xFF1E8E5A), const Color(0xFF0A3D2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(
            isForced
                ? Icons.system_update_rounded
                : Icons.new_releases_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isForced
                    ? AppLocalizations.of(context).updateRequiredTitle
                    : AppLocalizations.of(context).updateFoundTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isForced
                    ? AppLocalizations.of(context).updateRequiredSubtitle
                    : AppLocalizations.of(context).updateFoundSubtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  final AppUpdateResult result;
  const _VersionRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _VersionChip(
            label: AppLocalizations.of(context).updateCurrentVersion,
            version: result.currentVersion,
            color: Colors.grey.shade600,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded,
                size: 16, color: Colors.grey),
          ),
          _VersionChip(
            label: AppLocalizations.of(context).updateLatestVersion,
            version: result.latestVersion,
            color: kPrimaryGreen,
          ),
          if (result.releaseDate.isNotEmpty) ...[
            const Spacer(),
            Text(
              result.releaseDate,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  final String label;
  final String version;
  final Color color;
  const _VersionChip(
      {required this.label, required this.version, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          'v$version',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
