import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 個人資訊編輯結果模型，用於回傳最新填寫內容
class ProfileEditResult {
  final String displayName; // 暱稱顯示名稱
  final String email; // 電子郵件
  final String phone; // 聯絡電話
  final String handicap; // 差點資訊
  final String? avatarPath; // 頭像圖檔位置，若為空代表維持原狀
  final bool removeAvatar; // 是否清除頭像，true 時回到預設圖示

  ProfileEditResult({
    required this.displayName,
    required this.email,
    required this.phone,
    required this.handicap,
    required this.avatarPath,
    required this.removeAvatar,
  });
}

/// 個人資訊編輯頁面，提供使用者檢視與修改個資
class ProfileEditPage extends StatefulWidget {
  final String initialDisplayName; // 初始暱稱，用於預先填入表單
  final String initialEmail; // 初始電子郵件，與登入信箱同步
  final String? initialAvatarPath; // 初始頭像位置，方便重複編輯時保留

  const ProfileEditPage({
    super.key,
    required this.initialDisplayName,
    required this.initialEmail,
    this.initialAvatarPath,
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
  String? _avatarPath; // 當前選擇的頭像檔案路徑
  bool _removeAvatar = false; // 記錄是否使用者要求清除頭像
  static const String _avatarDirectoryName = 'profile_avatars'; // 頭像檔案集中存放的資料夾

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('profile_edit');
    // ---------- 狀態初始化區 ----------
    // 將外部傳入的資料填入控制器，確保使用者進入頁面時即看到目前設定
    _displayNameController = TextEditingController(text: widget.initialDisplayName);
    _emailController = TextEditingController(text: widget.initialEmail);
    _avatarPath = widget.initialAvatarPath; // 將先前設定的頭像同步到表單狀態
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
      avatarPath: _avatarPath,
      removeAvatar: _removeAvatar,
    );

    // 回到上一頁同時夾帶資料，供首頁更新顯示或後續擴充 API 使用
    Navigator.of(context).pop(result);
  }

  /// 觸發檔案選擇，讓使用者可以挑選或更換頭像照片
  Future<void> _handlePickAvatar() async {
    // 使用 file_picker 支援多平台圖片挑選，並限制為單張圖片；withData 可兼容僅提供記憶體資料的情境
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return; // 使用者取消選擇時不更新狀態
    }

    final pickedFile = result.files.single;

    try {
      final previousPath = _avatarPath; // 暫存舊檔路徑以便稍後清除
      final persistedPath = await _persistAvatarSelection(
        sourcePath: pickedFile.path,
        bytes: pickedFile.path == null ? pickedFile.bytes : null,
      );

      if (!mounted) {
        return; // 若寫入過程中頁面已被關閉則不再更新 UI
      }

      setState(() {
        _avatarPath = persistedPath; // 儲存於應用資料夾內的安全路徑
        _removeAvatar = false; // 只要挑選新圖片即視為使用者不想清除
      });

      if (previousPath != null && previousPath != persistedPath) {
        await _deletePersistedAvatar(previousPath); // 清除舊副本，避免佔用過多儲存空間
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileAvatarSaveFailed)),
      );
    }
  }

  /// 清除目前的頭像設定，恢復為預設圖示
  Future<void> _handleRemoveAvatar() async {
    final previousPath = _avatarPath; // 保留當前路徑，等 UI 更新後再清除實體檔案
    setState(() {
      _avatarPath = null; // 將狀態設為空即可在首頁顯示預設圖示
      _removeAvatar = true; // 標記清除狀態，方便上一頁調整顯示
    });

    if (previousPath != null) {
      await _deletePersistedAvatar(previousPath); // 刪除存放在應用目錄內的舊頭像
    }
  }

  /// 將使用者挑選的頭像存放到應用程式專屬目錄，避免分享時因權限不足而無法讀取
  Future<String> _persistAvatarSelection({
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    if (sourcePath == null && bytes == null) {
      throw ArgumentError('缺少頭像來源資料');
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(p.join(documentsDir.path, _avatarDirectoryName));
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true); // 確保資料夾存在，避免寫入失敗
    }

    final extension = sourcePath != null ? p.extension(sourcePath) : '';
    final safeExtension = extension.isEmpty ? '.jpg' : extension; // 若無副檔名則預設使用 jpg
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}$safeExtension';
    final targetFile = File(p.join(avatarDir.path, fileName));

    if (sourcePath != null) {
      await File(sourcePath).copy(targetFile.path); // 從原檔案建立一份副本
    } else if (bytes != null) {
      await targetFile.writeAsBytes(bytes, flush: true); // 將記憶體資料轉存成本地檔案
    }

    return targetFile.path;
  }

  /// 刪除存放於應用程式目錄內的舊頭像，避免重複挑選造成磁碟堆積
  Future<void> _deletePersistedAvatar(String path) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final avatarDirPath = p.join(documentsDir.path, _avatarDirectoryName);

    // 僅當檔案位於 avatars 資料夾內時才允許刪除，避免誤刪使用者原始圖片
    final normalizedPath = p.normalize(path);
    if (!p.isWithin(avatarDirPath, normalizedPath)) {
      return;
    }

    final file = File(normalizedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 建立頭像預覽區塊，包含目前圖片、覆蓋提示與操作按鈕
  Widget _buildAvatarSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasAvatar = _avatarPath != null && File(_avatarPath!).existsSync();

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: context.mintTint,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kBrandPrimary, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasAvatar
                  ? Image.file(
                      File(_avatarPath!),
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person, size: 56, color: kBrandPrimary),
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: FloatingActionButton.small(
                heroTag: 'avatarPicker',
                onPressed: () => _handlePickAvatar(),
                backgroundColor: kBrandPrimary,
                child: const Icon(Icons.edit, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.profileAvatarHint, style: TextStyle(color: context.textSecondary)),
        if (hasAvatar)
          TextButton.icon(
            onPressed: () => _handleRemoveAvatar(),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.profileRemoveAvatar),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ---------- 生命週期渲染區 ----------
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildAvatarSection(context),
              const SizedBox(height: 24),
              Text(
                l10n.profileSubtitle,
                style: TextStyle(color: context.textSecondary),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: l10n.profileDisplayNameLabel,
                  hintText: l10n.profileDisplayNameHint,
                  hintMaxLines: 1,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.profileDisplayNameRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                readOnly: true, // 電子郵件作為帳號識別，僅顯示不可修改
                decoration: InputDecoration(
                  labelText: l10n.profileEmailLabel,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.profilePhoneLabel,
                  hintText: l10n.profilePhoneHint,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _handicapController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.profileHandicapLabel,
                  hintText: l10n.profileHandicapHint,
                  hintMaxLines: 1,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _handleSubmit,
                child: Text(l10n.profileSaveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
