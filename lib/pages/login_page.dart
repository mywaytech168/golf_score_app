import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

import '../services/video_server_client.dart';
import '../services/auth_token_storage.dart';
import '../theme/app_theme.dart';
import 'main_shell_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _rememberMeKey = 'login.remember_me';
  static const String _rememberedEmailKey = 'login.remembered_email';
  static const String _rememberedPasswordKey = 'login.remembered_password';

  // 模式
  bool _isRegisterMode = false;

  // 控制器
  final _identifierController = TextEditingController(); // 登入：用戶名 / Email
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();   // 註冊：用戶名
  final _emailController = TextEditingController();      // 註冊：Email
  final _displayNameController = TextEditingController(); // 註冊：顯示名稱
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController(); // 註冊：邀請碼（可選）

  final _formKey = GlobalKey<FormState>();

  bool _rememberMe = false;
  bool _isObscure = true;
  bool _isConfirmObscure = true;
  bool _isLoading = false;
  bool _isGoogleSigningIn = false;

  // ── Dev 小幫手（debug only）──────────────────────────────────
  int _devTapCount = 0;
  Timer? _devTapTimer;

  late final Map<Permission, String> _blePermissions;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  @override
  void initState() {
    super.initState();
    _blePermissions = _buildRequiredPermissions();
    _permissionStatuses = {};
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _devTapTimer?.cancel();
    _identifierController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  // ── 模式切換 ────────────────────────────────────────────────

  void _switchMode(bool toRegister) {
    setState(() {
      _isRegisterMode = toRegister;
      _formKey.currentState?.reset();
    });
  }

  // ── 登入 ────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final response = await VideoServerClient.instance.loginLocal(
        username: _identifierController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        await _persistRememberedCredentials();

        final prefs = await SharedPreferences.getInstance();
        final user = response['user'];
        if (user is Map) {
          if (user['email'] != null) await prefs.setString('user_email', user['email'].toString());
          if (user['displayName'] != null) await prefs.setString('user_name', user['displayName'].toString());
        }

        if (!mounted) return;
        _showSnackBar(AppLocalizations.of(context).msgLoginSuccess);
        final ok = await _ensureBlePermissions();
        if (!mounted || !ok) return;
        await _navigateToHome();
      } else {
        _showSnackBar(
          response['message'] ?? AppLocalizations.of(context).msgLoginFailed,
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).msgLoginFailedWithError(e.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 註冊 ────────────────────────────────────────────────────

  Future<void> _handleRegister() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final response = await VideoServerClient.instance.registerLocal(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim().isEmpty
            ? _usernameController.text.trim()
            : _displayNameController.text.trim(),
        inviteCode: _inviteCodeController.text.trim().isEmpty
            ? null
            : _inviteCodeController.text.trim(),
      );

      if (!mounted) return;

      if (response['success'] == true) {
        _showSnackBar(AppLocalizations.of(context).msgRegisterSuccess);
        _identifierController.text = _usernameController.text.trim();
        _passwordController.clear();
        _switchMode(false);
      } else {
        _showSnackBar(
          response['message'] ?? AppLocalizations.of(context).msgRegisterFailed,
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).msgRegisterFailedWithError(e.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google 登入 ─────────────────────────────────────────────

  Future<void> _handleGoogleLogin() async {
    if (_isGoogleSigningIn) return;
    setState(() => _isGoogleSigningIn = true);

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        if (!mounted) return;
        _showSnackBar(AppLocalizations.of(context).msgGoogleLoginCancelled);
        return;
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        if (!mounted) return;
        _showSnackBar(
          AppLocalizations.of(context).msgGoogleLoginFailed('no IdToken'),
          isError: true,
        );
        return;
      }

      final dio = Dio();
      final response = await dio.post(
        'https://orvia.api.atk.tw/api/auth/google-login',
        data: {
          'idToken': googleAuth.idToken,
          'email': googleUser.email,
          'displayName': googleUser.displayName,
          'avatarUrl': googleUser.photoUrl,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final token = data['token'] ?? data['accessToken']
          ?? (data['data'] is Map ? data['data']['token'] ?? data['data']['accessToken'] : null);

      if (token == null || (token as String).isEmpty) {
        if (!mounted) return;
        _showSnackBar(AppLocalizations.of(context).msgGoogleLoginNoToken, isError: true);
        return;
      }

      final user = data['user'] ?? (data['data'] is Map ? data['data']['user'] : null);
      await AuthTokenStorage.instance.saveTokens(
        accessToken: token,
        refreshToken: data['refreshToken'],
        userId: user?['id']?.toString() ?? googleUser.email,
        userEmail: user?['email'] ?? googleUser.email,
      );

      final prefs = await SharedPreferences.getInstance();
      if (user?['displayName'] != null) {
        await prefs.setString('user_name', user['displayName'].toString());
      }

      if (mounted) {
        _showSnackBar(AppLocalizations.of(context).msgGoogleLoginSuccess);
        await _navigateToHome();
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? '';
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).msgGoogleLoginFailed(msg),
          isError: true,
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).msgGoogleLoginFailed(error.message ?? ''),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).msgGoogleLoginFailed(e.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  // ── Remember Me ─────────────────────────────────────────────

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_rememberMeKey) ?? false;
    if (!mounted) return;
    setState(() {
      _rememberMe = saved;
      if (saved) {
        _identifierController.text = prefs.getString(_rememberedEmailKey) ?? '';
        _passwordController.text = prefs.getString(_rememberedPasswordKey) ?? '';
      }
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberedEmailKey, _identifierController.text);
      await prefs.setString(_rememberedPasswordKey, _passwordController.text);
    } else {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.remove(_rememberedEmailKey);
      await prefs.remove(_rememberedPasswordKey);
    }
  }

  Future<void> _onRememberMeChanged(bool value) async {
    setState(() => _rememberMe = value);
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.remove(_rememberedEmailKey);
      await prefs.remove(_rememberedPasswordKey);
    } else {
      await prefs.setBool(_rememberMeKey, true);
    }
  }

  // ── 導向首頁 ────────────────────────────────────────────────

  Future<void> _navigateToHome() async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShellPage()),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : kPrimaryGreen,
      ),
    );
  }

  // ── 權限 ────────────────────────────────────────────────────

  void _showPermissionStatusDialog() {
    final l10n = AppLocalizations.of(context);
    final statusText = _permissionStatuses.entries
        .map((e) => '${_permLabel(e.key, l10n)}: ${e.value}')
        .join('\n');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.permStatusTitle),
        content: Text(statusText.isEmpty ? l10n.permNotChecked : statusText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonClose)),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await openAppSettings(); },
            child: Text(l10n.commonOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureBlePermissions() =>
      _requestBlePermissions(showDeniedDialog: true);

  Future<bool> _requestBlePermissions({required bool showDeniedDialog}) async {
    final updatedStatuses = <Permission, PermissionStatus>{};
    for (final entry in _blePermissions.entries) {
      updatedStatuses[entry.key] = await entry.key.request();
    }
    if (!mounted) return false;
    setState(() => _permissionStatuses = updatedStatuses);
    if (_arePermissionsAllGranted) return true;
    if (showDeniedDialog) await _showPermissionGuideDialog();
    return false;
  }

  Future<void> _showPermissionGuideDialog() async {
    final l10n = AppLocalizations.of(context);
    final instructions = Platform.isIOS
        ? l10n.permIosInstructions
        : l10n.permAndroidInstructions;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Text(l10n.permDialogTitle),
        ]),
        content: SingleChildScrollView(
          child: Text(instructions, style: const TextStyle(fontSize: 15)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.permIKnow)),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await openAppSettings(); },
            child: Text(l10n.permGoToSettings),
          ),
        ],
      ),
    );
  }

  bool get _arePermissionsAllGranted {
    if (_blePermissions.isEmpty) return true;
    if (_permissionStatuses.length < _blePermissions.length) return false;
    return _permissionStatuses.values.every(_isGranted);
  }

  bool _isGranted(PermissionStatus? s) =>
      s != null && (s.isGranted || s == PermissionStatus.limited || s == PermissionStatus.provisional);

  Map<Permission, String> _buildRequiredPermissions() => {};

  String _permLabel(Permission perm, AppLocalizations l10n) {
    if (perm == Permission.locationWhenInUse) return l10n.permLocation;
    return perm.toString();
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryGreen, kPrimaryDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _onDevLogoTap,
                  child: Image.asset(
                    'assets/branding/logo_horizontal.png',
                    height: 56,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  _isRegisterMode ? l10n.authRegisterTitle : l10n.authWelcomeBack,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegisterMode ? l10n.authRegisterSubtitle : l10n.authLoginSubtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                if (!_arePermissionsAllGranted && !_isRegisterMode)
                  _buildPermissionReminder(theme),
                const SizedBox(height: 32),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 16,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Form(
                      key: _formKey,
                      child: _isRegisterMode ? _buildRegisterForm(theme) : _buildLoginForm(theme),
                    ),
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 忘記密碼 ─────────────────────────────────────────────────

  void _showForgotPasswordSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForgotPasswordSheet(
        onDone: (email) {
          // 重設成功後預填 email
          _identifierController.text = email;
        },
      ),
    );
  }

  Widget _buildLoginForm(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.authLoginTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold, color: kPrimaryDark)),
        const SizedBox(height: 24),
        TextFormField(
          controller: _identifierController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l10n.authUsernameOrEmail,
            hintText: l10n.authUsernameHint,
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return l10n.validationEnterUsernameOrEmail;
            return null;
          },
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _passwordController,
          obscureText: _isObscure,
          decoration: InputDecoration(
            labelText: l10n.authPassword,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isObscure = !_isObscure),
              icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return l10n.validationEnterPassword;
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (v) => _onRememberMeChanged(v ?? false),
            ),
            Text(l10n.authRememberMe),
            const Spacer(),
            TextButton(
          onPressed: () => _showForgotPasswordSheet(context),
          child: Text(l10n.authForgotPassword),
        ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: kPrimaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l10n.authLoginButton),
          ),
        ),
        const SizedBox(height: 18),
        _buildDivider(l10n.authSocialDivider, theme),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isGoogleSigningIn ? null : _handleGoogleLogin,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: const Color(0xFFDB4437),
              side: const BorderSide(color: Color(0xFFDB4437)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isGoogleSigningIn)
                  const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDB4437)))
                else
                  const Icon(Icons.g_mobiledata, size: 28),
                const SizedBox(width: 8),
                Text(_isGoogleSigningIn ? l10n.authGoogleSigningIn : l10n.authLoginWithGoogle),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => _switchMode(true),
            child: Text(l10n.authNoAccount, style: const TextStyle(color: kPrimaryGreen)),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.authRegisterTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold, color: kPrimaryDark)),
        const SizedBox(height: 24),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: l10n.authUsername,
            hintText: l10n.authUsernameHintReg,
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return l10n.validationEnterUsername;
            if (v.trim().length < 3) return l10n.validationUsernameTooShort;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l10n.authEmail,
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return l10n.validationEnterEmail;
            if (!v.contains('@')) return l10n.validationInvalidEmail;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _displayNameController,
          decoration: InputDecoration(
            labelText: l10n.authDisplayName,
            hintText: l10n.authDisplayNameHint,
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _isObscure,
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isObscure = !_isObscure),
              icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return l10n.validationEnterPassword;
            if (v.length < 6) return l10n.validationPasswordTooShort;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _isConfirmObscure,
          decoration: InputDecoration(
            labelText: l10n.authConfirmPassword,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isConfirmObscure = !_isConfirmObscure),
              icon: Icon(_isConfirmObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return l10n.validationEnterPasswordAgain;
            if (v != _passwordController.text) return l10n.validationPasswordMismatch;
            return null;
          },
        ),
        const SizedBox(height: 16),

        // ── 邀請碼（可選）────────────────────────────────────────
        Row(children: [
          const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('選填', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ),
          const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          decoration: InputDecoration(
            labelText: '邀請碼',
            hintText: '如有好友邀請碼，請在此填寫',
            prefixIcon: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFF6B35)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
            ),
            helperText: '填寫邀請碼，雙方各獲得 +5 球獎勵',
            helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: kPrimaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l10n.authRegisterButton),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => _switchMode(false),
            child: Text(l10n.authHaveAccount, style: const TextStyle(color: kPrimaryGreen)),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(String label, ThemeData theme) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF5F6368), fontWeight: FontWeight.w600)),
        ),
        const Expanded(child: Divider(color: Color(0xFFE0E0E0))),
      ],
    );
  }

  // ── Dev 小幫手 ────────────────────────────────────────────────

  void _onDevLogoTap() {
    if (!kDebugMode) return;
    _devTapTimer?.cancel();
    _devTapCount++;
    if (_devTapCount >= 5) {
      _devTapCount = 0;
      HapticFeedback.mediumImpact();
      _showDevAccountPicker();
      return;
    }
    _devTapTimer = Timer(const Duration(seconds: 2), () => _devTapCount = 0);
  }

  static const _devAccounts = [
    (label: 'Free 全新',       username: 'test_free',        plan: 'free',  note: '0/10'),
    (label: 'Free 配額滿',     username: 'test_free_full',   plan: 'free',  note: '10/10'),
    (label: 'Free 有 Ball',    username: 'test_free_balls',  plan: 'free',  note: '10/10 +15球'),
    (label: '廣告全用完',      username: 'test_ad_full',     plan: 'free',  note: '25球·廣告5/5'),
    (label: 'Pro 接近上限',    username: 'test_pro',         plan: 'pro',   note: '88/90'),
    (label: 'Elite',           username: 'test_elite',       plan: 'elite', note: '無限制'),
    (label: '停權帳號',        username: 'test_suspended',   plan: 'free',  note: 'suspended'),
    (label: 'AI Coach',        username: 'test_aicoach',     plan: 'pro',   note: 'AI分析測試'),
    (label: 'IAP 購買',        username: 'test_iap',         plan: 'free',  note: '購買流程測試'),
    (label: '邀請者',          username: 'test_inviter',     plan: 'free',  note: 'code=TESTINVITE0001'),
    (label: '被邀請者',        username: 'test_invitee',     plan: 'free',  note: '+5球'),
    (label: 'Token 測試',      username: 'test_token',       plan: 'free',  note: '一般帳號'),
  ];

  void _showDevAccountPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.developer_mode, color: Colors.deepOrange, size: 20),
                  const SizedBox(width: 8),
                  Text('測試帳號',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('密碼：Test1234!',
                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[600])),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _devAccounts.length,
                itemBuilder: (_, i) {
                  final acc = _devAccounts[i];
                  final planColor = switch (acc.plan) {
                    'elite' => const Color(0xFFFFD700),
                    'pro'   => Colors.blueAccent,
                    _       => Colors.grey,
                  };
                  return ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _identifierController.text = acc.username;
                        _passwordController.text   = 'Test1234!';
                        _isRegisterMode            = false;
                      });
                      HapticFeedback.selectionClick();
                    },
                    leading: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: planColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          acc.plan.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: planColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    title: Text(acc.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(acc.username,
                        style: const TextStyle(fontSize: 12)),
                    trailing: Text(acc.note,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        )),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionReminder(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final chips = _blePermissions.entries.map((entry) {
      final granted = _isGranted(_permissionStatuses[entry.key]);
      return Chip(
        avatar: Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? kPrimaryGreen : Colors.redAccent,
          size: 20,
        ),
        label: Text('${_permLabel(entry.key, l10n)}：${granted ? l10n.permGranted : l10n.permDenied}'),
        backgroundColor: granted ? Colors.white : Colors.white.withValues(alpha: 0.85),
      );
    }).toList();

    return Card(
      color: Colors.white.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.permTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: kPrimaryDark, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l10n.permSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: kPrimaryDark)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _requestBlePermissions(showDeniedDialog: true),
                icon: const Icon(Icons.security),
                label: Text(l10n.permCheckAgain),
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 忘記密碼底部彈出表單（2步驟：輸入Email → 輸入驗證碼+新密碼）
// ════════════════════════════════════════════════════════════════

