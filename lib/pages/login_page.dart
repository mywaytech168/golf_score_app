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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 使用柔和底色讓畫面更乾淨
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.sports_golf, size: 72, color: Color(0xFF1E88E5)),
              const SizedBox(height: 16),
              Text(
                '高球紀錄系統',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E88E5),
                    ),
              ),
              const SizedBox(height: 32),
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: '電子郵件',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
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
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _isObscure,
                          decoration: InputDecoration(
                            labelText: '密碼',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _isObscure = !_isObscure),
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
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleLogin,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: const Color(0xFF1E88E5),
                            ),
                            child: const Text('登入'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
