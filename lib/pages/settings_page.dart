import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/export_quality.dart';
import '../providers/app_state_provider.dart';
import '../providers/user_provider.dart';
import '../services/analytics_service.dart';
import '../services/app_update_service.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import '../widgets/update_dialog.dart';
import 'login_page.dart';
import 'onboarding_page.dart';
import 'privacy_settings_page.dart';
import 'reward_page.dart';
import 'terms_of_service_page.dart';
import 'upgrade_page.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

// ── 頭像壓縮（isolate 中執行）────────────────────────────────────────────
Uint8List _compressAvatar(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized = decoded.width > 512
      ? img.copyResize(decoded, width: 512)
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

// ── ExportQuality SharedPreferences 鍵（與 recording_history_page 共用）──
const _kLastQuality = 'last_export_quality';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── 資料狀態 ──────────────────────────────────────────────────
  String _displayName = '';
  String _email = '';
  bool _googleLinked = false;
  bool _appleLinked = false;
  bool _hasPassword = true; // 預設 true，避免載入期間誤顯示「設定密碼」
  ExportQuality _quality = ExportQuality.standard;  bool _isLoadingProfile = true;
  bool _isCheckingUpdate = false;
  String _appVersion = '';
  bool _analyticsConsent = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('settings');
    _loadAll();
  }

  Future<void> _loadAll() async {
    // 1. 本地快取（最快）
    final provider = context.read<UserProvider>();
    setState(() {
      _displayName = provider.displayName;
    });

    // 1b. App 版本（常駐顯示）
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version} (${info.buildNumber})');
    } catch (_) {}

    // 1c. 使用統計追蹤偏好
    final consent = await TermsOfServicePage.analyticsConsentGranted();
    if (mounted) setState(() => _analyticsConsent = consent);

    // 2. 上次選的輸出品質
    _quality = await _SkipHelperQuality.savedQuality();
    // 3. 伺服器 /me（email + googleLinked）
    try {
      final me = await VideoServerClient.instance.getMe();
      if (mounted && me != null) {
        setState(() {
          _email       = me['email'] as String? ?? '';
          _googleLinked = me['googleLinked'] as bool? ?? false;
          _appleLinked  = me['appleLinked'] as bool? ?? false;
          _hasPassword  = me['hasPassword'] as bool? ?? true;
          _displayName = me['displayName'] as String? ?? _displayName;
        });
      }
    } catch (_) {}

    // 4. Email fallback from local secure storage
    if (_email.isEmpty) {
      final stored = await AuthTokenStorage.instance.getUserEmail();
      if (mounted) setState(() => _email = stored ?? '');
    }

    if (mounted) setState(() => _isLoadingProfile = false);
  }

  // ── 修改大頭貼 ────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final raw = result.files.first.bytes ??
        await File(result.files.first.path!).readAsBytes();

    final compressed = await Isolate.run(() => _compressAvatar(raw));

    // 儲存到 app 目錄
    final dir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(dir.path, 'profile_avatars'));
    await avatarDir.create(recursive: true);
    final destPath = p.join(avatarDir.path, 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(destPath).writeAsBytes(compressed);

    if (!mounted) return;
    await context.read<UserProvider>().updateAvatar(destPath);
    setState(() {});
  }

  Future<void> _removeAvatar() async {
    if (!mounted) return;
    await context.read<UserProvider>().updateAvatar(null);
    setState(() {});
  }

  // ── 修改名稱 ──────────────────────────────────────────────────
  Future<void> _showRenameDialog() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.settingsChangeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: l.settingsChangeNameHint,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l.commonCancel, style: TextStyle(color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kBrandPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.commonSave),
          ),
        ],
      ),
    );
    // dialog 退場動畫期間 TextField 仍會讀取 controller，延後 dispose 避免紅屏
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (result == null || result.isEmpty || result == _displayName) return;

    // 本地先更新（即時）
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await context.read<UserProvider>().updateDisplayName(result);
    setState(() => _displayName = result);

    // 伺服器同步
    final ok = await VideoServerClient.instance.updateProfileName(result);
    if (!mounted) return;
    if (ok) {
      _showSnack(AppLocalizations.of(context).settingsNameUpdated);
    } else {
      _showSnack(AppLocalizations.of(context).settingsNameSyncFailed, isError: true);
    }
  }

  /// 密碼強度規則（與 server 一致：≥8 + 大寫 + 小寫 + 數字）
  static bool _isStrongPassword(String? v) =>
      v != null &&
      v.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(v) &&
      RegExp(r'[a-z]').hasMatch(v) &&
      RegExp(r'[0-9]').hasMatch(v);

  // ── 修改密碼 / 設定密碼（純 Google 帳號無舊密碼）──────────────
  Future<void> _showChangePasswordDialog() async {
    final l = AppLocalizations.of(context);
    final isSetMode = !_hasPassword;
    final formKey = GlobalKey<FormState>();
    final curCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    bool obscureCur  = true;
    bool obscureNew  = true;
    bool obscureConf = true;
    bool isLoading   = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          title: Row(children: [
            const Icon(Icons.lock_outline_rounded, color: kBrandPrimary, size: 20),
            const SizedBox(width: 8),
            Text(isSetMode ? l.settingsSetPassword : l.settingsChangePassword,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (isSetMode) ...[
                Text(l.settingsSetPasswordDesc,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 12),
              ] else ...[
                _pwField(l.settingsCurrentPassword, curCtrl, obscureCur, () => setS(() => obscureCur = !obscureCur),
                    validator: (v) => (v == null || v.isEmpty) ? l.settingsCurrentPasswordRequired : null),
                const SizedBox(height: 10),
              ],
              _pwField(l.settingsNewPassword, newCtrl, obscureNew, () => setS(() => obscureNew = !obscureNew),
                  validator: (v) => _isStrongPassword(v) ? null : l.validationPasswordTooShort),
              const SizedBox(height: 10),
              _pwField(l.settingsConfirmNewPassword, confCtrl, obscureConf, () => setS(() => obscureConf = !obscureConf),
                  validator: (v) => v != newCtrl.text ? l.validationPasswordMismatch : null),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: Text(l.commonCancel, style: TextStyle(color: ctx.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kBrandPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isLoading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setS(() => isLoading = true);
                final res = isSetMode
                    ? await VideoServerClient.instance.setPassword(newCtrl.text)
                    : await VideoServerClient.instance.changePassword(
                        currentPassword: curCtrl.text,
                        newPassword: newCtrl.text,
                      );
                setS(() => isLoading = false);
                if (!ctx.mounted) return;
                if (res['success'] == false) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(res['message']?.toString() ?? l.settingsConfirmChange),
                    backgroundColor: Colors.red,
                  ));
                } else {
                  Navigator.pop(ctx);
                  if (mounted) {
                    if (isSetMode) setState(() => _hasPassword = true);
                    _showSnack(isSetMode ? l.settingsPasswordSet : l.settingsPasswordChanged);
                  }
                }
              },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l.settingsConfirmChange),
            ),
          ],
        );
      }),
    );
    // 同上：等 dialog 退場動畫結束再 dispose
    Future.delayed(const Duration(milliseconds: 400), () {
      curCtrl.dispose(); newCtrl.dispose(); confCtrl.dispose();
    });
  }

  Widget _pwField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
          onPressed: toggle,
        ),
      ),
    );
  }

  // ── 第三方登入（Google 綁定）─────────────────────────────────
  Future<void> _linkGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com',
        scopes: const ['email', 'openid'],
      );
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final auth    = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        if (mounted) _showSnack(AppLocalizations.of(context).settingsGoogleCredentialFailed, isError: true);
        return;
      }

      if (!mounted) return;
      final res = await VideoServerClient.instance.linkGoogleAccount(idToken);
      if (!mounted) return;

      // 無論成功或失敗都重新 fetch 伺服器狀態，確保 UI 與後端同步
      final me = await VideoServerClient.instance.getMe();
      if (mounted && me != null) {
        setState(() => _googleLinked = me['googleLinked'] as bool? ?? _googleLinked);
      }

      if (!mounted) return;
      if (res['success'] == false) {
        final msg = res['message']?.toString() ?? '';
        // 若伺服器回報已連結，視為成功刷新狀態
        if (_googleLinked) {
          AnalyticsService.instance
              .logEvent('account_link', {'provider': 'google'});
          _showSnack(AppLocalizations.of(context).settingsGoogleLinked);
        } else {
          _showSnack(msg.isNotEmpty ? msg : AppLocalizations.of(context).settingsGoogleLinkFailed, isError: true);
        }
      } else {
        AnalyticsService.instance
            .logEvent('account_link', {'provider': 'google'});
        _showSnack(AppLocalizations.of(context).settingsGoogleLinked);
      }
    } catch (e) {
      if (mounted) _showSnack('Google: $e', isError: true);
    }
  }

  // ── 第三方登入（Apple 綁定，僅 iOS）───────────────────────────
  Future<void> _linkApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final identityToken = credential.identityToken;
      if (identityToken == null) {
        if (mounted) _showSnack(AppLocalizations.of(context).settingsAppleCredentialFailed, isError: true);
        return;
      }

      if (!mounted) return;
      final res = await VideoServerClient.instance.linkAppleAccount(identityToken);
      if (!mounted) return;

      // 無論成功或失敗都重新 fetch 伺服器狀態，確保 UI 與後端同步
      final me = await VideoServerClient.instance.getMe();
      if (mounted && me != null) {
        setState(() => _appleLinked = me['appleLinked'] as bool? ?? _appleLinked);
      }

      if (!mounted) return;
      if (res['success'] == false) {
        final msg = res['message']?.toString() ?? '';
        if (_appleLinked) {
          AnalyticsService.instance
              .logEvent('account_link', {'provider': 'apple'});
          _showSnack(AppLocalizations.of(context).settingsAppleLinked);
        } else {
          _showSnack(msg.isNotEmpty ? msg : AppLocalizations.of(context).settingsAppleLinkFailed, isError: true);
        }
      } else {
        AnalyticsService.instance
            .logEvent('account_link', {'provider': 'apple'});
        _showSnack(AppLocalizations.of(context).settingsAppleLinked);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        _showSnack('Apple: ${e.message}', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Apple: $e', isError: true);
    }
  }

  // ── 完整分析畫質 ──────────────────────────────────────────────
  Future<void> _showQualityPicker() async {
    final l = AppLocalizations.of(context);
    ExportQuality selected = _quality;
    final result = await showModalBottomSheet<ExportQuality>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          decoration: BoxDecoration(
            color: ctx.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: ctx.borderColor, borderRadius: BorderRadius.circular(2))),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.settingsAnalysisQuality,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.settingsQualityHint,
                  style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
            ),
            const SizedBox(height: 14),
            ...ExportQuality.values.map((q) {
              final isSelected = selected == q;
              return GestureDetector(
                onTap: () => setS(() => selected = q),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? kBrandPrimary.withValues(alpha: 0.07) : ctx.bgInset,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? kBrandPrimary : ctx.borderColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? kBrandPrimary : ctx.textHint,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(q.localizedLabel(l), style: TextStyle(
                        fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? kBrandPrimary : ctx.textPrimary,
                      )),
                      const SizedBox(height: 2),
                      Text(q.localizedSizeHint(l), style: TextStyle(fontSize: 12, color: ctx.textSecondary)),
                    ])),
                    Text(q.bitrateHint, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: isSelected ? kBrandPrimary : ctx.textHint,
                    )),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text(l.settingsApply),
              ),
            ),
          ]),
        );
      }),
    );

    if (result == null || result == _quality) return;
    setState(() => _quality = result);
    await _SkipHelperQuality.saveQuality(result);
    if (mounted) _showSnack(AppLocalizations.of(context).settingsQualityUpdated(result.localizedLabel(AppLocalizations.of(context))));
  }

  // ── 外觀主題 ──────────────────────────────────────────────────
  String _themeModeLabel(AppLocalizations l, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return l.settingsThemeLight;
      case ThemeMode.dark:
        return l.settingsThemeDark;
      case ThemeMode.system:
        return l.settingsThemeSystem;
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  Future<void> _showThemePicker() async {
    final l = AppLocalizations.of(context);
    final appState = context.read<AppStateProvider>();
    final result = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final current = appState.themeMode;
        return Container(
          decoration: BoxDecoration(
            color: ctx.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: ctx.borderColor, borderRadius: BorderRadius.circular(2))),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.settingsTheme,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
            ),
            const SizedBox(height: 14),
            ...[ThemeMode.system, ThemeMode.light, ThemeMode.dark].map((mode) {
              final isSelected = current == mode;
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, mode),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? kBrandPrimary.withValues(alpha: 0.07) : ctx.bgInset,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? kBrandPrimary : ctx.borderColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(children: [
                    Icon(_themeModeIcon(mode),
                        color: isSelected ? kBrandPrimary : ctx.textHint, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_themeModeLabel(l, mode), style: TextStyle(
                        fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? kBrandPrimary : ctx.textPrimary,
                      )),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, color: kBrandPrimary, size: 18),
                  ]),
                ),
              );
            }),
          ]),
        );
      },
    );

    if (result == null || !mounted) return;
    AnalyticsService.instance.logEvent('settings_theme_changed');
    appState.setThemeMode(result);
  }

  // ── 登出 ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.settingsConfirmLogout, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(l.settingsLogoutWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel, style: TextStyle(color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.homeLogout),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    AnalyticsService.instance.logEvent('user_logout');
    await AuthTokenStorage.instance.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ── 刪除帳號 ───────────────────────────────────────────────────
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
            child: Text(l.commonCancel,
                style: TextStyle(color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
    AnalyticsService.instance.logEvent('account_delete');
    await AuthTokenStorage.instance.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ── 檢查更新 ──────────────────────────────────────────────────
  Future<void> _checkUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final result = await AppUpdateService.check();
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      if (!result.needsUpdate) {
        _showSnack(l.settingsAlreadyLatest(result.currentVersion));
      } else {
        await showUpdateDialog(context, result);
      }
    } catch (e) {
      if (mounted) _showSnack(AppLocalizations.of(context).settingsUpdateCheckFailed, isError: true);
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  // ── 聯絡我們：選擇 Email 或意見表單 ────────────────────────────
  Future<void> _showContactSheet() async {
    final l = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l.settingsContactUs,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded, color: kBrandPrimary),
              title: Text(l.settingsContactViaEmail),
              subtitle: Text(kSupportEmail),
              onTap: () => Navigator.pop(ctx, 'email'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded, color: kBrandPrimary),
              title: Text(l.settingsContactViaForm),
              subtitle: Text(l.settingsContactViaFormDesc),
              onTap: () => Navigator.pop(ctx, 'form'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'email') {
      final l2 = AppLocalizations.of(context);
      final ok = await openContactSupport();
      if (!ok && mounted) {
        // 無郵件 App 時退回複製信箱
        await Clipboard.setData(const ClipboardData(text: kSupportEmail));
        if (mounted) {
          _showSnack('${l2.settingsContactEmailCopied}：$kSupportEmail');
        }
      }
    } else if (choice == 'form') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RewardPage()),
      );
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : kBrandPrimary,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final avatarPath = user.avatarPath;

    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: context.isDarkMode ? context.bgPage : kBrandPrimary,
        foregroundColor: context.isDarkMode ? context.textPrimary : Colors.white,
        elevation: 0,
        title: Text(l.settingsTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: SafeArea(top: false, child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── 個人資料卡 ──────────────────────────────────────
          _ProfileCard(
            displayName: user.displayName,
            email: _email,
            avatarPath: avatarPath,
            isLoading: _isLoadingProfile,
            onTapAvatar: _pickAvatar,
            onRemoveAvatar: avatarPath != null ? _removeAvatar : null,
          ),
          const SizedBox(height: 16),
          // ── 帳號設定 ────────────────────────────────────────
          _SectionHeader(l.settingsSectionAccount),
          _SettingsTile(
            icon: Icons.badge_outlined,
            iconColor: const Color(0xFF1565C0),
            title: l.settingsChangeName,
            subtitle: user.displayName,
            onTap: _showRenameDialog,
          ),
          _SettingsTile(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: _hasPassword ? l.settingsChangePassword : l.settingsSetPassword,
            subtitle: _hasPassword ? null : l.settingsSetPasswordDesc,
            onTap: _showChangePasswordDialog,
          ),
          _SettingsTile(
            icon: Icons.g_mobiledata_rounded,
            iconColor: kBrandPrimary,
            title: l.settingsGoogleLogin,
            subtitle: _googleLinked ? l.settingsGoogleLinked : l.settingsGoogleNotLinked,
            subtitleColor: _googleLinked ? kGoodColor : context.textHint,
            trailing: _googleLinked
                ? const Icon(Icons.check_circle_rounded, color: kGoodColor, size: 18)
                : null,
            onTap: _googleLinked ? null : _linkGoogle,
          ),
          if (Platform.isIOS)
            _SettingsTile(
              icon: Icons.apple_rounded,
              iconColor: context.textPrimary,
              title: l.settingsAppleLogin,
              subtitle: _appleLinked ? l.settingsAppleLinked : l.settingsAppleNotLinked,
              subtitleColor: _appleLinked ? kGoodColor : context.textHint,
              trailing: _appleLinked
                  ? const Icon(Icons.check_circle_rounded, color: kGoodColor, size: 18)
                  : null,
              onTap: _appleLinked ? null : _linkApple,
            ),
          const SizedBox(height: 16),
          // ── 分析偏好 ────────────────────────────────────────
          _SectionHeader(l.settingsSectionAnalysis),
          _SettingsTile(
            icon: Icons.high_quality_rounded,
            iconColor: const Color(0xFF0288D1),
            title: l.settingsAnalysisQuality,
            subtitle: _quality.localizedLabel(l),
            onTap: _showQualityPicker,
          ),
          _SettingsTile(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF607D8B),
            title: l.privacySettingsTitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsPage()),
            ),
          ),
          const SizedBox(height: 16),
          // ── 訂閱 ────────────────────────────────────────────
          _SectionHeader(l.settingsSectionSubscription),
          _SettingsTile(
            icon: Icons.workspace_premium_rounded,
            iconColor: const Color(0xFFFF9800),
            title: l.settingsViewSubscription,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UpgradePage()),
            ),
          ),
          const SizedBox(height: 16),
          // ── 一般 ────────────────────────────────────────────
          _SectionHeader(l.settingsSectionGeneral),
          _SettingsTile(
            icon: Icons.language_rounded,
            iconColor: const Color(0xFF0288D1),
            title: l.settingsLanguage,
            onTap: () {
              AnalyticsService.instance.logEvent('settings_language_changed');
              LanguageSelectorSheet.show(context);
            },
          ),
          _SettingsTile(
            icon: Icons.dark_mode_outlined,
            iconColor: const Color(0xFF5C6BC0),
            title: l.settingsTheme,
            subtitle: _themeModeLabel(l, context.watch<AppStateProvider>().themeMode),
            onTap: _showThemePicker,
          ),
          _SettingsTile(
            icon: Icons.school_outlined,
            iconColor: const Color(0xFF26A69A),
            title: l.settingsReplayTutorial,
            onTap: () => OnboardingPage.show(context),
          ),
          _SettingsTile(
            icon: Icons.system_update_rounded,
            iconColor: kBrandPrimary,
            title: l.settingsCheckUpdate,
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary),
                  )
                : null,
            onTap: _isCheckingUpdate ? null : _checkUpdate,
          ),
          _SettingsTile(
            icon: Icons.analytics_outlined,
            iconColor: const Color(0xFF8D6E63),
            title: l.settingsAnalytics,
            subtitle: l.settingsAnalyticsDesc,
            trailing: Switch(
              value: _analyticsConsent,
              onChanged: (v) async {
                setState(() => _analyticsConsent = v);
                await TermsOfServicePage.setAnalyticsConsent(v);
              },
            ),
          ),
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
          _SettingsTile(
            icon: Icons.mail_outline_rounded,
            iconColor: const Color(0xFF607D8B),
            title: l.settingsContactUs,
            subtitle: l.settingsContactSubtitle,
            onTap: _showContactSheet,
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: const Color(0xFF9AA6B2),
            title: l.settingsVersion,
            subtitle: _appVersion.isEmpty ? null : _appVersion,
            trailing: _appVersion.isEmpty
                ? const SizedBox.shrink()
                : Icon(Icons.copy_rounded, color: context.textHint, size: 16),
            onTap: _appVersion.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _appVersion));
                    if (mounted) _showSnack(l.settingsVersionCopied);
                  },
          ),
          const SizedBox(height: 28),
          // ── 登出按鈕 ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(l.homeLogout),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _logout,
            ),
          ),
          const SizedBox(height: 12),
          // ── 刪除帳號（雙平台強制要求）────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(l.settingsDeleteAccount),
              style: TextButton.styleFrom(
                foregroundColor: context.textHint,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _deleteAccount,
            ),
          ),
          const SizedBox(height: 40),
        ],
      )),
    );
  }
}

