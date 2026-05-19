import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/video_server_client.dart';
import '../services/auth_token_storage.dart';
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

  final _formKey = GlobalKey<FormState>();

  bool _rememberMe = false;
  bool _isObscure = true;
  bool _isConfirmObscure = true;
  bool _isLoading = false;
  bool _isGoogleSigningIn = false;
  bool _hasRequestedInitialPermissions = false;

  late final Map<Permission, String> _blePermissions;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  @override
  void initState() {
    super.initState();
    _blePermissions = _buildRequiredPermissions();
    _permissionStatuses = {
      for (final p in _blePermissions.keys) p: PermissionStatus.denied,
    };
    _loadRememberedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerInitialPermissionRequest();
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _confirmPasswordController.dispose();
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

        // 儲存顯示資訊（user 在根層級）
        final prefs = await SharedPreferences.getInstance();
        final user = response['user'];
        if (user is Map) {
          if (user['email'] != null) await prefs.setString('user_email', user['email'].toString());
          if (user['displayName'] != null) await prefs.setString('user_name', user['displayName'].toString());
        }

        _showSnackBar('登入成功，歡迎回來！');
        if (Platform.isIOS) { await _navigateToHome(); return; }
        final ok = await _ensureBlePermissions();
        if (!mounted || !ok) return;
        await _navigateToHome();
      } else {
        _showSnackBar(response['message'] ?? '登入失敗，請檢查帳號密碼', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('登入失敗：$e', isError: true);
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
      );

      if (!mounted) return;

      if (response['success'] == true) {
        _showSnackBar('註冊成功，請登入');
        // 帶入 username 到登入頁
        _identifierController.text = _usernameController.text.trim();
        _passwordController.clear();
        _switchMode(false);
      } else {
        _showSnackBar(response['message'] ?? '註冊失敗', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('註冊失敗：$e', isError: true);
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
        clientId: '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _showSnackBar('已取消 Google 登入流程');
        return;
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        _showSnackBar('無法取得 Google IdToken', isError: true);
        return;
      }

      final dio = Dio();
      final response = await dio.post(
        'https://tekswing.api.atk.tw/api/auth/google-login',
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
        _showSnackBar('Google 登入失敗：後端未返回認證令牌', isError: true);
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
        _showSnackBar('Google 登入成功，歡迎回來！');
        await _navigateToHome();
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? '請稍後再試';
      _showSnackBar('Google 登入失敗：$msg', isError: true);
    } on PlatformException catch (error) {
      _showSnackBar('Google 登入失敗：${error.message ?? '請稍後再試'}', isError: true);
    } catch (e) {
      _showSnackBar('Google 登入失敗：$e', isError: true);
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
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF1E8E5A),
      ),
    );
  }

  // ── 權限 ────────────────────────────────────────────────────

  Future<void> _triggerInitialPermissionRequest() async {
    if (_hasRequestedInitialPermissions) return;
    _hasRequestedInitialPermissions = true;
    if (Platform.isIOS) return;

    await _requestBlePermissions(showDeniedDialog: false);
    if (mounted && !_arePermissionsAllGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('請允許藍牙權限。'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: '查看狀態', onPressed: _showPermissionStatusDialog),
        ),
      );
    }
  }

  void _showPermissionStatusDialog() {
    final statusText = _permissionStatuses.entries
        .map((e) => '${_blePermissions[e.key]}: ${e.value}')
        .join('\n');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('權限狀態'),
        content: Text(statusText.isEmpty ? '尚未檢查權限' : statusText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await openAppSettings(); },
            child: const Text('開啟設定'),
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
    final instructions = Platform.isIOS
        ? '需要定位權限才能使用藍牙掃描功能：\n\n'
            '1. 點擊「開啟設定」\n2. 找到「Golf Score App」\n'
            '3. 點選「位置」→「使用 App 期間」\n'
            '4. 返回 App 重新登入'
        : '請在系統設定中允許以下權限：\n'
            '1. 進入「應用程式與通知」\n2. 選擇 TekSwing → 權限\n'
            '3. 啟用「附近裝置、藍牙」與「定位」';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('需要開啟權限'),
        ]),
        content: SingleChildScrollView(
          child: Text(instructions, style: const TextStyle(fontSize: 15)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await openAppSettings(); },
            child: const Text('前往設定'),
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

  Map<Permission, String> _buildRequiredPermissions() => {
    Permission.locationWhenInUse: '定位',
  };

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E8E5A), Color(0xFF0A3D2E)],
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
                // 品牌標誌
                Row(
                  children: [
                    const Icon(Icons.golf_course_rounded, size: 42, color: Colors.white),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TekSwing',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('智慧揮桿訓練平台',
                            style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(
                  _isRegisterMode ? '建立帳號' : '歡迎回來！',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegisterMode
                      ? '填寫以下資料即可開始使用 TekSwing。'
                      : '請登入 TekSwing 以同步揮桿資料並探索最新分析報告。',
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
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.security, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text('所有資料皆採用 256-bit 加密保護',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 登入表單 ─────────────────────────────────────────────────

  Widget _buildLoginForm(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('登入帳號',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold, color: const Color(0xFF0A3D2E))),
        const SizedBox(height: 24),
        TextFormField(
          controller: _identifierController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '用戶名 / 電子郵件',
            hintText: 'username 或 you@example.com',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '請輸入用戶名或電子郵件';
            return null;
          },
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _passwordController,
          obscureText: _isObscure,
          decoration: InputDecoration(
            labelText: '密碼',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isObscure = !_isObscure),
              icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return '請輸入密碼';
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
            const Text('記住我'),
            const Spacer(),
            TextButton(onPressed: () {}, child: const Text('忘記密碼？')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF1E8E5A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('登入 TekSwing'),
          ),
        ),
        const SizedBox(height: 18),
        _buildDivider('或使用社群帳號快速登入', theme),
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
                Text(_isGoogleSigningIn ? 'Google 登入中...' : '使用 Google 登入'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => _switchMode(true),
            child: const Text('還沒有帳戶？立即註冊',
                style: TextStyle(color: Color(0xFF1E8E5A))),
          ),
        ),
      ],
    );
  }

  // ── 註冊表單 ─────────────────────────────────────────────────

  Widget _buildRegisterForm(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('建立帳號',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold, color: const Color(0xFF0A3D2E))),
        const SizedBox(height: 24),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: '用戶名',
            hintText: '用於登入，不可重複',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '請輸入用戶名';
            if (v.trim().length < 3) return '用戶名至少 3 個字元';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '電子郵件',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '請輸入電子郵件';
            if (!v.contains('@')) return '電子郵件格式不正確';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _displayNameController,
          decoration: InputDecoration(
            labelText: '顯示名稱（可選）',
            hintText: '留空則與用戶名相同',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _isObscure,
          decoration: InputDecoration(
            labelText: '密碼（至少 6 碼）',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isObscure = !_isObscure),
              icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return '請輸入密碼';
            if (v.length < 6) return '密碼至少需要 6 碼';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _isConfirmObscure,
          decoration: InputDecoration(
            labelText: '確認密碼',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isConfirmObscure = !_isConfirmObscure),
              icon: Icon(_isConfirmObscure ? Icons.visibility : Icons.visibility_off),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return '請再次輸入密碼';
            if (v != _passwordController.text) return '兩次密碼不一致';
            return null;
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF1E8E5A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('建立帳號'),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => _switchMode(false),
            child: const Text('已有帳戶？返回登入',
                style: TextStyle(color: Color(0xFF1E8E5A))),
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

  // ── 權限提示卡片 ─────────────────────────────────────────────

  Widget _buildPermissionReminder(ThemeData theme) {
    final chips = _blePermissions.entries.map((entry) {
      final granted = _isGranted(_permissionStatuses[entry.key]);
      return Chip(
        avatar: Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? const Color(0xFF1E8E5A) : Colors.redAccent,
          size: 20,
        ),
        label: Text('${entry.value}${granted ? '：已允許' : '：尚未允許'}'),
        backgroundColor: granted ? Colors.white : Colors.white.withValues(alpha:0.85),
      );
    }).toList();

    return Card(
      color: Colors.white.withValues(alpha:0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('請先授權藍牙與定位',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF0A3D2E), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('首次登入時需要取得藍牙權限。',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF0A3D2E))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _requestBlePermissions(showDeniedDialog: true),
                icon: const Icon(Icons.security),
                label: const Text('重新檢查權限'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E8E5A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
