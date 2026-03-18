import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io'; // 判斷平台以動態決定權限清單

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 捕捉平台層級錯誤以便顯示友善訊息
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_sign_in/google_sign_in.dart'; // 引入 Google 登入套件以支援第三方登入
import 'package:http/http.dart' as http; // 引入 HTTP 套件以支援 API 呼叫
import 'package:permission_handler/permission_handler.dart'; // 引入權限處理套件以於登入前檢查授權
import 'package:shared_preferences/shared_preferences.dart'; // 引入本地儲存套件以保存「記住我」資料

import '../services/video_server_client.dart';
import 'home_page.dart';

/// 登入頁面提供使用者輸入帳號密碼後進入首頁
class LoginPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 裝置可用鏡頭清單

  const LoginPage({super.key, required this.cameras});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _rememberMeKey = 'login.remember_me'; // 記錄是否勾選記住我
  static const String _rememberedEmailKey = 'login.remembered_email'; // 記錄記住我的電子郵件
  static const String _rememberedPasswordKey = 'login.remembered_password'; // 記錄記住我的密碼
  // ---------- 狀態管理區 ----------
  final TextEditingController _emailController = TextEditingController(); // 紀錄信箱輸入內容
  final TextEditingController _passwordController = TextEditingController(); // 紀錄密碼輸入內容
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // 表單驗證用 key
  bool _rememberMe = false; // 記住使用者選項，預設為關閉避免未授權情況儲存資料
  bool _isObscure = true; // 控制密碼顯示與否
  bool _hasRequestedInitialPermissions = false; // 避免重複觸發首次權限請求
  late final Map<Permission, String> _blePermissions; // 依照平台動態產生的權限顯示名稱
  Map<Permission, PermissionStatus> _permissionStatuses = {}; // 儲存各項權限授權狀態
  bool _isGoogleSigningIn = false; // 控制 Google 登入的載入狀態以避免重複觸發
  bool _isGuestSigningIn = false; // 控制訪客登入的載入狀態以避免重複觸發
  bool _isLoading = false; // 控制登入按鈕的載入狀態以避免重複觸發

  @override
  void initState() {
    super.initState();
    _blePermissions = _buildRequiredPermissions(); // 依平台建立權限清單，避免出現無法授權的項目
    _permissionStatuses = {
      for (final permission in _blePermissions.keys)
        permission: PermissionStatus.denied, // 初始化為未授權，確保提示卡片顯示狀態
    };
    _loadRememberedCredentials(); // 讀取記住我設定，若有資料則自動填入帳號密碼
    _checkBluetoothState(); // 檢查藍牙狀態
    // 於元件建立後立即排程權限請求，確保第一次進入登入頁面就彈出系統授權視窗
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerInitialPermissionRequest();
    });
  }

  @override
  void dispose() {
    // 組件銷毀時一併釋放控制器，避免記憶體洩漏
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------- 方法區 ----------
  /// 檢查藍牙狀態並更新 UI (僅 Android，iOS 會在掃描時自動處理)
  Future<void> _checkBluetoothState() async {
    try {
      // iOS 不支持直接查詢藍牙狀態，只在 Android 上檢查
      if (Platform.isAndroid) {
        final state = await FlutterBluePlus.adapterState.first;
        
        // 如果藍牙關閉，顯示提示
        if (mounted && state == BluetoothAdapterState.off) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('請開啟藍牙以使用 IMU 連線功能'),
              action: SnackBarAction(
                label: '瞭解',
                onPressed: () {},
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      // iOS 上不需要檢查，因為在實際使用藍牙時系統會自動處理
    } catch (e) {
      debugPrint('檢查藍牙狀態失敗: $e');
    }
  }

  /// 首次進入登入頁面時觸發權限請求，讓使用者立即看到系統彈窗
  Future<void> _triggerInitialPermissionRequest() async {
    if (_hasRequestedInitialPermissions) {
      return; // 已經處理過首次請求就不再重複執行
    }
    _hasRequestedInitialPermissions = true;

    // iOS：不在登入時請求權限，讓 flutter_blue_plus 在實際使用時自動請求
    if (Platform.isIOS) {
      debugPrint('📱 iOS 平台：跳過預先權限請求，將在使用藍牙時自動請求');
      return;
    }

    debugPrint('📱 開始初始權限請求流程');
    await _requestBlePermissions(showDeniedDialog: false); // 首次請求不額外彈說明，僅顯示系統視窗

    // 若仍未全部授權則以 SnackBar 提醒並在畫面上顯示提示卡片
    if (mounted && !_arePermissionsAllGranted) {
      debugPrint('⚠️ 權限未完全授予，顯示提示訊息');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('請允許藍牙與定位權限，以確保 IMU 連線功能可用。'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '查看狀態',
            onPressed: () => _showPermissionStatusDialog(),
          ),
        ),
      );
    } else {
      debugPrint('✅ 所有權限已在初始請求中授予');
    }
  }

  /// 顯示當前權限狀態的對話框（用於調試）
  void _showPermissionStatusDialog() {
    final statusText = _permissionStatuses.entries
        .map((e) => '${_blePermissions[e.key]}: ${e.value}')
        .join('\n');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('權限狀態'),
        content: Text(statusText.isEmpty ? '尚未檢查權限' : statusText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('開啟設定'),
          ),
        ],
      ),
    );
  }

  /// 當使用者按下登入按鈕時觸發，先驗證資料再導向首頁
  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