class _ForgotPasswordSheet extends StatefulWidget {
  final void Function(String email)? onDone;

  const _ForgotPasswordSheet({this.onDone});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  // step 0: 輸入 Email；step 1: 輸入驗證碼 + 新密碼
  int _step = 0;
  bool _loading = false;

  final _emailCtrl   = TextEditingController();
  final _codeCtrl    = TextEditingController();
  final _newPwCtrl   = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMsg = '請輸入有效的 Email');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final res = await VideoServerClient.instance.forgotPassword(email);
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() => _step = 1);
      } else {
        setState(() => _errorMsg = res['message'] ?? '寄送失敗');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '網路錯誤，請稍後再試');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code  = _codeCtrl.text.trim();
    final newPw = _newPwCtrl.text;
    final conf  = _confirmCtrl.text;

    if (code.length != 6) {
      setState(() => _errorMsg = '請輸入 6 位數驗證碼');
      return;
    }
    if (newPw.length < 8 ||
        !newPw.contains(RegExp(r'[A-Z]')) ||
        !newPw.contains(RegExp(r'[a-z]')) ||
        !newPw.contains(RegExp(r'[0-9]'))) {
      setState(() => _errorMsg = '密碼須至少 8 位且包含大寫、小寫及數字');
      return;
    }
    if (newPw != conf) {
      setState(() => _errorMsg = '兩次密碼不一致');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final res = await VideoServerClient.instance.resetPassword(
        email:       _emailCtrl.text.trim(),
        code:        code,
        newPassword: newPw,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context);
        widget.onDone?.call(_emailCtrl.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('密碼已重設，請用新密碼登入'),
            backgroundColor: kPrimaryGreen,
          ),
        );
      } else {
        setState(() => _errorMsg = res['message'] ?? '重設失敗');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '網路錯誤，請稍後再試');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖把 handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 標題
            Row(children: [
              const Icon(Icons.lock_reset_rounded, color: kPrimaryGreen, size: 24),
              const SizedBox(width: 10),
              Text(
                _step == 0 ? '忘記密碼' : '輸入驗證碼',
                style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF123B70)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              _step == 0
                  ? '輸入您的 Email，我們將寄送 6 位數驗證碼'
                  : '驗證碼已寄至 ${_emailCtrl.text.trim()}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6F7B86)),
            ),
            const SizedBox(height: 20),

            // ── Step 0: Email ──
            if (_step == 0) ...[
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],

            // ── Step 1: 驗證碼 + 新密碼 ──
            if (_step == 1) ...[
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    letterSpacing: 10),
                decoration: InputDecoration(
                  labelText: '6 位驗證碼',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _newPwCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: '新密碼',
                  hintText: '至少 8 位，含大寫、小寫、數字',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: '確認新密碼',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],

            // 錯誤訊息
            if (_errorMsg != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_errorMsg!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ]),
            ],

            const SizedBox(height: 20),
            // 按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : (_step == 0 ? _requestCode : _resetPassword),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_step == 0 ? '寄送驗證碼' : '確認重設密碼',
                        style: const TextStyle(fontSize: 15)),
              ),
            ),
            if (_step == 1) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => setState(() {
                    _step = 0;
                    _codeCtrl.clear();
                    _newPwCtrl.clear();
                    _confirmCtrl.clear();
                    _errorMsg = null;
                  }),
                  child: const Text('重新輸入 Email',
                      style: TextStyle(color: Color(0xFF9AA6B2))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
