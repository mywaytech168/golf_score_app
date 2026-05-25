import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_quality.dart';
import '../providers/user_provider.dart';
import '../services/auth_token_storage.dart';
import '../services/video_server_client.dart';
import 'login_page.dart';
import 'upgrade_page.dart';

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
  ExportQuality _quality = ExportQuality.standard;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    // 1. 本地快取（最快）
    final provider = context.read<UserProvider>();
    setState(() {
      _displayName = provider.displayName;
    });

    // 2. 上次選的輸出品質
    _quality = await _SkipHelperQuality.savedQuality();

    // 3. 伺服器 /me（email + googleLinked）
    try {
      final me = await VideoServerClient.instance.getMe();
      if (mounted && me != null) {
        setState(() {
          _email       = me['email'] as String? ?? '';
          _googleLinked = me['googleLinked'] as bool? ?? false;
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
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('修改名稱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '請輸入顯示名稱',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E5A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || result == _displayName) return;

    // 本地先更新（即時）
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await context.read<UserProvider>().updateDisplayName(result);
    setState(() => _displayName = result);

    // 伺服器同步（背景，失敗不影響）
    VideoServerClient.instance.updateProfileName(result).ignore();
    if (mounted) _showSnack('名稱已更新');
  }

  // ── 修改密碼 ──────────────────────────────────────────────────
  Future<void> _showChangePasswordDialog() async {
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
          title: const Row(children: [
            Icon(Icons.lock_outline_rounded, color: Color(0xFF1E8E5A), size: 20),
            SizedBox(width: 8),
            Text('修改密碼', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _pwField('目前密碼', curCtrl, obscureCur, () => setS(() => obscureCur = !obscureCur),
                  validator: (v) => (v == null || v.isEmpty) ? '請輸入目前密碼' : null),
              const SizedBox(height: 10),
              _pwField('新密碼', newCtrl, obscureNew, () => setS(() => obscureNew = !obscureNew),
                  validator: (v) => (v == null || v.length < 6) ? '至少 6 個字元' : null),
              const SizedBox(height: 10),
              _pwField('確認新密碼', confCtrl, obscureConf, () => setS(() => obscureConf = !obscureConf),
                  validator: (v) => v != newCtrl.text ? '兩次輸入不一致' : null),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E5A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isLoading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setS(() => isLoading = true);
                final res = await VideoServerClient.instance.changePassword(
                  currentPassword: curCtrl.text,
                  newPassword: newCtrl.text,
                );
                setS(() => isLoading = false);
                if (!ctx.mounted) return;
                if (res['success'] == false) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(res['message']?.toString() ?? '修改失敗'),
                    backgroundColor: Colors.red,
                  ));
                } else {
                  Navigator.pop(ctx);
                  if (mounted) _showSnack('密碼已修改');
                }
              },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('確認修改'),
            ),
          ],
        );
      }),
    );
    curCtrl.dispose(); newCtrl.dispose(); confCtrl.dispose();
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
      final googleSignIn = GoogleSignIn(scopes: ['email', 'openid']);
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final auth     = await account.authentication;
      final idToken  = auth.idToken;
      if (idToken == null) {
        if (mounted) _showSnack('無法取得 Google token', isError: true);
        return;
      }

      if (!mounted) return;
      final res = await VideoServerClient.instance.linkGoogleAccount(idToken);
      if (!mounted) return;
      if (res['success'] == false) {
        _showSnack(res['message']?.toString() ?? '綁定失敗', isError: true);
      } else {
        setState(() => _googleLinked = true);
        _showSnack('已成功綁定 Google 帳號');
      }
    } catch (e) {
      if (mounted) _showSnack('Google 登入失敗: $e', isError: true);
    }
  }

  // ── 完整分析畫質 ──────────────────────────────────────────────
  Future<void> _showQualityPicker() async {
    ExportQuality selected = _quality;
    final result = await showModalBottomSheet<ExportQuality>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFDDE1E7), borderRadius: BorderRadius.circular(2))),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('完整分析輸出品質',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('選擇後將作為預設值，下次分析自動套用',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
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
                    color: isSelected ? const Color(0xFF1E8E5A).withValues(alpha: 0.07) : const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1E8E5A) : const Color(0xFFDDE1E7),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? const Color(0xFF1E8E5A) : const Color(0xFFB0B8C1),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(q.label, style: TextStyle(
                        fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? const Color(0xFF1E8E5A) : const Color(0xFF1A1A2E),
                      )),
                      const SizedBox(height: 2),
                      Text(q.sizeHint, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ])),
                    Text(q.bitrateHint, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: isSelected ? const Color(0xFF1E8E5A) : const Color(0xFFB0B8C1),
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
                  backgroundColor: const Color(0xFF1E8E5A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('套用'),
              ),
            ),
          ]),
        );
      }),
    );

    if (result == null || result == _quality) return;
    setState(() => _quality = result);
    await _SkipHelperQuality.saveQuality(result);
    if (mounted) _showSnack('輸出品質已更新為「${result.label}」');
  }

  // ── 登出 ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('確定登出？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('登出後需重新登入才能使用雲端功能。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AuthTokenStorage.instance.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF1E8E5A),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final avatarPath = user.avatarPath;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E8E5A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('設定', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: ListView(
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
          _SectionHeader('帳號'),
          _SettingsTile(
            icon: Icons.badge_outlined,
            iconColor: const Color(0xFF1565C0),
            title: '修改名稱',
            subtitle: user.displayName,
            onTap: _showRenameDialog,
          ),
          _SettingsTile(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: '修改密碼',
            onTap: _showChangePasswordDialog,
          ),
          _SettingsTile(
            icon: Icons.g_mobiledata_rounded,
            iconColor: const Color(0xFF1E8E5A),
            title: 'Google 登入',
            subtitle: _googleLinked ? '已綁定' : '尚未綁定，點擊連結 Google 帳號',
            subtitleColor: _googleLinked ? const Color(0xFF1E8E5A) : const Color(0xFF9AA6B2),
            trailing: _googleLinked
                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1E8E5A), size: 18)
                : null,
            onTap: _googleLinked ? null : _linkGoogle,
          ),
          const SizedBox(height: 16),
          // ── 分析偏好 ────────────────────────────────────────
          _SectionHeader('分析偏好'),
          _SettingsTile(
            icon: Icons.high_quality_rounded,
            iconColor: const Color(0xFF0288D1),
            title: '完整分析輸出品質',
            subtitle: _quality.label,
            onTap: _showQualityPicker,
          ),
          const SizedBox(height: 16),
          // ── 訂閱 ────────────────────────────────────────────
          _SectionHeader('訂閱'),
          _SettingsTile(
            icon: Icons.workspace_premium_rounded,
            iconColor: const Color(0xFFFF9800),
            title: '查看訂閱方案',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UpgradePage()),
            ),
          ),
          const SizedBox(height: 28),
          // ── 登出按鈕 ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('登出'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _logout,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
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
      color: const Color(0xFF1E8E5A),
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
              child: const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF1E8E5A)),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: const Color(0xFFDDE1E7), borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF1E8E5A)),
            title: const Text('從相簿選擇'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: () { Navigator.pop(context); onTapAvatar(); },
          ),
          if (onRemoveAvatar != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('移除大頭貼', style: TextStyle(color: Colors.red)),
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
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: Color(0xFF9AA6B2), letterSpacing: 0.5)),
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
        color: Colors.white,
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
        title: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        subtitle: subtitle != null
            ? Text(subtitle!, style: TextStyle(fontSize: 12.5, color: subtitleColor ?? const Color(0xFF6B7280)))
            : null,
        trailing: trailing ?? (onTap != null
            ? const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0B8C1), size: 20)
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
