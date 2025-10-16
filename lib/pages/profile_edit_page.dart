import 'package:flutter/material.dart';

/// 個人資訊編輯結果模型，用於回傳最新填寫內容
class ProfileEditResult {
  final String displayName; // 暱稱顯示名稱
  final String email; // 電子郵件
  final String phone; // 聯絡電話
  final String handicap; // 差點資訊

  ProfileEditResult({
    required this.displayName,
    required this.email,
    required this.phone,
    required this.handicap,
  });
}

/// 個人資訊編輯頁面，提供使用者檢視與修改個資
class ProfileEditPage extends StatefulWidget {
  final String initialDisplayName; // 初始暱稱，用於預先填入表單
  final String initialEmail; // 初始電子郵件，與登入信箱同步

  const ProfileEditPage({
    super.key,
    required this.initialDisplayName,
    required this.initialEmail,
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // 表單驗證用 key
  late final TextEditingController _displayNameController; // 暱稱輸入控制器
  late final TextEditingController _emailController; // 電子郵件輸入控制器
  final TextEditingController _phoneController = TextEditingController(); // 聯絡電話控制器
  final TextEditingController _handicapController = TextEditingController(); // 差點控制器

  @override
  void initState() {
    super.initState();
    // ---------- 狀態初始化區 ----------
    // 將外部傳入的資料填入控制器，確保使用者進入頁面時即看到目前設定
    _displayNameController = TextEditingController(text: widget.initialDisplayName);
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    // ---------- 資源釋放區 ----------
    // 避免控制器持續佔用記憶體，於頁面關閉時確實釋放
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _handicapController.dispose();
    super.dispose();
  }

  // ---------- 方法區 ----------
  /// 驗證並送出表單，將填寫資料回傳給上一層頁面
  void _handleSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return; // 若驗證失敗則不進行後續流程
    }

    final result = ProfileEditResult(
      displayName: _displayNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      handicap: _handicapController.text.trim(),
    );

    // 回到上一頁同時夾帶資料，供首頁更新顯示或後續擴充 API 使用
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    // ---------- 生命週期渲染區 ----------
    return Scaffold(
      appBar: AppBar(
        title: const Text('個人資訊'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                '調整個人資訊以獲得更精準的揮桿分析，完成後記得儲存。',
                style: TextStyle(color: Color(0xFF6E7B87)),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: '暱稱',
                  hintText: '輸入想在首頁顯示的名稱',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '請輸入暱稱';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                readOnly: true, // 電子郵件作為帳號識別，僅顯示不可修改
                decoration: const InputDecoration(
                  labelText: '電子郵件',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '聯絡電話',
                  hintText: '例：0912-345-678',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _handicapController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '差點',
                  hintText: '可填寫目前差點或目標數值',
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _handleSubmit,
                child: const Text('儲存變更'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
