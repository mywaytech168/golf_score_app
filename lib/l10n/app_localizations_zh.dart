// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'TekSwing';

  @override
  String get appTagline => '智慧揮桿訓練平台';

  @override
  String get commonSave => '儲存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '確認';

  @override
  String get commonClose => '關閉';

  @override
  String get commonRetry => '重試';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonEdit => '編輯';

  @override
  String get commonOpenSettings => '開啟設定';

  @override
  String get commonOk => '確定';

  @override
  String get commonLoading => '載入中...';

  @override
  String get commonUnknownError => '發生未知錯誤，請稍後再試';

  @override
  String get authWelcomeBack => '歡迎回來！';

  @override
  String get authLoginSubtitle => '請登入 TekSwing 以同步揮桿資料並探索最新分析報告。';

  @override
  String get authRegisterTitle => '建立帳號';

  @override
  String get authRegisterSubtitle => '填寫以下資料即可開始使用 TekSwing。';

  @override
  String get authLoginTitle => '登入帳號';

  @override
  String get authUsernameOrEmail => '用戶名 / 電子郵件';

  @override
  String get authUsernameHint => 'username 或 you@example.com';

  @override
  String get authUsername => '用戶名';

  @override
  String get authUsernameHintReg => '用於登入，不可重複';

  @override
  String get authEmail => '電子郵件';

  @override
  String get authDisplayName => '顯示名稱（可選）';

  @override
  String get authDisplayNameHint => '留空則與用戶名相同';

  @override
  String get authPassword => '密碼';

  @override
  String get authPasswordLabel => '密碼（至少 6 碼）';

  @override
  String get authConfirmPassword => '確認密碼';

  @override
  String get authRememberMe => '記住我';

  @override
  String get authForgotPassword => '忘記密碼？';

  @override
  String get authLoginButton => '登入 TekSwing';

  @override
  String get authRegisterButton => '建立帳號';

  @override
  String get authSocialDivider => '或使用社群帳號快速登入';

  @override
  String get authLoginWithGoogle => '使用 Google 登入';

  @override
  String get authGoogleSigningIn => 'Google 登入中...';

  @override
  String get authNoAccount => '還沒有帳戶？立即註冊';

  @override
  String get authHaveAccount => '已有帳戶？返回登入';

  @override
  String get authEncryptionNote => '所有資料皆採用 256-bit 加密保護';

  @override
  String get validationEnterUsernameOrEmail => '請輸入用戶名或電子郵件';

  @override
  String get validationEnterPassword => '請輸入密碼';

  @override
  String get validationEnterEmail => '請輸入電子郵件';

  @override
  String get validationInvalidEmail => '電子郵件格式不正確';

  @override
  String get validationEnterUsername => '請輸入用戶名';

  @override
  String get validationUsernameTooShort => '用戶名至少 3 個字元';

  @override
  String get validationPasswordTooShort => '密碼至少需要 6 碼';

  @override
  String get validationPasswordMismatch => '兩次密碼不一致';

  @override
  String get validationEnterPasswordAgain => '請再次輸入密碼';

  @override
  String get msgLoginSuccess => '登入成功，歡迎回來！';

  @override
  String get msgLoginFailed => '登入失敗，請檢查帳號密碼';

  @override
  String msgLoginFailedWithError(String error) {
    return '登入失敗：$error';
  }

  @override
  String get msgRegisterSuccess => '註冊成功，請登入';

  @override
  String get msgRegisterFailed => '註冊失敗';

  @override
  String msgRegisterFailedWithError(String error) {
    return '註冊失敗：$error';
  }

  @override
  String get msgGoogleLoginCancelled => '已取消 Google 登入流程';

  @override
  String get msgGoogleLoginSuccess => 'Google 登入成功，歡迎回來！';

  @override
  String msgGoogleLoginFailed(String error) {
    return 'Google 登入失敗：$error';
  }

  @override
  String get msgGoogleLoginNoToken => 'Google 登入失敗：後端未返回認證令牌';

  @override
  String get permTitle => '請先授權藍牙與定位';

  @override
  String get permSubtitle => '首次登入時需要取得藍牙權限。';

  @override
  String get permGranted => '已允許';

  @override
  String get permDenied => '尚未允許';

  @override
  String get permLocation => '定位';

  @override
  String get permCheckAgain => '重新檢查權限';

  @override
  String get permStatusTitle => '權限狀態';

  @override
  String get permNotChecked => '尚未檢查權限';

  @override
  String get permDialogTitle => '需要開啟權限';

  @override
  String get permGoToSettings => '前往設定';

  @override
  String get permIKnow => '知道了';

  @override
  String get permBluetooth => '請允許藍牙權限。';

  @override
  String get permIosInstructions =>
      '需要定位權限才能使用藍牙掃描功能：\n\n1. 點擊「開啟設定」\n2. 找到「Golf Score App」\n3. 點選「位置」→「使用 App 期間」\n4. 返回 App 重新登入';

  @override
  String get permAndroidInstructions =>
      '請在系統設定中允許以下權限：\n1. 進入「應用程式與通知」\n2. 選擇 TekSwing → 權限\n3. 啟用「附近裝置、藍牙」與「定位」';

  @override
  String get permStatusGranted => '已允許';

  @override
  String get permStatusDenied => '已拒絕';

  @override
  String get navHome => '首頁';

  @override
  String get navData => '數據';

  @override
  String get navRecord => '錄製';

  @override
  String get navHistory => '歷史';

  @override
  String get navPremium => '付費';

  @override
  String get homeLogout => '登出';

  @override
  String get homeConfirmLogout => '確認登出';

  @override
  String get homeConfirmLogoutMsg => '您確定要登出嗎？';

  @override
  String get homeConfirmLogoutBtn => '確定登出';

  @override
  String get homeTodayUnlimited => '今日無限制 🏆';

  @override
  String homeTodayUsage(int used, int total) {
    return '今日用量 $used / $total 球';
  }

  @override
  String homeTodayUsageBonus(int used, int total, int bonus) {
    return '今日用量 $used / $total 球（含 +$bonus 獎勵）';
  }

  @override
  String get homeTodayLimit => '⚠️ 已達上限';

  @override
  String get homeProfile => '個人資料';

  @override
  String get homeRewards => '獎勵';

  @override
  String get homeGoodShot => '好球';

  @override
  String get homeBadShot => '壞球';

  @override
  String get homeTotalShots => '總次數';

  @override
  String get homeAvgScore => '平均分數';

  @override
  String get homeNoDataYet => '今日尚無資料';

  @override
  String get homeStartRecording => '開始錄製';

  @override
  String get recTitle => '新增錄製';

  @override
  String get recStartRecording => '開始錄製';

  @override
  String get recSelectLocalVideo => '選擇本地影片';

  @override
  String get recImportFromShare => '從分享連結取得';

  @override
  String get recImporting => '導入中...';

  @override
  String get recSelected => '已選擇';

  @override
  String get recSuccess => '導入成功';

  @override
  String get recFailed => '導入失敗';

  @override
  String get recCancelled => '已取消';

  @override
  String get historyTitle => '錄製歷史';

  @override
  String get historyEmpty => '尚無錄製記錄';

  @override
  String get historyDeleteConfirm => '刪除此錄製？';

  @override
  String get historyDeleteConfirmMsg => '此操作無法復原。';

  @override
  String get upgradeTitle => '升級方案';

  @override
  String get upgradeFreeForever => '永久免費';

  @override
  String get upgradePerMonth => '/月';

  @override
  String get upgradeRecommended => '推薦';

  @override
  String get upgradeCurrentPlan => '目前方案';

  @override
  String get upgradeSubscribe => '立即訂閱';

  @override
  String get upgradeFeatureSwingRecording => '揮桿錄影';

  @override
  String get upgradeFeatureVideoAnalysis => '長影片切片分析';

  @override
  String get upgradeFeatureVoice => '即時語音';

  @override
  String get upgradeFeatureBallTrack => '球軌跡分析';

  @override
  String get upgradeFeatureOverlay => '疊影分析';

  @override
  String get upgradeFeatureClubTrack => '桿頭軌跡分析';

  @override
  String get upgradeFeaturePose => '骨架姿勢分析';

  @override
  String get upgradeFeatureRhythm => '節奏 / 速度分析';

  @override
  String get upgradeFeatureScore => '揮桿分數估算';

  @override
  String get upgradeFeatureAiCoach => 'AI 姿勢建議';

  @override
  String get upgradeFeatureTraining => '訓練建議';

  @override
  String get upgradeFeatureCorrection => '修正追蹤';

  @override
  String get upgradeFeatureReport => '每日 / 月報告';

  @override
  String get upgradeFeatureCompare => '與他人比較';

  @override
  String get upgradeFeatureAds => '廣告';

  @override
  String get upgradeUnlimited => '無限制';

  @override
  String get upgradeHighQuality => '高畫質';

  @override
  String get upgradeHistoryCompare => '歷史比較';

  @override
  String get upgradeNoAds => '無廣告';

  @override
  String get upgradeAdvanced => '進階';

  @override
  String get todayTitle => '今日數據';

  @override
  String get todaySwingCount => '揮桿次數';

  @override
  String get todayGoodRate => '好球率';

  @override
  String get todayAvgSpeed => '平均速度';

  @override
  String get aiCoachTitle => 'AI 教練分析';

  @override
  String get aiCoachAnalyzing => '分析中，通常需要 10~30 秒';

  @override
  String get aiCoachNoData => '尚無分析資料';

  @override
  String get aiCoachBasis => '依據';

  @override
  String get aiCoachSuggestion => '建議';

  @override
  String get profileTitle => '編輯個人資料';

  @override
  String get profileAvatar => '設定個人頭像讓教練更容易識別';

  @override
  String get profileRemoveAvatar => '移除頭像';

  @override
  String get profilePersonalInfo => '個人資訊';

  @override
  String get profileDisplayName => '顯示名稱';

  @override
  String get profileSaveChanges => '儲存變更';

  @override
  String get langTitle => '語言';

  @override
  String get langZhTW => '繁體中文';

  @override
  String get langZhCN => '简体中文';

  @override
  String get langEn => 'English';

  @override
  String get langSelectTitle => '選擇語言';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appName => 'TekSwing';

  @override
  String get appTagline => '智能挥杆训练平台';

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonClose => '关闭';

  @override
  String get commonRetry => '重试';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonOpenSettings => '打开设置';

  @override
  String get commonOk => '确定';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonUnknownError => '发生未知错误，请稍后再试';

  @override
  String get authWelcomeBack => '欢迎回来！';

  @override
  String get authLoginSubtitle => '登录 TekSwing 以同步挥杆数据并探索最新分析报告。';

  @override
  String get authRegisterTitle => '创建账号';

  @override
  String get authRegisterSubtitle => '填写以下信息即可开始使用 TekSwing。';

  @override
  String get authLoginTitle => '登录账号';

  @override
  String get authUsernameOrEmail => '用户名 / 电子邮件';

  @override
  String get authUsernameHint => 'username 或 you@example.com';

  @override
  String get authUsername => '用户名';

  @override
  String get authUsernameHintReg => '用于登录，不可重复';

  @override
  String get authEmail => '电子邮件';

  @override
  String get authDisplayName => '显示名称（可选）';

  @override
  String get authDisplayNameHint => '留空则与用户名相同';

  @override
  String get authPassword => '密码';

  @override
  String get authPasswordLabel => '密码（至少 6 位）';

  @override
  String get authConfirmPassword => '确认密码';

  @override
  String get authRememberMe => '记住我';

  @override
  String get authForgotPassword => '忘记密码？';

  @override
  String get authLoginButton => '登录 TekSwing';

  @override
  String get authRegisterButton => '创建账号';

  @override
  String get authSocialDivider => '或使用社交账号快速登录';

  @override
  String get authLoginWithGoogle => '使用 Google 登录';

  @override
  String get authGoogleSigningIn => 'Google 登录中...';

  @override
  String get authNoAccount => '还没有账号？立即注册';

  @override
  String get authHaveAccount => '已有账号？返回登录';

  @override
  String get authEncryptionNote => '所有数据均采用 256 位加密保护';

  @override
  String get validationEnterUsernameOrEmail => '请输入用户名或电子邮件';

  @override
  String get validationEnterPassword => '请输入密码';

  @override
  String get validationEnterEmail => '请输入电子邮件';

  @override
  String get validationInvalidEmail => '电子邮件格式不正确';

  @override
  String get validationEnterUsername => '请输入用户名';

  @override
  String get validationUsernameTooShort => '用户名至少 3 个字符';

  @override
  String get validationPasswordTooShort => '密码至少需要 6 位';

  @override
  String get validationPasswordMismatch => '两次密码不一致';

  @override
  String get validationEnterPasswordAgain => '请再次输入密码';

  @override
  String get msgLoginSuccess => '登录成功，欢迎回来！';

  @override
  String get msgLoginFailed => '登录失败，请检查账号密码';

  @override
  String msgLoginFailedWithError(String error) {
    return '登录失败：$error';
  }

  @override
  String get msgRegisterSuccess => '注册成功，请登录';

  @override
  String get msgRegisterFailed => '注册失败';

  @override
  String msgRegisterFailedWithError(String error) {
    return '注册失败：$error';
  }

  @override
  String get msgGoogleLoginCancelled => '已取消 Google 登录流程';

  @override
  String get msgGoogleLoginSuccess => 'Google 登录成功，欢迎回来！';

  @override
  String msgGoogleLoginFailed(String error) {
    return 'Google 登录失败：$error';
  }

  @override
  String get msgGoogleLoginNoToken => 'Google 登录失败：服务器未返回认证令牌';

  @override
  String get permTitle => '请先授权蓝牙与定位';

  @override
  String get permSubtitle => '首次登录时需要获取蓝牙权限。';

  @override
  String get permGranted => '已允许';

  @override
  String get permDenied => '尚未允许';

  @override
  String get permLocation => '定位';

  @override
  String get permCheckAgain => '重新检查权限';

  @override
  String get permStatusTitle => '权限状态';

  @override
  String get permNotChecked => '尚未检查权限';

  @override
  String get permDialogTitle => '需要开启权限';

  @override
  String get permGoToSettings => '前往设置';

  @override
  String get permIKnow => '知道了';

  @override
  String get permBluetooth => '请允许蓝牙权限。';

  @override
  String get permIosInstructions =>
      '需要定位权限才能使用蓝牙扫描功能：\n\n1. 点击「打开设置」\n2. 找到「Golf Score App」\n3. 点选「位置」→「使用 App 期间」\n4. 返回 App 重新登录';

  @override
  String get permAndroidInstructions =>
      '请在系统设置中允许以下权限：\n1. 进入「应用与通知」\n2. 选择 TekSwing → 权限\n3. 启用「附近设备、蓝牙」与「定位」';

  @override
  String get permStatusGranted => '已允许';

  @override
  String get permStatusDenied => '已拒绝';

  @override
  String get navHome => '首页';

  @override
  String get navData => '数据';

  @override
  String get navRecord => '录制';

  @override
  String get navHistory => '历史';

  @override
  String get navPremium => '付费';

  @override
  String get homeLogout => '退出登录';

  @override
  String get homeConfirmLogout => '确认退出';

  @override
  String get homeConfirmLogoutMsg => '您确定要退出登录吗？';

  @override
  String get homeConfirmLogoutBtn => '确定退出';

  @override
  String get homeTodayUnlimited => '今日无限制 🏆';

  @override
  String homeTodayUsage(int used, int total) {
    return '今日用量 $used / $total 球';
  }

  @override
  String homeTodayUsageBonus(int used, int total, int bonus) {
    return '今日用量 $used / $total 球（含 +$bonus 奖励）';
  }

  @override
  String get homeTodayLimit => '⚠️ 已达上限';

  @override
  String get homeProfile => '个人资料';

  @override
  String get homeRewards => '奖励';

  @override
  String get homeGoodShot => '好球';

  @override
  String get homeBadShot => '坏球';

  @override
  String get homeTotalShots => '总次数';

  @override
  String get homeAvgScore => '平均分数';

  @override
  String get homeNoDataYet => '今日暂无数据';

  @override
  String get homeStartRecording => '开始录制';

  @override
  String get recTitle => '新建录制';

  @override
  String get recStartRecording => '开始录制';

  @override
  String get recSelectLocalVideo => '选择本地视频';

  @override
  String get recImportFromShare => '从分享链接获取';

  @override
  String get recImporting => '导入中...';

  @override
  String get recSelected => '已选择';

  @override
  String get recSuccess => '导入成功';

  @override
  String get recFailed => '导入失败';

  @override
  String get recCancelled => '已取消';

  @override
  String get historyTitle => '录制历史';

  @override
  String get historyEmpty => '暂无录制记录';

  @override
  String get historyDeleteConfirm => '删除此录制？';

  @override
  String get historyDeleteConfirmMsg => '此操作无法撤销。';

  @override
  String get upgradeTitle => '升级方案';

  @override
  String get upgradeFreeForever => '永久免费';

  @override
  String get upgradePerMonth => '/月';

  @override
  String get upgradeRecommended => '推荐';

  @override
  String get upgradeCurrentPlan => '当前方案';

  @override
  String get upgradeSubscribe => '立即订阅';

  @override
  String get upgradeFeatureSwingRecording => '挥杆录影';

  @override
  String get upgradeFeatureVideoAnalysis => '长视频切片分析';

  @override
  String get upgradeFeatureVoice => '实时语音';

  @override
  String get upgradeFeatureBallTrack => '球轨迹分析';

  @override
  String get upgradeFeatureOverlay => '叠影分析';

  @override
  String get upgradeFeatureClubTrack => '杆头轨迹分析';

  @override
  String get upgradeFeaturePose => '骨骼姿势分析';

  @override
  String get upgradeFeatureRhythm => '节奏 / 速度分析';

  @override
  String get upgradeFeatureScore => '挥杆分数估算';

  @override
  String get upgradeFeatureAiCoach => 'AI 姿势建议';

  @override
  String get upgradeFeatureTraining => '训练建议';

  @override
  String get upgradeFeatureCorrection => '修正追踪';

  @override
  String get upgradeFeatureReport => '每日 / 月报告';

  @override
  String get upgradeFeatureCompare => '与他人比较';

  @override
  String get upgradeFeatureAds => '广告';

  @override
  String get upgradeUnlimited => '无限制';

  @override
  String get upgradeHighQuality => '高画质';

  @override
  String get upgradeHistoryCompare => '历史比较';

  @override
  String get upgradeNoAds => '无广告';

  @override
  String get upgradeAdvanced => '高级';

  @override
  String get todayTitle => '今日数据';

  @override
  String get todaySwingCount => '挥杆次数';

  @override
  String get todayGoodRate => '好球率';

  @override
  String get todayAvgSpeed => '平均速度';

  @override
  String get aiCoachTitle => 'AI 教练分析';

  @override
  String get aiCoachAnalyzing => '分析中，通常需要 10~30 秒';

  @override
  String get aiCoachNoData => '暂无分析数据';

  @override
  String get aiCoachBasis => '依据';

  @override
  String get aiCoachSuggestion => '建议';

  @override
  String get profileTitle => '编辑个人资料';

  @override
  String get profileAvatar => '设置头像让教练更容易识别您';

  @override
  String get profileRemoveAvatar => '移除头像';

  @override
  String get profilePersonalInfo => '个人信息';

  @override
  String get profileDisplayName => '显示名称';

  @override
  String get profileSaveChanges => '保存更改';

  @override
  String get langTitle => '语言';

  @override
  String get langZhTW => '繁體中文';

  @override
  String get langZhCN => '简体中文';

  @override
  String get langEn => 'English';

  @override
  String get langSelectTitle => '选择语言';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appName => 'TekSwing';

  @override
  String get appTagline => '智慧揮桿訓練平台';

  @override
  String get commonSave => '儲存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '確認';

  @override
  String get commonClose => '關閉';

  @override
  String get commonRetry => '重試';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonEdit => '編輯';

  @override
  String get commonOpenSettings => '開啟設定';

  @override
  String get commonOk => '確定';

  @override
  String get commonLoading => '載入中...';

  @override
  String get commonUnknownError => '發生未知錯誤，請稍後再試';

  @override
  String get authWelcomeBack => '歡迎回來！';

  @override
  String get authLoginSubtitle => '請登入 TekSwing 以同步揮桿資料並探索最新分析報告。';

  @override
  String get authRegisterTitle => '建立帳號';

  @override
  String get authRegisterSubtitle => '填寫以下資料即可開始使用 TekSwing。';

  @override
  String get authLoginTitle => '登入帳號';

  @override
  String get authUsernameOrEmail => '用戶名 / 電子郵件';

  @override
  String get authUsernameHint => 'username 或 you@example.com';

  @override
  String get authUsername => '用戶名';

  @override
  String get authUsernameHintReg => '用於登入，不可重複';

  @override
  String get authEmail => '電子郵件';

  @override
  String get authDisplayName => '顯示名稱（可選）';

  @override
  String get authDisplayNameHint => '留空則與用戶名相同';

  @override
  String get authPassword => '密碼';

  @override
  String get authPasswordLabel => '密碼（至少 6 碼）';

  @override
  String get authConfirmPassword => '確認密碼';

  @override
  String get authRememberMe => '記住我';

  @override
  String get authForgotPassword => '忘記密碼？';

  @override
  String get authLoginButton => '登入 TekSwing';

  @override
  String get authRegisterButton => '建立帳號';

  @override
  String get authSocialDivider => '或使用社群帳號快速登入';

  @override
  String get authLoginWithGoogle => '使用 Google 登入';

  @override
  String get authGoogleSigningIn => 'Google 登入中...';

  @override
  String get authNoAccount => '還沒有帳戶？立即註冊';

  @override
  String get authHaveAccount => '已有帳戶？返回登入';

  @override
  String get authEncryptionNote => '所有資料皆採用 256-bit 加密保護';

  @override
  String get validationEnterUsernameOrEmail => '請輸入用戶名或電子郵件';

  @override
  String get validationEnterPassword => '請輸入密碼';

  @override
  String get validationEnterEmail => '請輸入電子郵件';

  @override
  String get validationInvalidEmail => '電子郵件格式不正確';

  @override
  String get validationEnterUsername => '請輸入用戶名';

  @override
  String get validationUsernameTooShort => '用戶名至少 3 個字元';

  @override
  String get validationPasswordTooShort => '密碼至少需要 6 碼';

  @override
  String get validationPasswordMismatch => '兩次密碼不一致';

  @override
  String get validationEnterPasswordAgain => '請再次輸入密碼';

  @override
  String get msgLoginSuccess => '登入成功，歡迎回來！';

  @override
  String get msgLoginFailed => '登入失敗，請檢查帳號密碼';

  @override
  String msgLoginFailedWithError(String error) {
    return '登入失敗：$error';
  }

  @override
  String get msgRegisterSuccess => '註冊成功，請登入';

  @override
  String get msgRegisterFailed => '註冊失敗';

  @override
  String msgRegisterFailedWithError(String error) {
    return '註冊失敗：$error';
  }

  @override
  String get msgGoogleLoginCancelled => '已取消 Google 登入流程';

  @override
  String get msgGoogleLoginSuccess => 'Google 登入成功，歡迎回來！';

  @override
  String msgGoogleLoginFailed(String error) {
    return 'Google 登入失敗：$error';
  }

  @override
  String get msgGoogleLoginNoToken => 'Google 登入失敗：後端未返回認證令牌';

  @override
  String get permTitle => '請先授權藍牙與定位';

  @override
  String get permSubtitle => '首次登入時需要取得藍牙權限。';

  @override
  String get permGranted => '已允許';

  @override
  String get permDenied => '尚未允許';

  @override
  String get permLocation => '定位';

  @override
  String get permCheckAgain => '重新檢查權限';

  @override
  String get permStatusTitle => '權限狀態';

  @override
  String get permNotChecked => '尚未檢查權限';

  @override
  String get permDialogTitle => '需要開啟權限';

  @override
  String get permGoToSettings => '前往設定';

  @override
  String get permIKnow => '知道了';

  @override
  String get permBluetooth => '請允許藍牙權限。';

  @override
  String get permIosInstructions =>
      '需要定位權限才能使用藍牙掃描功能：\n\n1. 點擊「開啟設定」\n2. 找到「Golf Score App」\n3. 點選「位置」→「使用 App 期間」\n4. 返回 App 重新登入';

  @override
  String get permAndroidInstructions =>
      '請在系統設定中允許以下權限：\n1. 進入「應用程式與通知」\n2. 選擇 TekSwing → 權限\n3. 啟用「附近裝置、藍牙」與「定位」';

  @override
  String get permStatusGranted => '已允許';

  @override
  String get permStatusDenied => '已拒絕';

  @override
  String get navHome => '首頁';

  @override
  String get navData => '數據';

  @override
  String get navRecord => '錄製';

  @override
  String get navHistory => '歷史';

  @override
  String get navPremium => '付費';

  @override
  String get homeLogout => '登出';

  @override
  String get homeConfirmLogout => '確認登出';

  @override
  String get homeConfirmLogoutMsg => '您確定要登出嗎？';

  @override
  String get homeConfirmLogoutBtn => '確定登出';

  @override
  String get homeTodayUnlimited => '今日無限制 🏆';

  @override
  String homeTodayUsage(int used, int total) {
    return '今日用量 $used / $total 球';
  }

  @override
  String homeTodayUsageBonus(int used, int total, int bonus) {
    return '今日用量 $used / $total 球（含 +$bonus 獎勵）';
  }

  @override
  String get homeTodayLimit => '⚠️ 已達上限';

  @override
  String get homeProfile => '個人資料';

  @override
  String get homeRewards => '獎勵';

  @override
  String get homeGoodShot => '好球';

  @override
  String get homeBadShot => '壞球';

  @override
  String get homeTotalShots => '總次數';

  @override
  String get homeAvgScore => '平均分數';

  @override
  String get homeNoDataYet => '今日尚無資料';

  @override
  String get homeStartRecording => '開始錄製';

  @override
  String get recTitle => '新增錄製';

  @override
  String get recStartRecording => '開始錄製';

  @override
  String get recSelectLocalVideo => '選擇本地影片';

  @override
  String get recImportFromShare => '從分享連結取得';

  @override
  String get recImporting => '導入中...';

  @override
  String get recSelected => '已選擇';

  @override
  String get recSuccess => '導入成功';

  @override
  String get recFailed => '導入失敗';

  @override
  String get recCancelled => '已取消';

  @override
  String get historyTitle => '錄製歷史';

  @override
  String get historyEmpty => '尚無錄製記錄';

  @override
  String get historyDeleteConfirm => '刪除此錄製？';

  @override
  String get historyDeleteConfirmMsg => '此操作無法復原。';

  @override
  String get upgradeTitle => '升級方案';

  @override
  String get upgradeFreeForever => '永久免費';

  @override
  String get upgradePerMonth => '/月';

  @override
  String get upgradeRecommended => '推薦';

  @override
  String get upgradeCurrentPlan => '目前方案';

  @override
  String get upgradeSubscribe => '立即訂閱';

  @override
  String get upgradeFeatureSwingRecording => '揮桿錄影';

  @override
  String get upgradeFeatureVideoAnalysis => '長影片切片分析';

  @override
  String get upgradeFeatureVoice => '即時語音';

  @override
  String get upgradeFeatureBallTrack => '球軌跡分析';

  @override
  String get upgradeFeatureOverlay => '疊影分析';

  @override
  String get upgradeFeatureClubTrack => '桿頭軌跡分析';

  @override
  String get upgradeFeaturePose => '骨架姿勢分析';

  @override
  String get upgradeFeatureRhythm => '節奏 / 速度分析';

  @override
  String get upgradeFeatureScore => '揮桿分數估算';

  @override
  String get upgradeFeatureAiCoach => 'AI 姿勢建議';

  @override
  String get upgradeFeatureTraining => '訓練建議';

  @override
  String get upgradeFeatureCorrection => '修正追蹤';

  @override
  String get upgradeFeatureReport => '每日 / 月報告';

  @override
  String get upgradeFeatureCompare => '與他人比較';

  @override
  String get upgradeFeatureAds => '廣告';

  @override
  String get upgradeUnlimited => '無限制';

  @override
  String get upgradeHighQuality => '高畫質';

  @override
  String get upgradeHistoryCompare => '歷史比較';

  @override
  String get upgradeNoAds => '無廣告';

  @override
  String get upgradeAdvanced => '進階';

  @override
  String get todayTitle => '今日數據';

  @override
  String get todaySwingCount => '揮桿次數';

  @override
  String get todayGoodRate => '好球率';

  @override
  String get todayAvgSpeed => '平均速度';

  @override
  String get aiCoachTitle => 'AI 教練分析';

  @override
  String get aiCoachAnalyzing => '分析中，通常需要 10~30 秒';

  @override
  String get aiCoachNoData => '尚無分析資料';

  @override
  String get aiCoachBasis => '依據';

  @override
  String get aiCoachSuggestion => '建議';

  @override
  String get profileTitle => '編輯個人資料';

  @override
  String get profileAvatar => '設定個人頭像讓教練更容易識別';

  @override
  String get profileRemoveAvatar => '移除頭像';

  @override
  String get profilePersonalInfo => '個人資訊';

  @override
  String get profileDisplayName => '顯示名稱';

  @override
  String get profileSaveChanges => '儲存變更';

  @override
  String get langTitle => '語言';

  @override
  String get langZhTW => '繁體中文';

  @override
  String get langZhCN => '简体中文';

  @override
  String get langEn => 'English';

  @override
  String get langSelectTitle => '選擇語言';
}
