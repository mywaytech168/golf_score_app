import 'package:flutter/material.dart';

import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';
import 'reward_page.dart';
import 'terms_of_service_page.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 隱私與分析設定頁
///
/// 內容：
/// 1. 資料蒐集說明（靜態說明：僅使用者主動操作時上傳，無背景上傳/遙測）
/// 2. 隱私權政策 / 服務條款入口（外部網頁，失敗退回 App 內 TermsViewPage）
/// 3. 分析資料上傳說明 + 查看上傳審核狀態（導向 RewardPage）
/// 4. 刪除帳號（與 settings_page 相同的二次確認軟刪除流程）
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : kBrandPrimary,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── 刪除帳號（與 settings_page 同款流程：兩段確認 + DELETE /api/user/me）──
  Future<void> _deleteAccount() async {
    final l = AppLocalizations.of(context);

    // 第一段確認：說明後果。
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.settingsDeleteAccount,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(l.settingsDeleteAccountWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(l.commonCancel, style: TextStyle(color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonContinue),
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    // 第二段確認：輸入 DELETE 防止誤觸。
    final controller = TextEditingController();
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final canDelete = controller.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(l.settingsDeleteAccountConfirmTitle,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.settingsDeleteAccountConfirmHint),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'DELETE',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel,
                    style: TextStyle(color: ctx.textSecondary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: canDelete ? Colors.red : Colors.grey,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: Text(l.settingsDeleteAccount),
              ),
            ],
          );
        },
      ),
    );
    // dialog 退場動畫期間 TextField 仍會讀取 controller，延後 dispose
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (confirm2 != true || !mounted) return;

    // 執行刪除（顯示阻塞 loading）。
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    bool ok = false;
    try {
      ok = await VideoServerClient.instance.deleteAccount();
    } on UnauthorizedException {
      ok = false;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 關閉 loading

    if (!ok) {
      _showSnack(l.settingsDeleteAccountFailed, isError: true);
      return;
    }

    // 刪除成功：清除本地憑證並回登入頁。
    await AuthTokenStorage.instance.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor:
            context.isDarkMode ? context.bgPage : kBrandPrimary,
        foregroundColor:
            context.isDarkMode ? context.textPrimary : Colors.white,
        elevation: 0,
        title: Text(l.privacySettingsTitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          // ── 資料蒐集說明 ────────────────────────────────────
          _SectionHeader(l.privacySectionDataCollection),
          _InfoCard(
            icon: Icons.cloud_off_rounded,
            iconColor: kBrandPrimary,
            text: l.privacyDataCollectionDesc,
          ),
          const SizedBox(height: 16),
          // ── 政策文件 ────────────────────────────────────────
          _SectionHeader(l.privacySectionPolicies),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            iconColor: const Color(0xFF607D8B),
            title: l.settingsPrivacyPolicy,
            onTap: () async {
              final ok = await openPrivacyPolicy();
              if (!ok && context.mounted) {
                // 網頁開啟失敗時退回 App 內條款檢視
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsViewPage()),
                );
              }
            },
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            iconColor: const Color(0xFF607D8B),
            title: l.settingsTermsOfService,
            onTap: () async {
              final ok = await openTermsOfService();
              if (!ok && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsViewPage()),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          // ── 分析資料上傳 ────────────────────────────────────
          _SectionHeader(l.privacySectionUpload),
          _InfoCard(
            icon: Icons.model_training_rounded,
            iconColor: const Color(0xFF0288D1),
            text: l.privacyUploadDesc,
          ),
          _SettingsTile(
            icon: Icons.fact_check_outlined,
            iconColor: const Color(0xFF0288D1),
            title: l.privacyUploadStatusEntry,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RewardPage()),
            ),
          ),
          const SizedBox(height: 16),
          // ── 帳號 ────────────────────────────────────────────
          _SectionHeader(l.privacySectionAccount),
          _SettingsTile(
            icon: Icons.delete_forever_rounded,
            iconColor: Colors.red,
            title: l.settingsDeleteAccount,
            subtitle: l.privacyDeleteAccountSubtitle,
            onTap: _deleteAccount,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── 區塊標題（與 settings_page 同款）────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
    child: Text(title,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: context.textSecondary, letterSpacing: 0.5)),
  );
}

// ── 靜態說明卡片 ─────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, height: 1.55, color: context.textSecondary)),
          ),
        ],
      ),
    );
  }
}

// ── 設定項目 Tile（與 settings_page 同款）────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(fontSize: 12.5, color: context.textSecondary))
            : null,
        trailing: onTap != null
            ? Icon(Icons.chevron_right_rounded,
                color: context.textHint, size: 20)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}
