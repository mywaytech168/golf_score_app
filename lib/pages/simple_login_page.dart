import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/video_server_client.dart';

/// 簡化版登入頁面 - 支持本地帳號和 Google OAuth
class SimpleLoginPage extends StatefulWidget {
  const SimpleLoginPage({super.key});

  @override
  State<SimpleLoginPage> createState() => _SimpleLoginPageState();
}

class _SimpleLoginPageState extends State<SimpleLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  
  final _googleSignIn = GoogleSignIn();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // true: login, false: register
  String _errorMessage = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // ============================================================
  // 本地帳號登入
  // ============================================================
  Future<void> _loginLocal() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = '請輸入用戶名和密碼';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await VideoServerClient().loginLocal(
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (response['success']) {
        // 保存 Token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', response['token']);
        await prefs.setString('user_id', response['user']['id'].toString());
        await prefs.setString('user_name', response['user']['displayName'] ?? response['user']['username']);

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? '登入失敗';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '登入錯誤: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // 本地帳號註冊
  // ============================================================
  Future<void> _registerLocal() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty || _emailController.text.isEmpty) {
      setState(() {
        _errorMessage = '請填入所有必填欄位';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await VideoServerClient().registerLocal(
        username: _usernameController.text,
        password: _passwordController.text,
        displayName: _displayNameController.text.isEmpty ? _usernameController.text : _displayNameController.text,
        email: _emailController.text,
      );

      if (response['success']) {
        _usernameController.clear();
        _passwordController.clear();
        _emailController.clear();
        _displayNameController.clear();
        
        setState(() {
          _isLoginMode = true;
          _errorMessage = '註冊成功，請登入';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('註冊成功，請登入')),
        );
      } else {
        setState(() {
          _errorMessage = response['message'] ?? '註冊失敗';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '註冊錯誤: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // Google OAuth 登入
  // ============================================================
  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 先登出以強制顯示帳戶選擇器
      await _googleSignIn.signOut();

      // 觸發 Google 登入流程
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '已取消 Google 登入';
        });
        return;
      }

      // 獲取使用者驗證資訊
      final googleAuth = await googleUser.authentication;

      // 驗證 IdToken
      if (googleAuth.idToken == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '無法取得 Google IdToken';
        });
        return;
      }

      // 發送到後端進行驗證
      final response = await VideoServerClient().loginWithGoogle(
        idToken: googleAuth.idToken!,
        email: googleUser.email,
        displayName: googleUser.displayName,
        avatarUrl: googleUser.photoUrl,
      );

      if (response['success'] == true || response.containsKey('token')) {
        final prefs = await SharedPreferences.getInstance();
        
        if (response['token'] != null) {
          await prefs.setString('auth_token', response['token']);
        }
        
        final user = response['user'];
        if (user is Map) {
          if (user['id'] != null) {
            await prefs.setString('user_id', user['id'].toString());
          }
          if (user['displayName'] != null) {
            await prefs.setString('user_name', user['displayName']);
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Google 登入失敗';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Google 登入錯誤: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoginMode ? '登入' : '註冊'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 40),
              const Text(
                'Golf Score App',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 40),

              // 登入模式表單
              if (_isLoginMode) ...[
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '用戶名',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '密碼',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
              ],
              
              // 註冊模式表單
              if (!_isLoginMode) ...[
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '用戶名',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: '電子郵件',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _displayNameController,
                  decoration: InputDecoration(
                    labelText: '顯示名稱（可選）',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '密碼（至少 6 個字符）',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  enabled: !_isLoading,
                ),
              ],

              SizedBox(height: 8),

              // 錯誤訊息
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              SizedBox(height: 24),

              // 主操作按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_isLoginMode ? _loginLocal : _registerLocal),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.blue,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _isLoginMode ? '登入' : '建立帳號',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              SizedBox(height: 16),

              // 切換登入/註冊模式
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _isLoginMode = !_isLoginMode;
                          _errorMessage = '';
                          _usernameController.clear();
                          _passwordController.clear();
                          _emailController.clear();
                          _displayNameController.clear();
                        });
                      },
                child: Text(
                  _isLoginMode ? '還沒有帳戶？立即註冊' : '已有帳戶？返回登入',
                ),
              ),

              SizedBox(height: 32),

              // 分隔線
              Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('或使用'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),

              SizedBox(height: 24),

              // Google 登入按鈕
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  icon: const Icon(Icons.account_circle),
                  label: const Text('使用 Google 帳號登入'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.grey),
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