// ── 個人資料卡 ─────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String? avatarPath;
  final bool isLoading;
  final VoidCallback onTapAvatar;
  final VoidCallback? onRemoveAvatar;

  const _ProfileCard({
    required this.displayName,
    required this.email,
    required this.avatarPath,
    required this.isLoading,
    required this.onTapAvatar,
    required this.onRemoveAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kBrandPrimary,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(children: [
        // ── 大頭貼 ──
        GestureDetector(
          onTap: () => _showAvatarOptions(context),
          child: Stack(alignment: Alignment.bottomRight, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: ClipOval(
                child: avatarPath != null
                    ? Image.file(File(avatarPath!), fit: BoxFit.cover)
                    : const Icon(Icons.person_rounded, color: Colors.white, size: 42),
              ),
            ),
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 14, color: kBrandPrimary),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const SizedBox(height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
        else ...[
          Text(displayName,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(email, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ),
        ],
      ]),
    );
  }

  void _showAvatarOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: kBrandPrimary),
            title: Text(AppLocalizations.of(context).settingsPickFromGallery),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: () { Navigator.pop(context); onTapAvatar(); },
          ),
          if (onRemoveAvatar != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: Text(AppLocalizations.of(context).settingsRemoveAvatar, style: const TextStyle(color: Colors.red)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () { Navigator.pop(context); onRemoveAvatar!(); },
            ),
        ]),
      ),
    );
  }
}

// ── 設定區塊標題 ───────────────────────────────────────────────────────────
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

// ── 設定項目 Tile ──────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
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
        title: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: TextStyle(fontSize: 12.5, color: subtitleColor ?? context.textSecondary))
            : null,
        trailing: trailing ?? (onTap != null
            ? Icon(Icons.chevron_right_rounded, color: context.textHint, size: 20)
            : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}

// ── ExportQuality SharedPreferences 輔助（與 recording_history_page 共用同一 key）
class _SkipHelperQuality {
  _SkipHelperQuality._();

  static Future<ExportQuality> savedQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_kLastQuality);
    return ExportQuality.values.firstWhere(
      (q) => q.channelKey == val,
      orElse: () => ExportQuality.standard,
    );
  }

  static Future<void> saveQuality(ExportQuality q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastQuality, q.channelKey);
  }
}
