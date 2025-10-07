import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // 引入權限處理套件以於登入前檢查授權

import 'home_page.dart';

/// 登入頁面提供使用者輸入帳號密碼後進入首頁
class LoginPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 裝置可用鏡頭清單

  const LoginPage({super.key, required this.cameras});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ---------- 狀態管理區 ----------
  final TextEditingController _emailController = TextEditingController(); // 紀錄信箱輸入內容
  final TextEditingController _passwordController = TextEditingController(); // 紀錄密碼輸入內容
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // 表單驗證用 key
  bool _rememberMe = true; // 記住使用者選項
  bool _isObscure = true; // 控制密碼顯示與否
  bool _hasRequestedInitialPermissions = false; // 避免重複觸發首次權限請求
  Map<Permission, PermissionStatus> _permissionStatuses = {}; // 儲存各項權限授權狀態

  // 將需要的權限與顯示名稱整理成 map，方便統一管理與顯示
  final Map<Permission, String> _blePermissions = {
    Permission.bluetooth: '藍牙使用',
    Permission.bluetoothScan: '藍牙掃描',
    Permission.bluetoothConnect: '藍牙連線',
    Permission.locationWhenInUse: '定位',
  };

  @override
  void initState() {
    super.initState();
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
  /// 首次進入登入頁面時觸發權限請求，讓使用者立即看到系統彈窗
  Future<void> _triggerInitialPermissionRequest() async {
    if (_hasRequestedInitialPermissions) {
      return; // 已經處理過首次請求就不再重複執行
    }
    _hasRequestedInitialPermissions = true;

    await _requestBlePermissions(showDeniedDialog: false); // 首次請求不額外彈說明，僅顯示系統視窗

    // 若仍未全部授權則以 SnackBar 提醒並在畫面上顯示提示卡片
    if (mounted && !_arePermissionsAllGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請允許藍牙與定位權限，以確保 IMU 連線功能可用。'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// 當使用者按下登入按鈕時觸發，先驗證資料再導向首頁
  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return; // 若表單驗證失敗則直接結束
    }

    // 登入前先要求使用者授權藍牙與定位權限，確保後續流程正常運作
    final permissionsGranted = await _ensureBlePermissions();
    if (!mounted || !permissionsGranted) {
      return; // 權限未完整授權時暫停導向首頁
    }

    // 權限與驗證皆通過後才導向首頁並帶入鏡頭資訊
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          userEmail: _emailController.text,
          cameras: widget.cameras,
        ),
      ),
    );
  }

  /// 於首次登入時請求藍牙／定位權限，並在拒絕時顯示操作提示
  Future<bool> _ensureBlePermissions() async {
    return _requestBlePermissions(showDeniedDialog: true);
  }

  /// 統一處理藍牙／定位權限請求並更新狀態，可選擇是否於拒絕時顯示說明
  Future<bool> _requestBlePermissions({required bool showDeniedDialog}) async {
    final updatedStatuses = <Permission, PermissionStatus>{};

    for (final entry in _blePermissions.entries) {
      final status = await entry.key.request();
      updatedStatuses[entry.key] = status;
    }

    if (!mounted) {
      return false; // 組件已卸載就不再進行後續流程
    }

    setState(() {
      _permissionStatuses = updatedStatuses;
    });

    if (_arePermissionsAllGranted) {
      return true; // 全數授權完成即可繼續
    }

    if (showDeniedDialog) {
      await _showPermissionGuideDialog();
    }

    return false;
  }

  /// 顯示權限說明視窗，指引用戶到正確的位置開啟藍牙／附近裝置／定位權限
  Future<void> _showPermissionGuideDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('需要藍牙與定位權限'),
          content: const Text(
            '為了搜尋並連線 IMU 感測裝置，請在系統設定中允許以下權限：\n'
            '1. 進入「應用程式與通知」或「應用管理」。\n'
            '2. 選擇 TekSwing 後開啟「權限」。\n'
            '3. 啟用「附近裝置 / 藍牙」與「定位」權限。\n\n'
            '若系統未直接顯示藍牙選項，請在權限頁面中尋找「附近裝置」或「位置」並開啟。',
          ),
          actions: [
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
        );
      },
    );
  }

  /// 判斷所有需要的權限是否都已授權
  bool get _arePermissionsAllGranted {
    if (_permissionStatuses.isEmpty) {
      return false; // 尚未檢查過視為未授權
    }
    return _permissionStatuses.values.every((status) => status.isGranted);
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
                                onChanged: (value) => setState(() => _rememberMe = value ?? false),
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
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _handleLogin(), // 透過匿名函式呼叫非同步登入流程
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: const Color(0xFF1E8E5A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text('登入 TekSwing'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Color(0xFF1E8E5A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text('以訪客身分瀏覽'),
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
      final granted = status?.isGranted ?? false;
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