<<<<<<< HEAD
    // iOS 不需要預先檢查權限，flutter_blue_plus 會在掃描時自動處理
    if (Platform.isIOS) {
      await _persistRememberedCredentials();
      await _navigateToHome(_emailController.text);
      return;
    }

    // Android 登入前先要求使用者授權藍牙與定位權限，確保後續流程正常運作
    final permissionsGranted = await _ensureBlePermissions();
    if (!mounted || !permissionsGranted) {
      return; // 權限未完整授權時暫停導向首頁
=======
    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('https://tekswing.api.atk.tw/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _emailController.text,
              'password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        // 保存 JWT token 和用戶信息
        final prefs = await SharedPreferences.getInstance();
        
        if (responseData is Map && responseData.containsKey('token')) {
          await prefs.setString('jwt_token', responseData['token']);
        }
        
        if (responseData is Map && responseData.containsKey('refreshToken')) {
          await prefs.setString('refresh_token', responseData['refreshToken']);
        }
        
        if (responseData is Map && responseData['user'] is Map) {
          final user = responseData['user'];
          if (user['id'] != null) {
            await prefs.setString('user_id', user['id'].toString());
          }
          if (user['email'] != null) {
            await prefs.setString('user_email', user['email']);
          }
          if (user['displayName'] != null) {
            await prefs.setString('user_name', user['displayName']);
          }
        }
        
        await _persistRememberedCredentials();
        if (mounted) {
          _showLoginResultSnackBar('登入成功！');
          // 導向首頁
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else if (response.statusCode == 401) {
        _showLoginResultSnackBar('登入失敗：電子郵件或密碼錯誤', isError: true);
      } else {
        _showLoginResultSnackBar('登入失敗：${response.body}', isError: true);
      }
    } on TimeoutException {
      _showLoginResultSnackBar('伺服器回應逾時，請稍後再試', isError: true);
    } catch (e) {
      _showLoginResultSnackBar('無法連接伺服器：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
>>>>>>> 00fbbe244e2f3778851c4634334111c8e914a987
    }
  }

  /// 載入記住我狀態與帳號密碼，協助使用者快速登入
  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRememberMe = prefs.getBool(_rememberMeKey) ?? false;
    final savedEmail = savedRememberMe ? prefs.getString(_rememberedEmailKey) ?? '' : '';
    final savedPassword = savedRememberMe ? prefs.getString(_rememberedPasswordKey) ?? '' : '';

    if (!mounted) {
      return; // 若頁面已卸載就不更新狀態
    }

    setState(() {
      _rememberMe = savedRememberMe;
      if (savedRememberMe) {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
      }
    });
  }

  /// 根據目前記住我選擇結果保存或清除本地帳號資訊
  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();

    if (_rememberMe) {
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberedEmailKey, _emailController.text);
      await prefs.setString(_rememberedPasswordKey, _passwordController.text);
      return;
    }

    await prefs.setBool(_rememberMeKey, false);
    await prefs.remove(_rememberedEmailKey);
    await prefs.remove(_rememberedPasswordKey);
  }

  /// 以 Google 登入，整合第三方帳戶
  Future<void> _handleGoogleLogin() async {
    if (_isGoogleSigningIn) {
      return; // 若已有請求進行中則略過避免重複觸發
    }

    setState(() {
      _isGoogleSigningIn = true;
    });

    try {
      // 先登出以強制顯示帳戶選擇器
      final googleSignIn = GoogleSignIn(
        clientId: '446697241300-2bba3v5gkc2679drmgeek0k6u20n5fks.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
      
      await googleSignIn.signOut();

      // 觸發 Google 登入流程
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _showLoginResultSnackBar('已取消 Google 登入流程');
        return;
      }

      // 獲取使用者詳細資訊
      final googleAuth = await googleUser.authentication;

      // 驗證 IdToken
      if (googleAuth.idToken == null) {
        _showLoginResultSnackBar('無法取得 Google IdToken', isError: true);
        return;
      }

      // 發送到後端進行驗證
      debugPrint('📤 發送到後端進行驗證...');
      final response = await VideoServerClient().loginWithGoogle(
        idToken: googleAuth.idToken!,
        email: googleUser.email,
        displayName: googleUser.displayName,
        avatarUrl: googleUser.photoUrl,
      );

      debugPrint('📥 後端回應: $response');

      if (response['success'] == true || response.containsKey('token')) {
        // 保存 JWT token 和用戶信息
        final prefs = await SharedPreferences.getInstance();

        if (response['token'] != null) {
          await prefs.setString('jwt_token', response['token']);
        }

        if (response['refreshToken'] != null) {
          await prefs.setString('refresh_token', response['refreshToken']);
        }

        final user = response['user'];
        if (user is Map) {
          if (user['id'] != null) {
            await prefs.setString('user_id', user['id'].toString());
          }
          if (user['email'] != null) {
            await prefs.setString('user_email', user['email']);
          }
          if (user['displayName'] != null) {
            await prefs.setString('user_name', user['displayName']);
          }
        }

        if (mounted) {
          _showLoginResultSnackBar('Google 登入成功，歡迎回來！');
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        final errorMsg = response['message'] ?? 'Google 登入失敗';
        _showLoginResultSnackBar(errorMsg, isError: true);
      }
    } on PlatformException catch (error) {
      debugPrint('❌ Google 登入失敗: ${error.code} - ${error.message}');
      _showLoginResultSnackBar(
        'Google 登入失敗：${error.message ?? '請稍後再試'}',
        isError: true,
      );
    } catch (e) {
      debugPrint('❌ Google 登入異常: $e');
      _showLoginResultSnackBar('Google 登入失敗：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
  }

  /// 以訪客身分進入 TekSwing，跳過帳號驗證但仍需檢查裝置權限
  Future<void> _handleGuestLogin() async {
    if (_isGuestSigningIn) {
      return; // 若已有請求進行中則略過避免重複觸發
    }

    setState(() {
      _isGuestSigningIn = true;
    });

    try {
      final permissionsGranted = await _ensureBlePermissions(); // 訪客模式仍需藍牙權限以使用 IMU 連線功能
      if (!mounted || !permissionsGranted) {
        return;
      }

      // 將訪客標識保存到本地儲存，供後續頁面判斷是否為訪客模式
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest', true);
      await prefs.remove('member_id'); // 訪客模式不需要保存會員 ID

      await _navigateToHome('guest@local');
      _showLoginResultSnackBar('以訪客身分進入，歡迎使用 TekSwing！');
    } catch (_) {
      _showLoginResultSnackBar('訪客登入失敗，請稍後再試。', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isGuestSigningIn = false;
        });
      }
    }
  }

  /// 顯示登入結果的提示訊息，讓使用者瞭解目前狀態
  void _showLoginResultSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return; // 當前頁面已卸載就不顯示提示
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF1E8E5A),
      ),
    );
  }

  /// 共用的導向首頁流程，集中管理導航邏輯
    /// ?????????? email
  Future<void> _navigateToHome(String email) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          cameras: widget.cameras,
        ),
      ),
    );
  }

