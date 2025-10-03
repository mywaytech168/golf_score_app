import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    // 組件銷毀時一併釋放控制器，避免記憶體洩漏
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------- 方法區 ----------
  /// 當使用者按下登入按鈕時觸發，先驗證資料再導向首頁
  void _handleLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      // 驗證成功後直接導向首頁並帶入鏡頭資訊
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            userEmail: _emailController.text,
            cameras: widget.cameras,
          ),
        ),
      );
    }
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
                              onPressed: _handleLogin,
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
}