Future<void> _onRememberMeChanged(bool value) async {
    setState(() {
      _rememberMe = value;
    });

    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_rememberMeKey, true);
      return;
    }

    await prefs.setBool(_rememberMeKey, false);
    await prefs.remove(_rememberedEmailKey);
    await prefs.remove(_rememberedPasswordKey);
  }

  /// 於首次登入時請求藍牙／定位權限，並在拒絕時顯示操作提示
  Future<bool> _ensureBlePermissions() async {
    return _requestBlePermissions(showDeniedDialog: true);
  }

  /// 統一處理藍牙／定位權限請求並更新狀態，可選擇是否於拒絕時顯示說明
  Future<bool> _requestBlePermissions({required bool showDeniedDialog}) async {
    final updatedStatuses = <Permission, PermissionStatus>{};

    debugPrint('===== 開始請求權限 (iOS) =====');
    debugPrint('需要請求的權限：${_blePermissions.keys.map((p) => p.toString()).join(", ")}');

    for (final entry in _blePermissions.entries) {
      final permission = entry.key;
      final label = entry.value;
      
      // 先檢查當前狀態
      final currentStatus = await permission.status;
      debugPrint('權限 $label 當前狀態: $currentStatus');
      
      // 使用 request() 以觸發系統授權視窗，並紀錄回傳結果
      final status = await permission.request();
      debugPrint('權限 $label 請求後狀態: $status');
      
      updatedStatuses[permission] = status;
    }

    debugPrint('所有權限請求完成');
    debugPrint('權限狀態: ${updatedStatuses.map((k, v) => MapEntry(_blePermissions[k], v.toString()))}');

    if (!mounted) {
      return false; // 組件已卸載就不再進行後續流程
    }

    setState(() {
      _permissionStatuses = updatedStatuses;
    });

    if (_arePermissionsAllGranted) {
      debugPrint('✅ 所有權限已授予');
      return true; // 全數授權完成即可繼續
    }

    debugPrint('❌ 部分權限未授予');
    if (showDeniedDialog) {
      await _showPermissionGuideDialog();
    }

    return false;
  }

  /// 顯示權限說明視窗，指引用戶到正確的位置開啟藍牙／附近裝置／定位權限
  Future<void> _showPermissionGuideDialog() async {
    final String instructions = Platform.isIOS
        ? '需要定位權限才能使用藍牙掃描功能：\n\n'
            '📱 請按照以下步驟操作：\n\n'
            '1. 點擊下方「開啟設定」按鈕\n'
            '2. 找到「Golf Score App」\n'
            '3. 點選「位置」→ 選擇「使用 App 期間」\n'
            '4. 確認 iPhone 的藍牙已在「控制中心」開啟\n'
            '5. 返回 App 重新登入\n\n'
            '💡 提示：iOS 需要定位權限來掃描藍牙設備，\n這是系統要求，不會追蹤你的位置。'
        : '為了搜尋並連線 IMU 感測裝置，請在系統設定中允許以下權限：\n'
            '1. 進入「應用程式與通知」或「應用管理」。\n'
            '2. 選擇 TekSwing 後開啟「權限」。\n'
            '3. 啟用「附近裝置 / 藍牙」與「定位」權限。\n\n'
            '若系統未直接顯示藍牙選項，請在權限頁面中尋找「附近裝置」或「位置」並開啟。';
    
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // 必須點按鈕才能關閉
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('需要開啟權限'),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(instructions, style: const TextStyle(fontSize: 15)),
          ),
          actions: [
            if (Platform.isIOS) ...[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍後再說'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await openAppSettings(); // 開啟系統的應用程式設定頁面
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                icon: const Icon(Icons.settings),
                label: const Text('開啟設定'),
              ),
            ] else ...[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
              TextButton(
                onPressed: () async {
                  await openAppSettings(); // 開啟系統的應用程式設定頁面
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('前往設定'),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 判斷所有需要的權限是否都已授權
  bool get _arePermissionsAllGranted {
    if (_blePermissions.isEmpty) {
      return true; // 當前平台不需額外權限時直接視為通過
    }

    if (_permissionStatuses.length < _blePermissions.length) {
      return false; // 尚未檢查過視為未授權
    }
    return _permissionStatuses.values.every(_isStatusEffectivelyGranted);
  }

  /// 判斷權限狀態是否等同於已授權（含 iOS limited / provisional）
  bool _isStatusEffectivelyGranted(PermissionStatus? status) {
    if (status == null) {
      return false;
    }
    if (status.isGranted) {
      return true;
    }
    return status == PermissionStatus.limited || status == PermissionStatus.provisional;
  }

  /// 依照平台與系統版本決定需要請求的權限項目
  Map<Permission, String> _buildRequiredPermissions() {
    // Android 需請求附近裝置（掃描 / 連線）與定位權限；iOS 則需藍牙與定位
    if (Platform.isAndroid) {
      return {
        Permission.bluetoothScan: '藍牙掃描',
        Permission.bluetoothConnect: '藍牙連線',
        Permission.locationWhenInUse: '定位',
      };
    }

    if (Platform.isIOS) {
      // iOS 只需要定位權限，藍牙會在使用 flutter_blue_plus 時自動處理
      return {
        Permission.locationWhenInUse: '定位',
      };
    }

    // 其他平台僅保留定位權限，避免出現無法處理的藍牙授權項目
    return {
      Permission.locationWhenInUse: '定位',
    };
  }

  // ---------- UI 建構區 ----------
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
                // 品牌標誌區塊，呼應設計稿上方 TekSwing 標示
                Row(
                  children: [
                    const Icon(Icons.golf_course_rounded, size: 42, color: Colors.white),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TekSwing',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '智慧揮桿訓練平台',
                          style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(
                  '歡迎回來！',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '請登入 TekSwing 以同步揮桿資料並探索最新分析報告。',
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                if (!_arePermissionsAllGranted) _buildPermissionReminder(theme),
                const SizedBox(height: 32),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 16,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '登入帳號',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0A3D2E),
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: '電子郵件',
                              hintText: 'you@example.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            validator: (value) {
                              // 確認使用者是否輸入內容與基本格式
                              if (value == null || value.isEmpty) {
                                return '請輸入電子郵件';
                              }
                              if (!value.contains('@')) {
                                return '電子郵件格式不正確';
                              }
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '請輸入密碼';
                              }
                              if (value.length < 6) {
                                return '密碼至少需要 6 碼';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  final shouldRemember = value ?? false;
                                  _onRememberMeChanged(shouldRemember); // 同步記住我設定並處理本地儲存
                                },
                              ),
                              const Text('記住我'),
                              const Spacer(),
                              TextButton(
                                onPressed: () {},
                                child: const Text('忘記密碼？'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          /// 更新登入按鈕以顯示載入指示器
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : () => _handleLogin(), // 禁用按鈕於載入中
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: const Color(0xFF1E8E5A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('登入 TekSwing'),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(
                                child: Divider(color: Color(0xFFE0E0E0)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  '或使用社群帳號快速登入',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: const Color(0xFF5F6368),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(color: Color(0xFFE0E0E0)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // 僅保留 Google 登入按鈕，避免受未支援的 Apple 登入流程影響
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isGoogleSigningIn ? null : _handleGoogleLogin,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                foregroundColor: const Color(0xFFDB4437),
                                side: const BorderSide(color: Color(0xFFDB4437)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isGoogleSigningIn)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFDB4437),
                                      ),
                                    )
                                  else
                                    const Icon(Icons.g_mobiledata, size: 28),
                                  const SizedBox(width: 8),
                                  Text(_isGoogleSigningIn ? 'Google 登入中...' : '使用 Google 登入'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isGuestSigningIn ? null : _handleGuestLogin,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Color(0xFF1E8E5A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isGuestSigningIn)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF1E8E5A),
                                      ),
                                    )
                                  else
                                    const Icon(Icons.visibility, size: 24),
                                  const SizedBox(width: 8),
                                  Text(_isGuestSigningIn ? '訪客登入中...' : '以訪客身分瀏覽'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.security, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '所有資料皆採用 256-bit 加密保護',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 建立權限提示卡片，列出尚未授權的項目與重新請求按鈕
  Widget _buildPermissionReminder(ThemeData theme) {
    final chips = _blePermissions.entries.map((entry) {
      final status = _permissionStatuses[entry.key];
      final granted = _isStatusEffectivelyGranted(status);
      return Chip(
        avatar: Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? const Color(0xFF1E8E5A) : Colors.redAccent,
          size: 20,
        ),
        label: Text('${entry.value}${granted ? '：已允許' : '：尚未允許'}'),
        backgroundColor: granted ? Colors.white : Colors.white.withOpacity(0.85),
      );
    }).toList();

    return Card(
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '請先授權藍牙與定位',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0A3D2E),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '首次登入時需要取得藍牙、附近裝置與定位權限，才能搜尋 IMU 感測器並同步資料。',
              style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF0A3D2E)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _requestBlePermissions(showDeniedDialog: true),
                icon: const Icon(Icons.security),
                label: const Text('重新檢查權限'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E5A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
