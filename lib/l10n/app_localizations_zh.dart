// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'ORVIA';

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
  String get authLoginSubtitle => '請登入 ORVIA 以同步揮桿資料並探索最新分析報告。';

  @override
  String get authRegisterTitle => '建立帳號';

  @override
  String get authRegisterSubtitle => '填寫以下資料即可開始使用 ORVIA。';

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
  String get authLoginButton => '登入 ORVIA';

  @override
  String get authRegisterButton => '建立帳號';

  @override
  String get authSocialDivider => '或使用社群帳號快速登入';

  @override
  String get authLoginWithGoogle => '使用 Google 登入';

  @override
  String get authGoogleSigningIn => 'Google 登入中...';

  @override
  String get authLoginWithApple => '使用 Apple 登入';

  @override
  String get authAppleSigningIn => 'Apple 登入中...';

  @override
  String get authNoAccount => '還沒有帳戶？立即註冊';

  @override
  String get authHaveAccount => '已有帳戶？返回登入';

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
  String get validationPasswordTooShort => '密碼須至少 8 碼且包含大寫、小寫字母及數字';

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
  String get msgAppleLoginCancelled => '已取消 Apple 登入流程';

  @override
  String get msgAppleLoginSuccess => 'Apple 登入成功，歡迎回來！';

  @override
  String msgAppleLoginFailed(Object error) {
    return 'Apple 登入失敗：$error';
  }

  @override
  String get msgAppleLoginNoToken => 'Apple 登入失敗：後端未返回認證令牌';

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
      '請在系統設定中允許以下權限：\n1. 進入「應用程式與通知」\n2. 選擇 ORVIA → 權限\n3. 啟用「附近裝置、藍牙」與「定位」';

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

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsSectionAccount => '帳號';

  @override
  String get settingsChangeName => '修改名稱';

  @override
  String get settingsChangeNameHint => '請輸入顯示名稱';

  @override
  String get settingsChangePassword => '修改密碼';

  @override
  String get settingsCurrentPassword => '目前密碼';

  @override
  String get settingsNewPassword => '新密碼';

  @override
  String get settingsConfirmNewPassword => '確認新密碼';

  @override
  String get settingsCurrentPasswordRequired => '請輸入目前密碼';

  @override
  String get settingsConfirmChange => '確認修改';

  @override
  String get settingsPasswordChanged => '密碼已修改';

  @override
  String get settingsSetPassword => '設定密碼';

  @override
  String get settingsSetPasswordDesc => '設定密碼後也可用 Email 登入';

  @override
  String get settingsPasswordSet => '密碼已設定';

  @override
  String get settingsGoogleLogin => 'Google 登入';

  @override
  String get settingsGoogleLinked => '已綁定';

  @override
  String get settingsGoogleNotLinked => '尚未綁定，點擊連結 Google 帳號';

  @override
  String get settingsAppleLogin => 'Apple 登入';

  @override
  String get settingsAppleLinked => '已綁定';

  @override
  String get settingsAppleNotLinked => '尚未綁定，點擊連結 Apple 帳號';

  @override
  String get settingsAppleCredentialFailed => '無法取得 Apple 憑證，請重試';

  @override
  String get settingsAppleLinkFailed => 'Apple 綁定失敗，請稍後再試';

  @override
  String get settingsSectionAnalysis => '分析偏好';

  @override
  String get settingsAnalysisQuality => '完整分析輸出品質';

  @override
  String get settingsQualityHint => '選擇後將作為預設值，下次分析自動套用';

  @override
  String get settingsApply => '套用';

  @override
  String settingsQualityUpdated(String quality) {
    return '輸出品質已更新為「$quality」';
  }

  @override
  String get settingsSectionSubscription => '訂閱';

  @override
  String get settingsViewSubscription => '查看訂閱方案';

  @override
  String get settingsSectionGeneral => '一般';

  @override
  String get settingsLanguage => '語言 / Language';

  @override
  String get settingsTheme => '外觀主題';

  @override
  String get settingsThemeSystem => '跟隨系統';

  @override
  String get settingsThemeLight => '日間模式';

  @override
  String get settingsThemeDark => '夜間模式';

  @override
  String get settingsCheckUpdate => '檢查更新';

  @override
  String get settingsAnalytics => '使用統計追蹤';

  @override
  String get settingsAnalyticsDesc => '匿名使用統計，協助改善 App 體驗';

  @override
  String get settingsPrivacyPolicy => '隱私權政策';

  @override
  String get settingsTermsOfService => '使用條款';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsPrivacyOpenFailed => '無法開啟隱私政策頁面，請稍後再試';

  @override
  String get settingsVersionCopied => '已複製版本';

  @override
  String settingsAlreadyLatest(String version) {
    return '已是最新版本 v$version';
  }

  @override
  String get settingsUpdateCheckFailed => '檢查更新失敗，請稍後再試';

  @override
  String get settingsConfirmLogout => '確定登出？';

  @override
  String get settingsLogoutWarning => '登出後需重新登入才能使用雲端功能。';

  @override
  String get commonContinue => '繼續';

  @override
  String get settingsDeleteAccount => '刪除帳號';

  @override
  String get settingsDeleteAccountWarning =>
      '刪除帳號將永久移除你的個人資料、訂閱與分析紀錄，且無法復原。此操作不會自動退款，訂閱請另於 App Store／Google Play 取消。確定要繼續嗎？';

  @override
  String get settingsDeleteAccountConfirmTitle => '最後確認';

  @override
  String get settingsDeleteAccountConfirmHint => '請輸入「DELETE」以確認永久刪除帳號。';

  @override
  String get settingsDeleteAccountFailed => '刪除帳號失敗，請稍後再試或聯絡客服。';

  @override
  String get settingsNameUpdated => '名稱已更新';

  @override
  String get settingsPickFromGallery => '從相簿選擇';

  @override
  String get settingsRemoveAvatar => '移除大頭貼';

  @override
  String get homeTodayOverview => '今日概況';

  @override
  String homeHi(String name) {
    return '嗨，$name 👋';
  }

  @override
  String get homeRounds => '練習輪次';

  @override
  String get homePractices => '練習次數';

  @override
  String get homeTodayGoodRate => '今日好球率';

  @override
  String homeGoodTimes(int count) {
    return '好球 $count 次';
  }

  @override
  String homeBadTimes(int count) {
    return '壞球 $count 次';
  }

  @override
  String get homeTodayPosture => '今日姿勢分析';

  @override
  String get homeTopSpeed => '最佳速度';

  @override
  String get homeSweetSpot => '甜蜜點';

  @override
  String get homeCrispness => '清脆度';

  @override
  String get homeAnnouncements => '公告欄';

  @override
  String get homeRewardBalls => '獎勵球數';

  @override
  String get homeGreetingQuestion => '今天的揮桿目標，準備開始了嗎？';

  @override
  String get homeTodayQuota => '今日用量';

  @override
  String homeQuotaBalls(int used, int total) {
    return '$used / $total 球';
  }

  @override
  String get homeHitAnalysis => '擊球分析';

  @override
  String get homeHitRecordsLabel => '筆擊球紀錄';

  @override
  String homeImprovedVsAvg(String pct) {
    return '持續進步中！本次表現較平均提升 $pct%。';
  }

  @override
  String get homeTrainingFocus => '訓練重點';

  @override
  String get homeViewNow => '立刻查看';

  @override
  String get homeNoShotsToday => '今天還沒有擊球紀錄，去錄一桿吧！';

  @override
  String get homeEmptyHint => '錄下第一桿，開始累積你的數據';

  @override
  String get weekdayMon => '週一';

  @override
  String get weekdayTue => '週二';

  @override
  String get weekdayWed => '週三';

  @override
  String get weekdayThu => '週四';

  @override
  String get weekdayFri => '週五';

  @override
  String get weekdaySat => '週六';

  @override
  String get weekdaySun => '週日';

  @override
  String get todayTitleToday => '今日概況';

  @override
  String get todayTitleHistory => '歷史概況';

  @override
  String get todayLoadFailed => '載入失敗，請下拉重新整理';

  @override
  String get todaySweetSpotHit => '甜蜜點命中';

  @override
  String get todayCrispness => '聲音清脆度';

  @override
  String get todayTopSpeed => '最佳速度';

  @override
  String get todayNoRecord => '今天還沒有練習記錄';

  @override
  String get todayNoRecordDate => '這天沒有練習記錄';

  @override
  String get todayGoRecord => '去錄一支揮桿吧！';

  @override
  String get todayPostureToday => '今日姿勢分析';

  @override
  String get todayPosture => '姿勢分析';

  @override
  String get annBoardTitle => '公告欄';

  @override
  String annUnreadCount(int count) {
    return '$count 則未讀';
  }

  @override
  String get annAllAnnouncements => '所有公告';

  @override
  String get annMarkAllRead => '全部已讀';

  @override
  String get annRefresh => '重新整理';

  @override
  String get annLoadFailed => '載入失敗，請下拉重試';

  @override
  String annMinutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String annHoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String annDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get annDetailTitle => '公告詳情';

  @override
  String annExpiresAt(String date) {
    return '有效期限至 $date';
  }

  @override
  String get annEmpty => '目前沒有公告';

  @override
  String get annEmptySubtitle => '新公告將會顯示在這裡';

  @override
  String get updateNotes => '更新內容';

  @override
  String get updateForcedWarning => '此版本已停止支援，請更新後繼續使用';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateRemindLater => '稍後提醒';

  @override
  String get updateDontRemind => '不再提醒';

  @override
  String get updateCannotOpenStore => '無法開啟商店頁面，請手動前往更新';

  @override
  String get updateRequiredTitle => '必要更新';

  @override
  String get updateRequiredSubtitle => '請更新後繼續使用 ORVIA';

  @override
  String get updateFoundTitle => '發現新版本';

  @override
  String get updateFoundSubtitle => '建議更新以獲得最佳體驗';

  @override
  String get updateCurrentVersion => '目前版本';

  @override
  String get updateLatestVersion => '最新版本';

  @override
  String get upgradePageTitle => '升級您的方案';

  @override
  String get upgradePageSubtitle => '解鎖更多揮桿分析功能，精進您的球技';

  @override
  String get upgradeFullComparison => '完整功能比較';

  @override
  String get upgradeFeatureColumn => '功能';

  @override
  String upgradeSubscribePlan(String plan) {
    return '升級 $plan 方案';
  }

  @override
  String get upgradeSelectPayment => '選擇付款方式';

  @override
  String get upgradeApplePayFailed => 'Apple Pay 設定載入失敗';

  @override
  String get upgradeGooglePayFailed => 'Google Pay 設定載入失敗';

  @override
  String get upgradePaymentFailed => '付款驗證失敗，請稍後重試';

  @override
  String get upgradeSuccessMsg => '升級成功';

  @override
  String get upgradeAlreadyFree => '您目前使用的已是免費方案';

  @override
  String get learningTitle => '揮桿學習';

  @override
  String get learningMoreComing => '更多課程陸續更新中';

  @override
  String get learningVideoComingSoon => '示範影片待補充，先提供重點與標記供對照學習。';

  @override
  String get learningKeyMarkers => '關鍵標記';

  @override
  String get myFeedbackTitle => '我的回饋';

  @override
  String get myFeedbackSubtitle => '已送出的回饋與官方回覆';

  @override
  String get myFeedbackEntry => '查看我的回饋';

  @override
  String get myFeedbackEmpty => '尚無回饋紀錄';

  @override
  String get myFeedbackLoadFailed => '載入失敗，請下拉重試';

  @override
  String get myFeedbackAllLoaded => '已載入全部回饋';

  @override
  String get myFeedbackTypeBug => '問題回報';

  @override
  String get myFeedbackTypeFeature => '功能建議';

  @override
  String get myFeedbackTypeOther => '其他';

  @override
  String get myFeedbackAdminReply => '官方回覆';

  @override
  String get myFeedbackNoReply => '等待回覆中';

  @override
  String get myFeedbackAttachedVideo => '已附影片';

  @override
  String get onboardingSkip => '跳過';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingStart => '開始使用';

  @override
  String get onboardingRecordTitle => '錄製你的揮桿';

  @override
  String get onboardingRecordDesc => '點選底部中央的錄製按鈕開始錄影，ORVIA 會邊錄邊自動偵測每一次擊球。';

  @override
  String get onboardingClipTitle => '自動切片';

  @override
  String get onboardingClipDesc => '錄影結束後，每一桿會自動切成 5 秒片段，可在歷史頁逐段檢查。';

  @override
  String get onboardingAiTitle => 'AI 分析';

  @override
  String get onboardingAiDesc => '將切片送交 AI 教練，分析姿勢、8 階段揮桿與球體軌跡。';

  @override
  String get onboardingBallsTitle => '球數與獎勵';

  @override
  String get onboardingBallsDesc => '分析需要消耗球數。每天有免費額度，也可透過看廣告、提交回饋或邀請好友賺取更多。';

  @override
  String get settingsReplayTutorial => '重看教學引導';

  @override
  String recFrameCount(int count) {
    return '$count 幀';
  }

  @override
  String recDetectedShots(int count) {
    return '已偵測 $count 桿';
  }

  @override
  String recImpactShot(int number) {
    return '第 $number 桿';
  }

  @override
  String get privacySettingsTitle => '隱私與分析';

  @override
  String get privacySectionDataCollection => '資料蒐集說明';

  @override
  String get privacyDataCollectionDesc =>
      '你的影片與分析資料只會在你主動操作時上傳——AI 分析、分享、上傳獎勵或回饋附件。ORVIA 沒有背景上傳，也沒有隱藏的遙測。';

  @override
  String get privacySectionPolicies => '政策文件';

  @override
  String get privacySectionUpload => '分析資料上傳';

  @override
  String get privacyUploadDesc =>
      '你可以自願提交揮桿影片與感測 CSV 資料，協助改善揮桿偵測模型。每筆提交都會人工審核，通過後發放獎勵球。';

  @override
  String get privacyUploadStatusEntry => '查看我的上傳審核狀態';

  @override
  String get privacySectionAccount => '帳號';

  @override
  String get privacyDeleteAccountSubtitle => '軟刪除：將無法再登入，資料會被匿名化';

  @override
  String get rewardSubtitle => '完成任務累積球數，兌換分析次數';

  @override
  String get historyFilterReset => '重置';

  @override
  String aiCoachUpgradeFailed(String error) {
    return '升級失敗: $error';
  }

  @override
  String get aiCoachQuotaExhaustedTitle => '今日球數已用完';

  @override
  String aiCoachQuotaExhaustedBody(int todayUsed, int totalLimit) {
    return '今日已使用 $todayUsed 次，已達上限 $totalLimit 次。\n\n明天可繼續使用，或升級方案取得更多次數。';
  }

  @override
  String get aiCoachGotIt => '知道了';

  @override
  String get aiCoachAnalysisFailed => '分析失敗，請重試';

  @override
  String get aiCoachStatusPending => '準備中...';

  @override
  String get aiCoachStatusQueued => '等待分析佇列...';

  @override
  String get aiCoachStatusProcessing => 'AI 教練正在分析影片...';

  @override
  String get aiCoachStatusIdle => '等待 AI 教練分析...';

  @override
  String get aiCoachStatusConnecting => '連接中...';

  @override
  String get aiCoachLoadingHint => '通常需要 10~30 秒';

  @override
  String get aiCoachPostureAnalysisDone => '已完成錯誤姿勢分析';

  @override
  String get aiCoachSubmitting => '送出中...';

  @override
  String get aiCoachStartAnalysis => '開始 AI 教練分析';

  @override
  String get aiCoachAnalysisHint => '* AI 教練將依據姿勢分析結果，提供詳細教練評語與訓練建議';

  @override
  String get aiCoachEvidence => '依據';

  @override
  String get aiCoachSeverityHigh => '嚴重';

  @override
  String get aiCoachSeverityMedium => '中等';

  @override
  String get aiCoachSeverityLow => '輕微';

  @override
  String get aiCoachImpactPremiumSweetSpot => '高品質甜蜜點';

  @override
  String get aiCoachImpactSweetSpot => '甜蜜點';

  @override
  String get aiCoachImpactNearSweetSpot => '接近甜蜜點';

  @override
  String get aiCoachImpactFair => '普通';

  @override
  String get aiCoachImpactPoor => '擊球偏虛';

  @override
  String get aiCoachImpactQualityTitle => '擊球品質（音訊）';

  @override
  String aiCoachImpactFeatureCount(int passCount, int totalFeatures) {
    return '$passCount / $totalFeatures 項特徵符合甜蜜點範圍';
  }

  @override
  String get aiCoachFeedbackTitle => '教練評語';

  @override
  String get aiCoachPracticeTitle => '訓練建議';

  @override
  String get aiCoachNextGoalTitle => '下次練習目標';

  @override
  String get aiCoachReanalyzeSubmitting => '提交重新分析中...';

  @override
  String aiCoachReanalyzeFailed(String error) {
    return '重新分析失敗: $error';
  }

  @override
  String get ballTuneTitle => '球軌跡調參';

  @override
  String get ballTuneHudInit => '初始化中…';

  @override
  String get ballTuneHudDetecting => '偵測中…';

  @override
  String get ballTuneHudBlobFailed => 'blob 抽取失敗';

  @override
  String ballTuneRoiBadge(String r, String margin) {
    return 'ROI r=${r}px  margin=$margin';
  }

  @override
  String get ballTuneRoiToggleTooltip => 'ROI 疊圖開關';

  @override
  String get ballTuneSectionRealtime => '即時（拉了立刻重畫）';

  @override
  String get ballTuneSliderResidual => '品質閘門 殘差上限';

  @override
  String get ballTuneSliderP1MaxDist => 'P1 最遠距離';

  @override
  String get ballTuneRoiMaskSection => 'ROI / 遮罩（可直接在預覽上拖拉）';

  @override
  String get ballTuneSliderRoiRadius => 'ROI 半徑';

  @override
  String get ballTuneSliderGolferMargin => '球員遮罩 margin';

  @override
  String get ballTuneSliderRoiMissScale => 'ROI miss 大擴張×';

  @override
  String get ballTuneSliderRoiRadiusMax => 'ROI 半徑上限';

  @override
  String get ballTuneSliderStepMaxPost => '擊球後 step 上限';

  @override
  String get ballTuneSliderPredMaxPost => '擊球後 pred 上限';

  @override
  String get ballTuneSliderMissPatiencePost => '擊球後 miss 容忍';

  @override
  String get ballTuneSectionReextract => '重抽（改完按下方按鈕）';

  @override
  String get ballTuneSliderDiffThresh => 'diffThresh 幀差門檻';

  @override
  String get ballTuneRedetectButton => '重新偵測（套用 diffThresh）';

  @override
  String clipCandTitle(int count) {
    return '確認擊球片段（$count 個候選）';
  }

  @override
  String get clipCandTapToPreview => '點候選可預覽';

  @override
  String get clipCandRangeTooShort => '切片區段需至少 0.5 秒（終點需在起點之後）';

  @override
  String clipCandConfirmClip(int count) {
    return '切出 $count 個片段';
  }

  @override
  String clipCandManualHint(String start) {
    return '起點 $start → 拖到終點後按「加入區段」';
  }

  @override
  String get clipCandManualPrompt => '自由切片：拖時間軸到起點';

  @override
  String get clipCandSetStart => '設為起點';

  @override
  String get clipCandReset => '重設';

  @override
  String get clipCandAddRange => '加入區段';

  @override
  String clipCandCandidateLabel(int index, String time) {
    return '候選 $index ・ $time';
  }

  @override
  String get clipCandFromAudio => '擊球聲偵測';

  @override
  String get clipCandFromMotion => '錄影中動作偵測';

  @override
  String clipCandManualRangeLabel(String start, String end) {
    return '自訂區段 ・ $start - $end';
  }

  @override
  String clipCandRangeDuration(String seconds) {
    return '長度 $seconds 秒';
  }

  @override
  String get compareLoadingVideos => '載入影片中…';

  @override
  String get highlightTitle => 'Highlight 預覽';

  @override
  String get highlightShareSystem => '系統分享';

  @override
  String get highlightExportDebug => '匯出 debug';

  @override
  String get highlightShareDebug => '分享 debug';

  @override
  String get highlightShareText => '我的揮桿 Highlight';

  @override
  String get highlightDebugFileError => '無法建立 debug 檔';

  @override
  String get highlightStoragePermissionRequired => '需要儲存權限以匯出至下載資料夾';

  @override
  String get highlightDownloadsDirNotFound => '找不到下載資料夾';

  @override
  String highlightSavedTo(String path) {
    return '已另存至：$path';
  }

  @override
  String highlightExportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String historySubtitle(int total, int good, int bad) {
    return '共 $total 筆 · 好球 $good · 壞球 $bad';
  }

  @override
  String get historySearchHint => '搜尋錄影…';

  @override
  String historySearchResult(int count, int total) {
    return '搜尋結果 $count / $total 筆';
  }

  @override
  String get historySearchNoResult => '找不到相符的紀錄';

  @override
  String historySearchNoResultHint(Object query) {
    return '沒有符合「$query」的結果';
  }

  @override
  String get historySearchClear => '清除搜尋';

  @override
  String get historyEmptyTitle => '還沒有任何錄影';

  @override
  String get historyEmptySubtitle => '開始錄製揮桿來累積紀錄吧';

  @override
  String get historyFilterLabelSort => '排序';

  @override
  String get historyFilterLabelDate => '日期';

  @override
  String get historyFilterLabelVideo => '影片';

  @override
  String get historyFilterLabelGoodBad => '評級';

  @override
  String get historyFilterLabelAnalysis => '分析';

  @override
  String get historyFilterLabelClip => '切片';

  @override
  String get historyFilterLabelAI => 'AI';

  @override
  String get historyFilterLabelPosture => '姿勢';

  @override
  String get historyFilterAll => '全部';

  @override
  String get historyFilterToday => '今天';

  @override
  String get historyFilterWeek => '本週';

  @override
  String get historyFilterMonth => '本月';

  @override
  String get historyFilterCustomDate => '自訂日期範圍';

  @override
  String get historyFilterSort => '排序方式';

  @override
  String get historyFilterGood => '優';

  @override
  String get historyFilterBad => '劣';

  @override
  String get historyFilterAnalyzed => '已分析';

  @override
  String get historyFilterNotAnalyzed => '未分析';

  @override
  String get historyFilterAiAnalyzed => 'AI 已分析';

  @override
  String get historyFilterAiNotAnalyzed => 'AI 未分析';

  @override
  String get historyFilterClipped => '已切片';

  @override
  String get historyFilterNotClipped => '未切片';

  @override
  String get historyFilterLongVideo => '長影片';

  @override
  String get historyFilterShortVideo => '短影片';

  @override
  String get historySortDate => '時間';

  @override
  String get historySortPeakSpeed => '最佳速度';

  @override
  String get historySortClipTime => '片段時間';

  @override
  String get historyDateRangeHelp => '選擇日期範圍';

  @override
  String get historyDeleteTitle => '刪除錄影';

  @override
  String historyDeleteClipConfirm(Object title) {
    return '確定刪除切片「$title」？';
  }

  @override
  String historyDeleteVideoConfirm(Object title) {
    return '確定刪除錄影「$title」？';
  }

  @override
  String historyDeleteVideoWithClipsConfirm(Object title, Object count) {
    return '確定刪除「$title」及其 $count 個切片？';
  }

  @override
  String historyDeletedSnack(Object name) {
    return '已刪除 $name';
  }

  @override
  String historyDeletedWithClipsSnack(Object name, Object count) {
    return '已刪除 $name 及 $count 個切片';
  }

  @override
  String get historyRenameTitle => '重新命名錄影';

  @override
  String get historyRenameClipTitle => '重新命名切片';

  @override
  String get historyRenameLabel => '新名稱';

  @override
  String get historyRenameHelper => '留空以還原預設名稱';

  @override
  String get historyRenameValidation => '名稱不能為空白';

  @override
  String historyRenamedSnack(Object name) {
    return '已重新命名為「$name」';
  }

  @override
  String historyRenameResetSnack(Object name) {
    return '已還原預設名稱「$name」';
  }

  @override
  String historyFileNotFound(Object name) {
    return '找不到檔案：$name';
  }

  @override
  String get historyClipFileNotExist => '切片檔案不存在，請重新偵測';

  @override
  String get historyAlreadyClipped => '此影片已有切片，重新偵測將取代現有切片。';

  @override
  String get historyProgressPreparingSkeleton => '準備骨架分析…';

  @override
  String get historyProgressPreparing => '準備中…';

  @override
  String get historyDetectingShots => '偵測揮桿中';

  @override
  String get historyCancelledDetection => '已取消偵測';

  @override
  String get historyCancelledAnalysis => '已取消分析';

  @override
  String get historyV2NoAudio => '未找到音訊軌，無法使用音訊偵測模式';

  @override
  String get historyV3NoShot => '骨架分析未偵測到任何揮桿';

  @override
  String get historyV3NoValidHit => '過濾後無有效擊球點';

  @override
  String get historyNoShotDetected => '未偵測到揮桿';

  @override
  String get historyClipFailed => '切片生成失敗';

  @override
  String historyClipsGenerated(Object count) {
    return '已生成 $count 個切片';
  }

  @override
  String historyClipsGeneratedBg(Object count) {
    return '已將 $count 個切片存入紀錄';
  }

  @override
  String historyDetectFailed(Object error) {
    return '偵測失敗：$error';
  }

  @override
  String get historyLongVideoTitle => '長影片提示';

  @override
  String historyLongVideoContent(Object seconds) {
    return '此影片長達 $seconds 秒，完整分析可能需要較長時間。';
  }

  @override
  String get historyContinueAnalysis => '繼續分析';

  @override
  String get historyFullAnalysisTitle => '分析中';

  @override
  String historyInvalidDuration(Object seconds) {
    return '影片時長無效：$seconds 秒';
  }

  @override
  String historyAnalysisComplete(Object audio) {
    return '分析完成$audio';
  }

  @override
  String historyAnalysisFailed(Object error) {
    return '分析失敗：$error';
  }

  @override
  String get historyQuotaExhaustedTitle => '今日配額已用盡';

  @override
  String historyQuotaExhaustedContent(Object used, Object total) {
    return '今日已使用 $used/$total 次，升級方案以繼續使用。';
  }

  @override
  String get historyGotIt => '知道了';

  @override
  String get historyAiAnalysisConfirmTitle => 'AI 分析';

  @override
  String get historyAiAnalysisConfirmDesc => '提交此揮桿進行 AI 分析，將消耗 1 顆球。';

  @override
  String get historyAiAnalysisConfirmBtn => '開始分析';

  @override
  String historyAiSubmitFailed(Object error) {
    return '提交失敗：$error';
  }

  @override
  String get historyNoOtherVideoToCompare => '沒有其他影片可供比較';

  @override
  String get historyCompareTitle => '比較揮桿';

  @override
  String historyCompareSubtitle(Object title) {
    return '選擇要與「$title」比較的影片';
  }

  @override
  String get historyPhasesJsonMissing => '找不到 phases.json，請重新分析';

  @override
  String get historyPhasesJsonInvalid => 'phases.json 格式錯誤，請重新分析';

  @override
  String get historySelectAiModeTitle => '選擇 AI 模式';

  @override
  String get historyAiModeV1Title => '基礎 (V1)';

  @override
  String get historyAiModeV1Desc => '音訊峰值偵測';

  @override
  String get historyAiModeV2Title => '標準 (V2)';

  @override
  String get historyAiModeV2Desc => '音訊 + 骨架混合';

  @override
  String get historyAiModeV3Title => '進階 (V3)';

  @override
  String get historyAiModeV3Desc => '骨架主導加音訊精修';

  @override
  String get historySelectDetectModeTitle => '選擇偵測模式';

  @override
  String get historyDetectV1Title => '骨架偵測 (V1)';

  @override
  String get historyDetectV1Desc => 'MediaPipe 姿勢估計';

  @override
  String get historyDetectBadgePrecise => '精準';

  @override
  String get historyDetectV1Time => '~10 秒';

  @override
  String get historyDetectV2Title => '音訊偵測 (V2)';

  @override
  String get historyDetectV2Desc => '快速音訊峰值偵測';

  @override
  String get historyDetectBadgeFast => '快速';

  @override
  String get historyDetectV2Time => '~30 秒';

  @override
  String get historyDetectV3Title => '混合偵測 (V3)';

  @override
  String get historyDetectV3Desc => '骨架主導加音訊精修';

  @override
  String get historyDetectBadgeBalanced => '均衡';

  @override
  String get historyDetectV3Time => '~45 秒';

  @override
  String get historySkipToday => '今日不再提醒';

  @override
  String get historyStartDetect => '開始偵測';

  @override
  String get historySelectQualityTitle => '選擇匯出品質';

  @override
  String get historyStartAnalysis => '開始分析';

  @override
  String get historyActionDetect => '偵測桿數';

  @override
  String get historyActionAiAnalysis => 'AI 分析';

  @override
  String get historyActionFullAnalysis => '完整分析';

  @override
  String get historyActionChart => '統計圖表';

  @override
  String get historyActionPlay => '播放';

  @override
  String get historyActionExpand => '展開切片';

  @override
  String get historyActionCollapse => '收合切片';

  @override
  String get historyMenuRename => '重新命名';

  @override
  String get historyMenuAddNote => '新增備註';

  @override
  String get historyMenuEditNote => '編輯備註';

  @override
  String get historyMenuShare => '分享';

  @override
  String get historyMenuDownload => '下載';

  @override
  String get historyMenuDownloading => '下載中…';

  @override
  String get historyMenuCompare => '比較';

  @override
  String historyMenuUploadReward(int balls) {
    return '上傳獎勵 +$balls 球';
  }

  @override
  String get historyMenuUploaded => '已上傳';

  @override
  String get historyMenuAnalyzing => '分析中…';

  @override
  String get historyMenuDeleteVideo => '刪除影片';

  @override
  String get historyMoreActions => '更多操作';

  @override
  String get historyBadgeNoAudio => '無音訊';

  @override
  String get historyBadgeAnalyzed => '已分析';

  @override
  String get historySweetSpot => '甜蜜點';

  @override
  String get historySweetSpotHit => '命中';

  @override
  String get historySweetSpotMiss => '未命中';

  @override
  String get historyHitSummary => '擊球統計';

  @override
  String historyClipDefaultName(Object index) {
    return '第 $index 桿';
  }

  @override
  String historyClipHitAt(Object time) {
    return '擊球 @ $time';
  }

  @override
  String historyClipRange(Object start, Object end) {
    return '片段 $start–$end 秒';
  }

  @override
  String historyRoundLabel(Object index) {
    return '第 $index 輪';
  }

  @override
  String historyDurationLine(Object time, Object seconds) {
    return '$time · $seconds 秒';
  }

  @override
  String historyImportedFrom(Object name) {
    return '來自 $name';
  }

  @override
  String get historyNoteDialogTitle => '影片備註';

  @override
  String get historyNoteHint => '記下練習心得、場地、使用桿型…';

  @override
  String get historyNoteHelper => '可留空以清除備註';

  @override
  String get historySaveLocationTitle => '選擇儲存位置';

  @override
  String get historySaveLocationDownloads => '下載資料夾';

  @override
  String get historySaveLocationDownloadsSub => '儲存到系統預設下載位置';

  @override
  String get historySaveLocationPick => '選擇資料夾';

  @override
  String get historySaveLocationPickSub => '自訂儲存位置';

  @override
  String get historyDownloadVersionTitle => '選擇下載版本';

  @override
  String historyExportSaved(Object label) {
    return '「$label」已儲存 ✅';
  }

  @override
  String historyExportSavedPhotos(Object label) {
    return '「$label」已儲存到相機膠卷 ✅';
  }

  @override
  String historyExportFailed(Object detail) {
    return '下載失敗：$detail';
  }

  @override
  String get historyUploadRewardTitle => '上傳分析資料';

  @override
  String historyUploadRewardContent(Object title, Object balls) {
    return '將上傳「$title」的分析資料，用於改善揮桿偵測模型。\n\n上傳後需經審核，審核通過將發放 +$balls 球獎勵。\n\n確定上傳？';
  }

  @override
  String get historyUploadSubmit => '上傳送審';

  @override
  String get historyUploadingProgress => '上傳影片與分析資料中…';

  @override
  String historyUploadFailed(Object error) {
    return '上傳失敗：$error';
  }

  @override
  String get historyUploadSubmitFailed =>
      '送審未成功：此影片可能已提交過（含審核未通過者不可重送），或網路異常請稍後再試';

  @override
  String historyUploadReviewPending(Object balls) {
    return '已送出審核，通過後將發放 +$balls 球';
  }

  @override
  String get hitsSummaryEmpty => '尚未偵測到任何揮桿';

  @override
  String hitsSummaryHitIndex(int index) {
    return '第 $index 桿';
  }

  @override
  String get hitsSummaryPeak => '峰值';

  @override
  String get hitsSummaryDuration => '時長';

  @override
  String get hitsSummaryStart => '開始';

  @override
  String get hitsSummaryEnd => '結束';

  @override
  String hitsSummaryDetectFrom(String source) {
    return '偵測來源：$source';
  }

  @override
  String get hitsSummaryTitle => '揮桿摘要';

  @override
  String hitsSummaryCount(int count) {
    return '共 $count 桿';
  }

  @override
  String get homeCurrentSuggestions => '目前訓練建議';

  @override
  String homeNextGoal(String goal) {
    return '下次目標：$goal';
  }

  @override
  String get authInviteCodeOptional => '選填';

  @override
  String get authInviteCodeLabel => '邀請碼';

  @override
  String get authInviteCodeHint => '如有好友邀請碼，請在此填寫';

  @override
  String get authInviteCodeHelper => '填寫邀請碼，雙方各獲得 +5 球獎勵';

  @override
  String get devTestAccounts => '測試帳號';

  @override
  String get devTestPassword => '密碼：Test1234!';

  @override
  String get forgotTitle => '忘記密碼';

  @override
  String get forgotEnterCodeTitle => '輸入驗證碼';

  @override
  String get forgotEmailSubtitle => '輸入您的 Email，我們將寄送 6 位數驗證碼';

  @override
  String forgotCodeSentSubtitle(String email) {
    return '驗證碼已寄至 $email';
  }

  @override
  String get forgotSixDigitCodeLabel => '6 位驗證碼';

  @override
  String get forgotNewPasswordLabel => '新密碼';

  @override
  String get forgotNewPasswordHint => '至少 8 位，含大寫、小寫、數字';

  @override
  String get forgotConfirmPasswordLabel => '確認新密碼';

  @override
  String get forgotSendCodeButton => '寄送驗證碼';

  @override
  String get forgotConfirmResetButton => '確認重設密碼';

  @override
  String get forgotReEnterEmail => '重新輸入 Email';

  @override
  String get forgotEnterValidEmail => '請輸入有效的 Email';

  @override
  String get forgotSendFailed => '寄送失敗';

  @override
  String get forgotNetworkError => '網路錯誤，請稍後再試';

  @override
  String get forgotEnterSixDigitCode => '請輸入 6 位數驗證碼';

  @override
  String get forgotPasswordComplexity => '密碼須至少 8 位且包含大寫、小寫及數字';

  @override
  String get forgotPasswordMismatch => '兩次密碼不一致';

  @override
  String get forgotResetSuccess => '密碼已重設，請用新密碼登入';

  @override
  String get forgotResetFailed => '重設失敗';

  @override
  String get playerTitle => '影片查看';

  @override
  String get playerNoteAdd => '新增備註';

  @override
  String get playerNoteEdit => '編輯備註';

  @override
  String get playerNoteCleared => '已清除備註';

  @override
  String get playerNoteSaved => '已儲存備註';

  @override
  String get playerVideoNotFound => '找不到影片檔案';

  @override
  String get playerVideoLoadFailed => '影片載入失敗';

  @override
  String get playerSkeletonNotFound => '骨架資料不存在';

  @override
  String get playerOverlaySkeleton => '骨架';

  @override
  String get playerOverlayTrajectory => '軌跡';

  @override
  String get playerOverlayEffect => '特效';

  @override
  String get playerTrajectoryTuning => '軌跡調參';

  @override
  String playerShotLabel(int index, String time) {
    return '第$index球 $time';
  }

  @override
  String get playerStatsEmpty => '尚無統計資料（需軌跡或階段分析）';

  @override
  String get playerStatLaunchAngle => '發射角';

  @override
  String get playerStatTempo => '節奏 (上桿:下桿)';

  @override
  String get playerStatBackDownswing => '上桿 / 下桿';

  @override
  String get playerStatFlightTime => '入鏡飛行';

  @override
  String get playerChartEmpty => '尚無圖表資料，請先完成分析';

  @override
  String get playerChartNoData => '無資料';

  @override
  String get playerChartAudioEmpty => '聲音峰值 無資料';

  @override
  String get playerChartWristYEmpty => '手腕 Y 無資料';

  @override
  String get playerChartSpeedEmpty => '速度 無資料';

  @override
  String get playerChartTabAudio => '聲音峰值';

  @override
  String get playerChartTabWristY => '手腕 Y';

  @override
  String get playerChartTabSpeed => '速度';

  @override
  String get playerChartTabPosture => '姿勢';

  @override
  String get playerChartTabAudioFeature => '音頻特徵';

  @override
  String get playerLoadDetailScore => '載入詳細分數';

  @override
  String get playerPostureEmpty => '尚無姿勢分析，請先完成分析';

  @override
  String playerAudioPassCount(int count) {
    return '$count / 5 項通過';
  }

  @override
  String get playerAudioEmpty => '尚無音頻分析';

  @override
  String playerAiAnalysisFailed(String error) {
    return 'AI 分析失敗: $error';
  }

  @override
  String get playerAiNotStarted => '尚未進行 AI 教練分析';

  @override
  String get playerAiStartAnalysis => '開始分析';

  @override
  String get playerAiViewProgress => '查看進度';

  @override
  String get playerAiCoachTitle => 'AI 教練分析';

  @override
  String get playerAiPrimaryIssue => '主要問題';

  @override
  String get playerAiCoachFeedback => '教練評語';

  @override
  String get playerAiPracticeSuggestions => '訓練建議';

  @override
  String get playerAiNextGoal => '下次目標';

  @override
  String get playerAiReanalyze => '重新分析';

  @override
  String get playerAiViewDetail => '查看詳細';

  @override
  String get playerAiStatusPending => '準備中...';

  @override
  String get playerAiStatusQueued => '等待分析佇列...';

  @override
  String get playerAiStatusProcessing => 'AI 教練分析中...';

  @override
  String get playerAiStatusAnalyzing => '分析中...';

  @override
  String get playerSeverityHigh => '嚴重';

  @override
  String get playerSeverityMedium => '中等';

  @override
  String get playerSeverityLow => '輕微';

  @override
  String get playerHighlightPreview => '精彩片段預覽';

  @override
  String get playerSweetSpotHit => '甜蜜點命中';

  @override
  String get playerSweetSpot => '甜蜜點';

  @override
  String get playerThinShot => '偏虛球';

  @override
  String playerAudioPassCountBadge(int count) {
    return '$count/5 特徵符合';
  }

  @override
  String get playerNoteDialogTitle => '影片備註';

  @override
  String get playerNoteHint => '記下練習心得、場地、使用桿型…';

  @override
  String get playerNoteHelper => '可留空以清除備註';

  @override
  String get playerPhaseAddress => '準備';

  @override
  String get playerPhaseTakeaway => '起桿';

  @override
  String get playerPhaseBackswing => '上桿';

  @override
  String get playerPhaseTop => '頂點';

  @override
  String get playerPhaseDownswing => '下桿';

  @override
  String get playerPhaseImpact => '擊球';

  @override
  String get clipLegendStart => '開始';

  @override
  String get clipLegendEnd => '結束';

  @override
  String get playerPhaseFollowthrough => '送桿';

  @override
  String get playerPhaseFinish => '收桿';

  @override
  String get postureTitle => '姿勢分析';

  @override
  String get postureNoData => '尚無 AI 分析資料';

  @override
  String get profileSubtitle => '調整個人資訊以獲得更精準的揮桿分析，完成後記得儲存。';

  @override
  String get profileAvatarHint => '設定個人頭像讓教練更容易識別';

  @override
  String get profileAvatarSaveFailed => '儲存頭像失敗，請稍後再試。';

  @override
  String get profileDisplayNameLabel => '暱稱';

  @override
  String get profileDisplayNameHint => '輸入想在首頁顯示的名稱';

  @override
  String get profileDisplayNameRequired => '請輸入暱稱';

  @override
  String get profileEmailLabel => '電子郵件';

  @override
  String get profilePhoneLabel => '聯絡電話';

  @override
  String get profilePhoneHint => '例：0912-345-678';

  @override
  String get profileHandicapLabel => '差點';

  @override
  String get profileHandicapHint => '可填寫目前差點或目標數值';

  @override
  String get purchaseTestPanelTitle => '🧪 購買測試面板';

  @override
  String get purchaseTestSimulateSuccessMsg => '✅ 模擬購買成功！用戶已設置為高級用戶';

  @override
  String purchaseTestErrorMsg(String error) {
    return '❌ 錯誤: $error';
  }

  @override
  String get purchaseTestClearSuccessMsg => '🔄 已清除購買紀錄！用戶現在是普通用戶';

  @override
  String get purchaseTestPremiumStatusLabel => '高級用戶狀態: ';

  @override
  String get purchaseTestStatusPurchased => '✅ 已購買';

  @override
  String get purchaseTestStatusNotPurchased => '❌ 未購買';

  @override
  String purchaseTestPaymentMethod(String method) {
    return '支付方式: $method';
  }

  @override
  String get purchaseTestPaymentMethodNone => '無';

  @override
  String get purchaseTestSimulateBtn => '模擬購買成功';

  @override
  String get purchaseTestClearBtn => '清除購買';

  @override
  String get purchaseTestRefreshBtn => '刷新狀態';

  @override
  String get purchaseTestDialogTitle => '🧪 購買功能測試';

  @override
  String get recDetailDownloadVideo => '下載影片';

  @override
  String get exportCustomTitle => '自訂匯出';

  @override
  String get exportCustomSubtitle => '選擇要燒錄到影片上的元素';

  @override
  String get exportElementSkeleton => '骨架';

  @override
  String get exportElementSkeletonDesc => '揮桿姿勢關節骨架';

  @override
  String get exportElementTrajectory => '球軌跡';

  @override
  String get exportElementTrajectoryDesc => '擊球後球體飛行軌跡';

  @override
  String get exportElementGlow => '擊球光暈';

  @override
  String get exportElementGlowDesc => '擊球瞬間的擴散光圈';

  @override
  String get exportElementSweetSpot => '甜蜜點';

  @override
  String get exportElementSweetSpotDesc => '擊球品質光圈（金／藍／灰）';

  @override
  String get swingBothHands => '雙手判斷';

  @override
  String get swingBothHandsDesc => '雙手腕一起移動才算一次揮桿；其中一手被遮擋時自動改用另一手';

  @override
  String get exportNoOverlayMaterial => '此影片沒有可疊加的分析素材，將輸出原片。';

  @override
  String get exportWatermarkFree => '免費版成品將含 ORVIA 浮水印，升級可移除';

  @override
  String get exportWatermarkPaid => '已訂閱：成品不含浮水印';

  @override
  String get exportComposeAndDownload => '合成並下載';

  @override
  String get recDetailNoVideoFound => '找不到可下載的影片';

  @override
  String recDetailBurning(String label) {
    return '燒錄「$label」中…';
  }

  @override
  String get recDetailBurnFailed => '燒錄失敗，請稍後重試';

  @override
  String recDetailSavedToDownloads(String label) {
    return '「$label」已儲存到下載資料夾 ✅';
  }

  @override
  String recDetailSavedToPhotos(String label) {
    return '「$label」已儲存到相機膠卷 ✅';
  }

  @override
  String get recDetailSharedViaSheet => '已開啟分享 ✅';

  @override
  String recDetailDownloadFailed(String detail) {
    return '下載失敗：$detail';
  }

  @override
  String get recDetailSkeletonPreview => '骨架預覽';

  @override
  String get recDetailSkeletonLoadFailed => '骨架預覽載入失敗';

  @override
  String get recDetailAudioPeak => '聲音峰值';

  @override
  String get recDetailAudioPeakSubtitle => 'RMS dBFS';

  @override
  String get recDetailAudioPeakMissing => '需完成音頻分析';

  @override
  String get recDetailWristY => '手腕 Y';

  @override
  String get recDetailWristYSubtitle => '右手腕 Y 位置（像素）';

  @override
  String get recDetailPoseMissing => '需完成姿勢分析';

  @override
  String get recDetailSpeedSubtitle => '手腕移動速度（px/frame）';

  @override
  String get recDetailSpeedMissing => '速度';

  @override
  String get recDetailSweetSpot => '甜蜜點';

  @override
  String get recDetailOffCenter => '擊球偏虛';

  @override
  String get recDetailAudioFeaturesTitle => '音頻特徵分析';

  @override
  String recDetailFeaturePassCount(int count) {
    return '$count / 5 項特徵符合甜蜜點範圍';
  }

  @override
  String get recDetailAutoAnalyzing => '姿勢分析上傳中，請稍候…';

  @override
  String get recDetailOnnxTitle => 'ONNX 姿勢分析';

  @override
  String recDetailOnnxLoadFailed(String error) {
    return '載入失敗: $error';
  }

  @override
  String get recDetailOnnxNoResult => '尚無 ONNX 結果';

  @override
  String get recDetailOnnxNoScores => '無分數資料';

  @override
  String get recDetailSwingPhases => '揮桿階段';

  @override
  String get recDetailRegenerate => '重新生成';

  @override
  String get recDetailGeneratePhases => '生成階段';

  @override
  String get recDetailNoChartData => '尚無圖表資料';

  @override
  String get recDetailNoChartHint => '請先完成音頻分析與姿勢分析';

  @override
  String get recDetailLoadFailed => '載入失敗';

  @override
  String get recDetailSelectDownloadVersion => '選擇下載版本';

  @override
  String get recDetailOptLabelFull => '分析完整版';

  @override
  String get recDetailOptDescFull => '骨架 + 球軌跡';

  @override
  String get recDetailOptLabelSkeleton => '骨架版';

  @override
  String get recDetailOptDescSkeleton => '只含骨架 overlay';

  @override
  String get recDetailOptLabelClip => '原始片段';

  @override
  String get recDetailOptDescNoOverlay => '無任何 overlay';

  @override
  String get recDetailOptLabelRaw => '原始影片';

  @override
  String get recDetailOptLabelRawMov => '原始影片 (MOV)';

  @override
  String get recDetailOptDescRawMov => '原始 MOV 檔';

  @override
  String get recDetailPhaseAddress => '①準備';

  @override
  String get recDetailPhaseTakeaway => '②起桿';

  @override
  String get recDetailPhaseBackswing => '③上桿';

  @override
  String get recDetailPhaseTop => '④頂點';

  @override
  String get recDetailPhaseDownswing => '⑤下桿';

  @override
  String get recDetailPhaseImpact => '⑥擊球';

  @override
  String get recDetailPhaseFollowthrough => '⑦送桿';

  @override
  String get recDetailPhaseFinish => '⑧收桿';

  @override
  String get recHistSheetEmptyHint => '目前沒有錄影紀錄，完成錄影後會自動顯示在此處。';

  @override
  String get recHistSheetPickFromFolder => '從檔案資料夾選取影片';

  @override
  String recHistSheetDurationSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get recSelPreparingProgress => '準備中...';

  @override
  String get recSelAnalyzingDialogTitle => '影片分析中';

  @override
  String get recSelNoFileSelected => '❌ 未選擇任何檔案';

  @override
  String recSelVideoTooLong(int durationSec) {
    return '❌ 影片超過 10 分鐘限制（$durationSec 秒）\n請選擇 600 秒以內的影片';
  }

  @override
  String recSelVideoDurationOk(int durationSec) {
    return '✅ 影片時長 $durationSec 秒，符合 10 分鐘限制';
  }

  @override
  String get recSelImportFailed => '❌ 導入失敗\n檔案可能不存在或格式不支援';

  @override
  String recSelImportSuccess(String name, String duration) {
    return '✅ 導入成功！\n$name\n時長: $duration';
  }

  @override
  String recSelImportError(String error) {
    return '❌ 導入出錯\n$error';
  }

  @override
  String get recSelImportingVideo => '正在導入影片...';

  @override
  String get recSelDoNotClose => '請勿關閉應用';

  @override
  String get recSelShotModeTitle => '即時揮桿模式';

  @override
  String get recSelShotModeSubtitle => '揮桿自動偵測並切片，無需錄長影片';

  @override
  String get recSelNewFeatureBadge => '新功能';

  @override
  String get recSelRecordTitle => '開始錄製';

  @override
  String get recSelRecordSubtitle => '即時拍攝並進行揮桿分析';

  @override
  String get recSelLocalVideoTitle => '選擇本地影片';

  @override
  String get recSelLocalVideoSubtitle => '從裝置中選擇已有影片（上限 10 分鐘）';

  @override
  String get recSelShareLinkTitle => '從分享連結取得';

  @override
  String get recSelShareLinkSubtitle => '輸入 16 碼分享碼下載影片';

  @override
  String get recSelHeaderTitle => '選擇錄製方式';

  @override
  String get recSelHeaderSubtitle => '即時拍攝、匯入本地影片或透過分享碼取得';

  @override
  String get recSelIOSSourceSheetTitle => '選擇影片來源';

  @override
  String get recSelPhotoLibrary => '相簿';

  @override
  String get recSelFilesApp => '檔案 App（資料夾）';

  @override
  String recTabsTitle(int count) {
    return '錄影歷史 ($count)';
  }

  @override
  String get recTabsEmpty => '沒有錄影紀錄';

  @override
  String get recTabsEmptyHint => '完成新的錄影後，將在此顯示';

  @override
  String recTabsMode(String label) {
    return '模式：$label';
  }

  @override
  String recTabsDuration(int seconds) {
    return '時長：$seconds秒';
  }

  @override
  String get recordTitle => '高爾夫揮桿錄製';

  @override
  String get recordOverlayToggle => '輪廓疊加切換';

  @override
  String get recordSettings => '錄製設定';

  @override
  String get recordPermissionTitle => '需要相機與麥克風權限';

  @override
  String get recordPermissionMicOnly => '錄影需要麥克風權限以收錄擊球聲，請開啟後再試。';

  @override
  String get recordPermissionCameraAndMic => '揮桿錄影需要相機與麥克風權限，請開啟後再試。';

  @override
  String get recordGoToSettings => '前往設定';

  @override
  String get recordGotIt => '知道了';

  @override
  String get recordLowEndDeviceWarning => '此裝置不支援錄影期間同步骨架偵測，錄影結束後恢復';

  @override
  String get recordFailed => '本次錄製失敗（未取得有效影像），請重新錄製';

  @override
  String get recordVideoQuality => '影片畫質';

  @override
  String get recordFrameRate => '幀率';

  @override
  String get recordAudio => '錄製音訊';

  @override
  String get recordApply => '套用';

  @override
  String get rewardTitle => '獎勵球數';

  @override
  String get rewardUsageHistoryTooltip => '使用紀錄';

  @override
  String rewardEarnedSnackbar(String source, int balls) {
    return '透過「$source」獲得 +$balls 額外球數！';
  }

  @override
  String rewardUploadSubmittedPending(int pending) {
    return '已送出 $pending 筆審核，通過後將發放球數獎勵';
  }

  @override
  String get rewardUploadSubmittedDuplicate => '資料已提交（重複資料不再送審）';

  @override
  String get rewardStatBonusBalls => '累積獎勵';

  @override
  String get rewardUnitBall => '球';

  @override
  String get rewardStatAdToday => '今日廣告';

  @override
  String get rewardAdDailyUnit => '/ 5 次';

  @override
  String get rewardStatInvites => '邀請好友';

  @override
  String get rewardUnitPerson => '位';

  @override
  String rewardBallsBadge(int balls) {
    return '+$balls 球';
  }

  @override
  String rewardAdProgress(int used, int cap) {
    return '$used / $cap 次';
  }

  @override
  String get rewardDoneToday => '今日已完成';

  @override
  String get rewardAdNotCompleted => '廣告未播放完成或暫時無法載入，請稍後再試';

  @override
  String rewardAdFailed(String error) {
    return '廣告獎勵失敗：$error';
  }

  @override
  String get rewardWatchAdTitle => '看廣告';

  @override
  String rewardWatchAdButton(int balls) {
    return '觀看廣告 +$balls 球';
  }

  @override
  String get rewardInviteFriendTitle => '邀請好友';

  @override
  String rewardInviteFriendDesc(int balls) {
    return '好友使用邀請碼註冊後，你獲得 +$balls 球，好友也獲得 +$balls 球';
  }

  @override
  String get rewardGetInviteCode => '取得邀請碼';

  @override
  String get rewardYourInviteCode => '你的邀請碼';

  @override
  String get rewardInviteCodeCopied => '邀請碼已複製';

  @override
  String get rewardInvitedFriends => '已邀請好友';

  @override
  String get rewardNoInviteHistory => '尚無邀請紀錄';

  @override
  String get rewardShareInviteHint => '分享你的邀請碼，邀請好友一起練習！';

  @override
  String get rewardEnterCodeTitle => '輸入邀請碼';

  @override
  String rewardEnterCodeDesc(int balls) {
    return '輸入好友的邀請碼，你獲得 +$balls 球，好友也獲得 +$balls 球';
  }

  @override
  String get rewardEnterCodeEmpty => '請輸入邀請碼';

  @override
  String get rewardInviteCodeInvalid => '邀請碼無效';

  @override
  String rewardApplyFailed(String error) {
    return '套用失敗：$error';
  }

  @override
  String get rewardApplying => '套用中...';

  @override
  String rewardApplyButton(int balls) {
    return '套用 +$balls 球';
  }

  @override
  String get rewardEnterFriendCode => '輸入好友邀請碼';

  @override
  String get rewardFeedbackTitle => '問題回饋';

  @override
  String get rewardFeedbackTypeBug => '🐛 問題回報';

  @override
  String get rewardFeedbackTypeFeature => '💡 功能建議';

  @override
  String get rewardFeedbackTypeOther => '💬 其他';

  @override
  String get rewardFeedbackHint => '請詳細描述你的回饋...';

  @override
  String get rewardSelectVideo => '選擇影片';

  @override
  String get rewardChangeVideo => '更換影片';

  @override
  String get rewardUploadImage => '上傳圖片';

  @override
  String get rewardChangeImage => '更換圖片';

  @override
  String get rewardFeedbackEmpty => '請輸入回饋內容';

  @override
  String get rewardFeedbackSubmitted => '回饋已送出，感謝你的意見！';

  @override
  String rewardSubmitFailed(String error) {
    return '提交失敗：$error';
  }

  @override
  String get rewardSubmitFeedback => '送出回饋';

  @override
  String rewardSubmitFeedbackWithBalls(int balls) {
    return '送出回饋 +$balls 球';
  }

  @override
  String get rewardWriteFeedback => '填寫回饋';

  @override
  String rewardWriteFeedbackWithBalls(int balls) {
    return '填寫回饋 +$balls 球';
  }

  @override
  String get rewardNoVideoHistory => '尚無歷史錄影';

  @override
  String get rewardLongVideo => '長影片';

  @override
  String get rewardShortVideo => '短影片';

  @override
  String get rewardUploadDataTitle => '上傳分析資料';

  @override
  String get rewardNoUploadable => '目前沒有可上傳的分析資料';

  @override
  String rewardUploadPartialFail(int count) {
    return '$count 筆上傳失敗，已略過';
  }

  @override
  String get rewardUploadFailed => '上傳失敗，請稍後再試';

  @override
  String get rewardUploadResubmitBlocked =>
      '送審未成功：資料可能已提交過（含審核未通過者不可重送），或網路異常請稍後再試';

  @override
  String rewardUploadError(String error) {
    return '上傳失敗：$error';
  }

  @override
  String rewardUploadAvailableCount(int available, int uploaded) {
    return '可上傳 $available 筆，已上傳 $uploaded 筆';
  }

  @override
  String rewardUploadAllDone(int count) {
    return '所有分析資料已上傳（共 $count 筆）';
  }

  @override
  String rewardUploadReviewStatus(int pending, int approved) {
    return '審核中 $pending 筆 / 已通過 $approved 筆';
  }

  @override
  String rewardUploadRejectedSuffix(int count) {
    return ' / 未通過 $count 筆';
  }

  @override
  String get rewardUploadRejectedNote => '未通過審核的資料不可重新提交';

  @override
  String get rewardSelectUploadVideo => '選擇要上傳的錄影';

  @override
  String get rewardSelectUploadSubtitle => '選擇一筆後按「確認上傳」獲得獎勵';

  @override
  String get rewardNoneSelected => '尚未選擇';

  @override
  String get rewardOneSelected => '已選 1 筆';

  @override
  String rewardConfirmUpload(int balls) {
    return '確認上傳 +$balls 球';
  }

  @override
  String get rewardAnalyzed => '已分析';

  @override
  String rewardDurationSec(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get settingsNameSyncFailed => '名稱已更新，但伺服器同步失敗';

  @override
  String get settingsGoogleCredentialFailed => '無法取得 Google 憑證，請重試';

  @override
  String get settingsGoogleLinkFailed => 'Google 綁定失敗，請稍後再試';

  @override
  String get shareImportTitle => '從分享連結取得';

  @override
  String get shareImportEnterCodeTitle => '輸入 16 碼分享碼';

  @override
  String get shareImportEnterCodeDesc => '對方分享後，輸入分享碼即可下載影片到本機';

  @override
  String get shareImportCodeValidator => '請輸入完整的 16 碼分享碼';

  @override
  String get shareImportLooking => '查詢中…';

  @override
  String get shareImportLookup => '查詢';

  @override
  String get shareImportFrom => '來自';

  @override
  String get shareImportSize => '大小';

  @override
  String get shareImportExpiry => '到期';

  @override
  String get shareImportReenter => '重新輸入';

  @override
  String get shareImportDownload => '下載到本機';

  @override
  String get shareImportPreparing => '準備下載…';

  @override
  String get shareImportDownloading => '下載中…';

  @override
  String get shareImportExtracting => '解壓縮中…';

  @override
  String get shareImportDoneTitle => '下載完成！';

  @override
  String get shareImportDoneDesc => '影片已加入歷史記錄';

  @override
  String get shareImportBack => '返回';

  @override
  String get shareUploadTitle => '分享連結';

  @override
  String get shareUploadChecking => '檢查分享狀態…';

  @override
  String get shareUploadCompressing => '壓縮中…';

  @override
  String get shareUploadUnknownError => '未知錯誤';

  @override
  String shareUploadUploading(String percent) {
    return '上傳中…  $percent%';
  }

  @override
  String get shareUploadCodeReused => '現有分享碼（尚未過期）';

  @override
  String get shareUploadCodeNew => '分享碼（有效 1 天）';

  @override
  String get shareUploadCopy => '複製';

  @override
  String get shareUploadCopied => '已複製分享碼';

  @override
  String shareUploadShareText(String code) {
    return '高爾夫揮桿分享碼：$code\n（有效 1 天，請在 App 中輸入此碼取得影片）';
  }

  @override
  String get shareUploadSystemShare => '系統分享';

  @override
  String get shotRecTitle => '即時揮桿模式';

  @override
  String get shotRecSettings => '錄製設定';

  @override
  String shotRecShotsCompleted(int count) {
    return '已完成 $count 桿';
  }

  @override
  String get shotRecReady => '準備';

  @override
  String get shotRecCalibrating => '校準中…請保持靜止';

  @override
  String shotRecAddressPrompt(int current, int total) {
    return '請站到準備姿勢 ($current/$total)';
  }

  @override
  String get shotRecAddressSubText => '站定後將自動開始錄影';

  @override
  String get shotRecDetecting => '⚡ 偵測中…請揮桿';

  @override
  String get shotRecStop => '停止';

  @override
  String shotRecSwingDetected(String seconds) {
    return '偵測到揮桿 ✓\n倒數 ${seconds}s';
  }

  @override
  String get shotRecAnalyzing => '分析中…';

  @override
  String get shotRecExtractingAudio => '提取音訊…';

  @override
  String get shotRecDetectingImpact => '偵測擊球…';

  @override
  String get shotRecClipping => '切片中…';

  @override
  String get shotRecScoringAudio => '聲音分析中…';

  @override
  String get shotRecDone => '完成！';

  @override
  String get shotRecWatch => '觀看';

  @override
  String shotRecNextShot(int countdown) {
    return '下一桿 ($countdown)';
  }

  @override
  String get shotRecVideoQuality => '影片畫質';

  @override
  String get shotRecFrameRate => '幀率';

  @override
  String get shotRecEnableAudio => '錄製音訊';

  @override
  String get shotRecApply => '套用';

  @override
  String get shotRecAddressTimeout => '未偵測到準備姿勢，已取消';

  @override
  String get shotRecNoAnalysisWarning => '此裝置不支援錄影期間同步骨架偵測，仍會自動偵測揮桿';

  @override
  String get shotRecRecordFailed => '本次揮桿錄製失敗（未取得有效影像），請重試';

  @override
  String get shotRecNoSwingDetected => '未偵測到揮桿，請重試';

  @override
  String get shotRecClipFailed => '切片失敗，請重試';

  @override
  String shotRecLiveShotName(int number) {
    return '即時第$number桿';
  }

  @override
  String get termsPageSubtitle => '使用者條款與隱私政策';

  @override
  String get termsReadPrompt => '請閱讀以下條款後，勾選同意即可開始使用';

  @override
  String get termsScrolledToBottom => '已閱讀至條款末端，請返回頂部勾選同意。';

  @override
  String get termsDeclineTitle => '確認離開';

  @override
  String get termsDeclineContent => '不同意使用者條款將無法使用 ORVIA。確定要離開嗎？';

  @override
  String get termsDeclineBack => '返回';

  @override
  String get termsDeclineExit => '離開';

  @override
  String get termsPrivacyOpenFailed => '無法開啟隱私政策頁面，請稍後再試';

  @override
  String get termsAgreePrefix => '我已閱讀並同意《使用者條款》與《';

  @override
  String get termsPrivacyLink => '隱私政策';

  @override
  String get termsAgreeSuffix => '》';

  @override
  String get termsAnalyticsTitle => '允許使用統計追蹤（選用）';

  @override
  String get termsAnalyticsDesc => '協助我們改善 App 體驗，不包含個人身份資訊';

  @override
  String get termsScrollFirst => '請先滑動閱讀完整條款後方可勾選同意';

  @override
  String get termsDisagree => '不同意';

  @override
  String get termsAgreeAndContinue => '同意並繼續';

  @override
  String get termsOpenPrivacyFull => '開啟完整隱私政策';

  @override
  String get termsSec1Title => '一、服務說明';

  @override
  String get termsSec1Body =>
      'ORVIA（以下簡稱「本服務」）由 ORVIA 團隊提供，旨在協助使用者透過行動裝置錄製、分析高爾夫揮桿動作，並提供相關數據統計與建議。\n\n使用本服務前，請仔細閱讀以下條款。一旦您開始使用本服務，即表示您已閱讀、理解並同意本條款之所有內容。';

  @override
  String get termsSec2Title => '二、帳號與安全';

  @override
  String get termsSec2Body =>
      '1. 您須透過電子郵件或 Google 帳號完成註冊，方可使用完整功能。\n2. 您有責任妥善保管帳號密碼，並對所有使用您帳號進行的活動負責。\n3. 若發現帳號遭未授權使用，請立即通知我們。\n4. 您不得將帳號轉讓予他人。';

  @override
  String get termsSec3Title => '三、使用者行為規範';

  @override
  String get termsSec3Body =>
      '使用本服務時，您同意：\n\n1. 僅上傳您本人拍攝或擁有合法授權的影片內容。\n2. 不上傳任何違法、侵權或不當內容。\n3. 不干擾或破壞本服務的正常運作。\n4. 不嘗試未授權存取本服務的系統或資料。';

  @override
  String get termsSec4Title => '四、影片與資料處理';

  @override
  String get termsSec4Body =>
      '1. 您上傳的影片與分析資料將儲存於本服務的雲端系統，以提供揮桿分析功能。\n2. 分享功能產生的分享連結有效期為 1 天，到期後將自動刪除相關檔案。\n3. 您可隨時在 App 內刪除個人資料及錄影記錄。\n4. 我們不會將您的個人影片提供給未經授權的第三方。';

  @override
  String get termsSec5Title => '五、隱私政策';

  @override
  String get termsSec5Body =>
      '我們重視您的隱私，並依照以下原則收集與使用您的資訊：\n\n收集的資訊：\n• 帳號資訊（電子郵件、顯示名稱）\n• 揮桿影片及分析結果\n• 裝置資訊與使用紀錄\n\n使用統計追蹤（需您同意）：\n• 我們可能收集匿名使用資料（功能點擊、頁面瀏覽等）\n• 用於改善 App 體驗與功能設計\n• 不包含個人身份資訊，可隨時在設定中關閉\n\n資料保護：\n• 所有資料傳輸採用 TLS 加密\n• 伺服器端資料進行加密儲存\n• 定期進行安全稽核\n\n完整隱私政策請見：https://orvia.atk.tw/privacy.html';

  @override
  String get termsSec6Title => '六、智慧財產權';

  @override
  String get termsSec6Body =>
      '1. 本服務的軟體、介面設計、商標及所有相關內容均屬 ORVIA 所有，受著作權法保護。\n2. 您上傳的影片著作權歸您所有，但您授予本服務使用這些內容以提供分析服務的有限授權。\n3. 未經授權，您不得複製、修改或散布本服務的任何部分。';

  @override
  String get termsSec7Title => '七、免責聲明';

  @override
  String get termsSec7Body =>
      '1. 本服務提供的揮桿分析結果僅供參考，不構成專業運動指導建議。\n2. 本服務以「現狀」提供，不保證服務永遠不間斷或無誤差。\n3. 對於因使用本服務所產生的任何直接或間接損失，本服務不負賠償責任。\n4. 揮桿練習涉及身體活動，請在安全環境下進行，並自行評估身體狀況。';

  @override
  String get termsSec8Title => '八、服務變更與終止';

  @override
  String get termsSec8Body =>
      '1. 我們保留在任何時間修改、暫停或終止本服務的權利。\n2. 若本條款有重大變更，我們將透過 App 通知您。\n3. 繼續使用本服務視為接受更新後的條款。';

  @override
  String get termsSec9Title => '九、聯絡我們';

  @override
  String get termsSec9Body =>
      '若您對本條款有任何疑問，請透過以下方式聯絡我們：\n\n電子郵件：support@atk.tw\n服務網站：https://orvia.atk.tw\n隱私政策：https://orvia.atk.tw/privacy.html\n\n本條款最後更新日期：2026 年 5 月 25 日';

  @override
  String get testVideoTitle => '選擇測試影片';

  @override
  String testVideoLoadError(String error) {
    return '載入影片失敗\n$error';
  }

  @override
  String get testVideoEmpty => '尚無已導入的影片';

  @override
  String get testVideoSelect => '選擇';

  @override
  String get testVideoHint => '💡 提示：選擇一支影片作為測試錄製，用於演示和測試分析功能';

  @override
  String get upgradeSubscribed => '已訂閱';

  @override
  String get upgradeCurrentPlanActive => '目前方案';

  @override
  String get upgradeMonthly => '月繳';

  @override
  String get upgradeYearly => '年繳（享約 2 個月折扣）';

  @override
  String upgradeSubscribeFailed(String error) {
    return '訂閱失敗：$error';
  }

  @override
  String get upgradeProductLoadFailed => '商品載入失敗，請稍後再試';

  @override
  String get upgradeAppStoreSubscribe => 'App Store 訂閱';

  @override
  String get upgradeGooglePlaySubscribe => 'Google Play 訂閱';

  @override
  String get upgradeManageSubscriptionIos => '訂閱後可隨時在 App Store 管理或取消';

  @override
  String get upgradeManageSubscriptionAndroid => '訂閱後可隨時在 Google Play 管理或取消';

  @override
  String get upgradeBuyBalls => '單買球數';

  @override
  String get upgradeNoExpiry => '不限時間使用';

  @override
  String upgradeBallCount(int count) {
    return '$count 球';
  }

  @override
  String get upgradeBallPackValidity => '永久有效，隨時使用';

  @override
  String get upgradeBuyButton => '購買';

  @override
  String upgradePurchaseFailed(String error) {
    return '購買失敗：$error';
  }

  @override
  String upgradeBuyBallCount(int count) {
    return '購買 $count 球';
  }

  @override
  String get upgradeBallPackDescription => '球數永久有效，不限時間使用。用完每日配額後自動消耗。';

  @override
  String get upgradeAppStorePurchase => 'App Store 購買';

  @override
  String get upgradeGooglePlayPurchase => 'Google Play 購買';

  @override
  String get usageTitle => '使用紀錄';

  @override
  String get usageSubtitle => 'AI 分析 & 球數流水帳';

  @override
  String get usageTabAnalysis => 'AI 分析紀錄';

  @override
  String get usageTabBalls => '球數流水帳';

  @override
  String get usageLoadFailed => '載入失敗，請下拉重試';

  @override
  String usageLoadError(String error) {
    return '載入錯誤：$error';
  }

  @override
  String get usageEmptyAnalysis => '尚無分析紀錄';

  @override
  String get usageAllLoaded => '已載入全部紀錄';

  @override
  String get usageSummaryTotalAnalysis => '累計分析';

  @override
  String get usageUnitTimes => '次';

  @override
  String get usageSummaryTodayUsed => '今日已用';

  @override
  String get usageAnalysisItemTitle => 'AI 揮桿分析';

  @override
  String get usageSourceDailyQuota => '每日配額';

  @override
  String get usageSourceBonusBall => '獎勵球';

  @override
  String get usageSourceDailyQuotaDesc => '使用每日配額';

  @override
  String get usageSourceBonusBallDesc => '消耗 1 顆球';

  @override
  String get usageEmptyBalls => '尚無球數紀錄';

  @override
  String get usageSummaryTotalRecords => '累計筆數';

  @override
  String get usageUnitRecords => '筆';

  @override
  String get usageSummaryCurrentBalls => '目前球數';

  @override
  String get usageUnitBalls => '球';

  @override
  String usageBallBalance(int balance) {
    return '餘額 $balance 球';
  }

  @override
  String get usageDateToday => '今天';

  @override
  String get usageDateYesterday => '昨天';

  @override
  String waveformCrispScore(int score) {
    return '清脆度 $score';
  }

  @override
  String waveformPeakLabel(String level) {
    return '峰值 $level';
  }

  @override
  String get extImportProgressCopying => '複製影片中...';

  @override
  String get extImportProgressTranscoding => '轉檔準備中...';

  @override
  String get extImportProgressDurationInvalid => '影片時長不符 (需 1-600 秒)';

  @override
  String get extImportProgressThumbnail => '生成縮圖中...';

  @override
  String get extImportProgressDone => '匯入完成 ✅';

  @override
  String get learnHubGoodSwingTitle => '良好揮桿示範';

  @override
  String get learnHubGoodSwingDesc => '節奏平順、重心穩定、擊球後收桿完整。';

  @override
  String get learnHubEarlyReleaseTitle => '常見錯誤：提前釋放';

  @override
  String get learnHubEarlyReleaseDesc => '手腕提前放鬆，導致桿頭加速度不足，球路弱/右曲。';

  @override
  String get learnHubMarkerBackswingTop => '上桿頂點';

  @override
  String get learnHubMarkerBackswingTopNote => '重心仍在腳中，桿身與手臂成直線';

  @override
  String get learnHubMarkerImpact => '擊球瞬間';

  @override
  String get learnHubMarkerImpactNote => '手位在球前方，身體旋轉帶動擊球';

  @override
  String get learnHubMarkerFinish => '收桿';

  @override
  String get learnHubMarkerFinishNote => '重心轉向前腳，身體保持平衡';

  @override
  String get learnHubMarkerEarlyReleaseTopNote => '手腕角度過早放鬆，桿頭落後';

  @override
  String get learnHubMarkerPreImpact => '擊球前';

  @override
  String get learnHubMarkerPreImpactNote => '手部領先不足，重心偏後';

  @override
  String get learnHubMarkerEarlyReleaseFinishNote => '重心未移到前腳，平衡不佳';

  @override
  String get playerTimelineAbbrAddress => '準';

  @override
  String get playerTimelineAbbrTakeaway => '起';

  @override
  String get playerTimelineAbbrBackswing => '上';

  @override
  String get playerTimelineAbbrTop => '頂';

  @override
  String get playerTimelineAbbrDownswing => '下';

  @override
  String get playerTimelineAbbrImpact => '擊';

  @override
  String get playerTimelineAbbrFollowthrough => '送';

  @override
  String get playerTimelineAbbrFinish => '收';

  @override
  String get recHistSheetTitle => '曾經錄影紀錄';

  @override
  String get recTabsToday => '今天';

  @override
  String get recTabsYesterday => '昨天';

  @override
  String recTabsDateMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get recWidgetsZoomWide => '最廣';

  @override
  String get recWidgetsSavingVideo => '儲存影片中…';

  @override
  String get rewardFriendFallbackName => '好友';

  @override
  String get upgradeHighlightFullFeatured => '完整錄影與分析功能';

  @override
  String get upgradeHighlightAiDaily10 => 'AI 教練分析每日 10 次';

  @override
  String get upgradeHighlightBuyMore => '球數用完可購買加值';

  @override
  String get upgradeHighlightAiDaily90 => 'AI 教練分析每日 90 次';

  @override
  String get upgradeHighlightAiUnlimited => 'AI 教練分析無限次';

  @override
  String get upgradeFeatureAutoClip => '長影片自動切片';

  @override
  String get upgradeFeatureVoiceHint => '即時語音提示';

  @override
  String get upgradeFeatureAudioScore => '音頻分析（擊球評分）';

  @override
  String get upgradeFeatureDualVideo => '雙影片比較';

  @override
  String get upgradeFeatureAiCoachAnalysis => 'AI 教練分析';

  @override
  String get upgradeQuotaDaily10 => '每日10球';

  @override
  String get upgradeQuotaDaily90 => '每日90球';

  @override
  String get upgradeQuotaUnlimited => '無限';

  @override
  String get upgradeBadgePopular => '熱門';

  @override
  String get upgradeBadgeValue => '划算';

  @override
  String get upgradeBadgeBestDeal => '最優惠';

  @override
  String get upgradePerYear => '/年';

  @override
  String get usageReasonAd => '看廣告獎勵';

  @override
  String get usageReasonFeedback => '問題回饋獎勵';

  @override
  String get usageReasonInvite => '邀請好友獎勵';

  @override
  String get usageReasonUpload => '上傳資料獎勵';

  @override
  String get usageReasonAnalysis => 'AI 分析消耗';

  @override
  String get usageReasonManual => '手動調整';

  @override
  String get usageReasonOther => '其他';

  @override
  String get waveformPeakHigh => '高';

  @override
  String get waveformPeakMid => '中';

  @override
  String get waveformPeakLow => '低';

  @override
  String get waveformFreqCrispy => '偏清脆';

  @override
  String get waveformFreqMid => '中音';

  @override
  String get waveformFreqMuffled => '偏悶';

  @override
  String get historyProgressV2AudioScan => 'V2 音訊掃描中...';

  @override
  String get historyProgressV3AudioScan => 'V3 音訊掃描中...';

  @override
  String get historyProgressWaitingConfirm => '等待確認片段...';

  @override
  String get historyProgressClipping => '裁切片段中...';

  @override
  String historyProgressClippingPct(int pct, int cur, int total) {
    return '裁切片段中... $pct% ($cur/$total)';
  }

  @override
  String historyProgressV3SkeletonAnalysis(int cur, int total) {
    return 'V3 骨架分析 $cur/$total';
  }

  @override
  String historyProgressV3SkeletonItem(int cur, int total) {
    return '第$cur/$total個';
  }

  @override
  String get historyProgressDetectingHit => '偵測擊球中...';

  @override
  String get historyProgressVideoAnalysis => '視頻分析中...';

  @override
  String get historyProgressDetectingPhase => '偵測揮桿階段...';

  @override
  String get historyProgressAudioAnalysis => '音頻分析中...';

  @override
  String get historyDlLabelFull => '完整分析';

  @override
  String get historyDlDescFull => '骨架 + 球軌跡 overlay';

  @override
  String get historyDlLabelSkeleton => '骨架版';

  @override
  String get historyDlDescSkeleton => '只含骨架 overlay';

  @override
  String get historyDlLabelClip => '原始切片';

  @override
  String get historyDlDescClip => '無 overlay 的原始切片';

  @override
  String get historyDlLabelRaw => '原始影片';

  @override
  String get historyDlDescRaw => '無任何 overlay';

  @override
  String get historyDlLabelRawMov => '原始影片 (MOV)';

  @override
  String get historyDlDescRawMov => '原始 MOV 檔';

  @override
  String historyCandidateDuration(int seconds) {
    return '$seconds 秒';
  }

  @override
  String recDetailPointCount(int count) {
    return '$count 點';
  }
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appName => 'ORVIA';

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
  String get authLoginSubtitle => '登录 ORVIA 以同步挥杆数据并探索最新分析报告。';

  @override
  String get authRegisterTitle => '创建账号';

  @override
  String get authRegisterSubtitle => '填写以下信息即可开始使用 ORVIA。';

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
  String get authLoginButton => '登录 ORVIA';

  @override
  String get authRegisterButton => '创建账号';

  @override
  String get authSocialDivider => '或使用社交账号快速登录';

  @override
  String get authLoginWithGoogle => '使用 Google 登录';

  @override
  String get authGoogleSigningIn => 'Google 登录中...';

  @override
  String get authLoginWithApple => '使用 Apple 登录';

  @override
  String get authAppleSigningIn => 'Apple 登录中...';

  @override
  String get authNoAccount => '还没有账号？立即注册';

  @override
  String get authHaveAccount => '已有账号？返回登录';

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
  String get validationPasswordTooShort => '密码须至少 8 位且包含大写、小写字母及数字';

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
  String get msgAppleLoginCancelled => '已取消 Apple 登录流程';

  @override
  String get msgAppleLoginSuccess => 'Apple 登录成功，欢迎回来！';

  @override
  String msgAppleLoginFailed(Object error) {
    return 'Apple 登录失败：$error';
  }

  @override
  String get msgAppleLoginNoToken => 'Apple 登录失败：服务器未返回认证令牌';

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
      '请在系统设置中允许以下权限：\n1. 进入「应用与通知」\n2. 选择 ORVIA → 权限\n3. 启用「附近设备、蓝牙」与「定位」';

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

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionAccount => '账号';

  @override
  String get settingsChangeName => '修改名称';

  @override
  String get settingsChangeNameHint => '请输入显示名称';

  @override
  String get settingsChangePassword => '修改密码';

  @override
  String get settingsCurrentPassword => '当前密码';

  @override
  String get settingsNewPassword => '新密码';

  @override
  String get settingsConfirmNewPassword => '确认新密码';

  @override
  String get settingsCurrentPasswordRequired => '请输入当前密码';

  @override
  String get settingsConfirmChange => '确认修改';

  @override
  String get settingsPasswordChanged => '密码已修改';

  @override
  String get settingsSetPassword => '设置密码';

  @override
  String get settingsSetPasswordDesc => '设置密码后也可用 Email 登录';

  @override
  String get settingsPasswordSet => '密码已设置';

  @override
  String get settingsGoogleLogin => 'Google 登录';

  @override
  String get settingsGoogleLinked => '已绑定';

  @override
  String get settingsGoogleNotLinked => '未绑定，点击链接 Google 账号';

  @override
  String get settingsAppleLogin => 'Apple 登录';

  @override
  String get settingsAppleLinked => '已绑定';

  @override
  String get settingsAppleNotLinked => '未绑定，点击链接 Apple 账号';

  @override
  String get settingsAppleCredentialFailed => '无法获取 Apple 凭证，请重试';

  @override
  String get settingsAppleLinkFailed => 'Apple 绑定失败，请稍后再试';

  @override
  String get settingsSectionAnalysis => '分析偏好';

  @override
  String get settingsAnalysisQuality => '完整分析输出质量';

  @override
  String get settingsQualityHint => '保存后作为默认值，下次分析自动应用';

  @override
  String get settingsApply => '应用';

  @override
  String settingsQualityUpdated(String quality) {
    return '输出质量已更新为「$quality」';
  }

  @override
  String get settingsSectionSubscription => '订阅';

  @override
  String get settingsViewSubscription => '查看订阅方案';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsLanguage => '语言 / Language';

  @override
  String get settingsTheme => '外观主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '日间模式';

  @override
  String get settingsThemeDark => '夜间模式';

  @override
  String get settingsCheckUpdate => '检查更新';

  @override
  String get settingsAnalytics => '使用统计追踪';

  @override
  String get settingsAnalyticsDesc => '匿名使用统计，协助改善 App 体验';

  @override
  String get settingsPrivacyPolicy => '隐私政策';

  @override
  String get settingsTermsOfService => '使用条款';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsPrivacyOpenFailed => '无法开启隐私政策页面，请稍后再试';

  @override
  String get settingsVersionCopied => '已复制版本';

  @override
  String settingsAlreadyLatest(String version) {
    return '已是最新版本 v$version';
  }

  @override
  String get settingsUpdateCheckFailed => '检查更新失败，请稍后重试';

  @override
  String get settingsConfirmLogout => '确定退出？';

  @override
  String get settingsLogoutWarning => '退出后需重新登录才能使用云端功能。';

  @override
  String get commonContinue => '继续';

  @override
  String get settingsDeleteAccount => '删除帐号';

  @override
  String get settingsDeleteAccountWarning =>
      '删除帐号将永久移除你的个人资料、订阅与分析记录，且无法复原。此操作不会自动退款，订阅请另于 App Store／Google Play 取消。确定要继续吗？';

  @override
  String get settingsDeleteAccountConfirmTitle => '最后确认';

  @override
  String get settingsDeleteAccountConfirmHint => '请输入「DELETE」以确认永久删除帐号。';

  @override
  String get settingsDeleteAccountFailed => '删除帐号失败，请稍后再试或联系客服。';

  @override
  String get settingsNameUpdated => '名称已更新';

  @override
  String get settingsPickFromGallery => '从相册选择';

  @override
  String get settingsRemoveAvatar => '移除头像';

  @override
  String get homeTodayOverview => '今日概况';

  @override
  String homeHi(String name) {
    return '嗨，$name 👋';
  }

  @override
  String get homeRounds => '练习轮次';

  @override
  String get homePractices => '练习次数';

  @override
  String get homeTodayGoodRate => '今日好球率';

  @override
  String homeGoodTimes(int count) {
    return '好球 $count 次';
  }

  @override
  String homeBadTimes(int count) {
    return '坏球 $count 次';
  }

  @override
  String get homeTodayPosture => '今日姿势分析';

  @override
  String get homeTopSpeed => '最佳速度';

  @override
  String get homeSweetSpot => '甜蜜点';

  @override
  String get homeCrispness => '清脆度';

  @override
  String get homeAnnouncements => '公告栏';

  @override
  String get homeRewardBalls => '奖励球数';

  @override
  String get homeGreetingQuestion => '今天的挥杆目标，准备开始了吗？';

  @override
  String get homeTodayQuota => '今日用量';

  @override
  String homeQuotaBalls(int used, int total) {
    return '$used / $total 球';
  }

  @override
  String get homeHitAnalysis => '击球分析';

  @override
  String get homeHitRecordsLabel => '笔击球记录';

  @override
  String homeImprovedVsAvg(String pct) {
    return '持续进步中！本次表现较平均提升 $pct%。';
  }

  @override
  String get homeTrainingFocus => '训练重点';

  @override
  String get homeViewNow => '立即查看';

  @override
  String get homeNoShotsToday => '今天还没有击球记录，去录一杆吧！';

  @override
  String get homeEmptyHint => '录下第一杆，开始累积你的数据';

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String get todayTitleToday => '今日概况';

  @override
  String get todayTitleHistory => '历史概况';

  @override
  String get todayLoadFailed => '加载失败，请下拉刷新';

  @override
  String get todaySweetSpotHit => '甜蜜点命中';

  @override
  String get todayCrispness => '声音清脆度';

  @override
  String get todayTopSpeed => '最佳速度';

  @override
  String get todayNoRecord => '今天还没有练习记录';

  @override
  String get todayNoRecordDate => '这天没有练习记录';

  @override
  String get todayGoRecord => '去录一次挥杆吧！';

  @override
  String get todayPostureToday => '今日姿势分析';

  @override
  String get todayPosture => '姿势分析';

  @override
  String get annBoardTitle => '公告栏';

  @override
  String annUnreadCount(int count) {
    return '$count 条未读';
  }

  @override
  String get annAllAnnouncements => '全部公告';

  @override
  String get annMarkAllRead => '全部已读';

  @override
  String get annRefresh => '刷新';

  @override
  String get annLoadFailed => '加载失败，请下拉重试';

  @override
  String annMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String annHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String annDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get annDetailTitle => '公告详情';

  @override
  String annExpiresAt(String date) {
    return '有效期至 $date';
  }

  @override
  String get annEmpty => '暂无公告';

  @override
  String get annEmptySubtitle => '新公告将显示在这里';

  @override
  String get updateNotes => '更新内容';

  @override
  String get updateForcedWarning => '此版本已停止支持，请更新后继续使用';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateRemindLater => '稍后提醒';

  @override
  String get updateDontRemind => '不再提醒';

  @override
  String get updateCannotOpenStore => '无法打开商店页面，请手动前往更新';

  @override
  String get updateRequiredTitle => '必要更新';

  @override
  String get updateRequiredSubtitle => '请更新后继续使用 ORVIA';

  @override
  String get updateFoundTitle => '发现新版本';

  @override
  String get updateFoundSubtitle => '建议更新以获得最佳体验';

  @override
  String get updateCurrentVersion => '当前版本';

  @override
  String get updateLatestVersion => '最新版本';

  @override
  String get upgradePageTitle => '升级您的方案';

  @override
  String get upgradePageSubtitle => '解锁更多挥杆分析功能，提升您的球技';

  @override
  String get upgradeFullComparison => '完整功能对比';

  @override
  String get upgradeFeatureColumn => '功能';

  @override
  String upgradeSubscribePlan(String plan) {
    return '升级 $plan 方案';
  }

  @override
  String get upgradeSelectPayment => '选择付款方式';

  @override
  String get upgradeApplePayFailed => 'Apple Pay 配置加载失败';

  @override
  String get upgradeGooglePayFailed => 'Google Pay 配置加载失败';

  @override
  String get upgradePaymentFailed => '付款验证失败，请稍后重试';

  @override
  String get upgradeSuccessMsg => '升级成功';

  @override
  String get upgradeAlreadyFree => '您目前使用的已是免费方案';

  @override
  String get learningTitle => '挥杆学习';

  @override
  String get learningMoreComing => '更多课程持续更新中';

  @override
  String get learningVideoComingSoon => '示范视频待补充，先提供重点与标记供对照学习。';

  @override
  String get learningKeyMarkers => '关键标记';

  @override
  String get myFeedbackTitle => '我的反馈';

  @override
  String get myFeedbackSubtitle => '已提交的反馈与官方回复';

  @override
  String get myFeedbackEntry => '查看我的反馈';

  @override
  String get myFeedbackEmpty => '尚无反馈记录';

  @override
  String get myFeedbackLoadFailed => '加载失败，请下拉重试';

  @override
  String get myFeedbackAllLoaded => '已加载全部反馈';

  @override
  String get myFeedbackTypeBug => '问题反馈';

  @override
  String get myFeedbackTypeFeature => '功能建议';

  @override
  String get myFeedbackTypeOther => '其他';

  @override
  String get myFeedbackAdminReply => '官方回复';

  @override
  String get myFeedbackNoReply => '等待回复中';

  @override
  String get myFeedbackAttachedVideo => '已附视频';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingStart => '开始使用';

  @override
  String get onboardingRecordTitle => '录制你的挥杆';

  @override
  String get onboardingRecordDesc => '点击底部中央的录制按钮开始录像，ORVIA 会边录边自动检测每一次击球。';

  @override
  String get onboardingClipTitle => '自动切片';

  @override
  String get onboardingClipDesc => '录像结束后，每一杆会自动切成 5 秒片段，可在历史页逐段检查。';

  @override
  String get onboardingAiTitle => 'AI 分析';

  @override
  String get onboardingAiDesc => '将切片发送给 AI 教练，分析姿势、8 阶段挥杆与球体轨迹。';

  @override
  String get onboardingBallsTitle => '球数与奖励';

  @override
  String get onboardingBallsDesc => '分析需要消耗球数。每天有免费额度，也可通过看广告、提交反馈或邀请好友赚取更多。';

  @override
  String get settingsReplayTutorial => '重看教学引导';

  @override
  String recFrameCount(int count) {
    return '$count 帧';
  }

  @override
  String recDetectedShots(int count) {
    return '已检测 $count 杆';
  }

  @override
  String recImpactShot(int number) {
    return '第 $number 杆';
  }

  @override
  String get privacySettingsTitle => '隐私与分析';

  @override
  String get privacySectionDataCollection => '数据收集说明';

  @override
  String get privacyDataCollectionDesc =>
      '你的视频与分析数据只会在你主动操作时上传——AI 分析、分享、上传奖励或反馈附件。ORVIA 没有后台上传，也没有隐藏的遥测。';

  @override
  String get privacySectionPolicies => '政策文件';

  @override
  String get privacySectionUpload => '分析数据上传';

  @override
  String get privacyUploadDesc =>
      '你可以自愿提交挥杆视频与传感 CSV 数据，帮助改善挥杆检测模型。每笔提交都会人工审核，通过后发放奖励球。';

  @override
  String get privacyUploadStatusEntry => '查看我的上传审核状态';

  @override
  String get privacySectionAccount => '账号';

  @override
  String get privacyDeleteAccountSubtitle => '软删除：将无法再登录，数据会被匿名化';

  @override
  String get rewardSubtitle => '完成任务累积球数，兑换分析次数';

  @override
  String get historyFilterReset => '重置';

  @override
  String aiCoachUpgradeFailed(String error) {
    return '升级失败: $error';
  }

  @override
  String get aiCoachQuotaExhaustedTitle => '今日球数已用完';

  @override
  String aiCoachQuotaExhaustedBody(int todayUsed, int totalLimit) {
    return '今日已使用 $todayUsed 次，已达上限 $totalLimit 次。\n\n明天可继续使用，或升级方案获取更多次数。';
  }

  @override
  String get aiCoachGotIt => '知道了';

  @override
  String get aiCoachAnalysisFailed => '分析失败，请重试';

  @override
  String get aiCoachStatusPending => '准备中...';

  @override
  String get aiCoachStatusQueued => '等待分析队列...';

  @override
  String get aiCoachStatusProcessing => 'AI 教练正在分析视频...';

  @override
  String get aiCoachStatusIdle => '等待 AI 教练分析...';

  @override
  String get aiCoachStatusConnecting => '连接中...';

  @override
  String get aiCoachLoadingHint => '通常需要 10~30 秒';

  @override
  String get aiCoachPostureAnalysisDone => '已完成错误姿势分析';

  @override
  String get aiCoachSubmitting => '提交中...';

  @override
  String get aiCoachStartAnalysis => '开始 AI 教练分析';

  @override
  String get aiCoachAnalysisHint => '* AI 教练将依据姿势分析结果，提供详细教练评语与训练建议';

  @override
  String get aiCoachEvidence => '依据';

  @override
  String get aiCoachSeverityHigh => '严重';

  @override
  String get aiCoachSeverityMedium => '中等';

  @override
  String get aiCoachSeverityLow => '轻微';

  @override
  String get aiCoachImpactPremiumSweetSpot => '高品质甜蜜点';

  @override
  String get aiCoachImpactSweetSpot => '甜蜜点';

  @override
  String get aiCoachImpactNearSweetSpot => '接近甜蜜点';

  @override
  String get aiCoachImpactFair => '普通';

  @override
  String get aiCoachImpactPoor => '击球偏虚';

  @override
  String get aiCoachImpactQualityTitle => '击球品质（音频）';

  @override
  String aiCoachImpactFeatureCount(int passCount, int totalFeatures) {
    return '$passCount / $totalFeatures 项特征符合甜蜜点范围';
  }

  @override
  String get aiCoachFeedbackTitle => '教练评语';

  @override
  String get aiCoachPracticeTitle => '训练建议';

  @override
  String get aiCoachNextGoalTitle => '下次练习目标';

  @override
  String get aiCoachReanalyzeSubmitting => '提交重新分析中...';

  @override
  String aiCoachReanalyzeFailed(String error) {
    return '重新分析失败: $error';
  }

  @override
  String get ballTuneTitle => '球轨迹调参';

  @override
  String get ballTuneHudInit => '初始化中…';

  @override
  String get ballTuneHudDetecting => '检测中…';

  @override
  String get ballTuneHudBlobFailed => 'blob 提取失败';

  @override
  String ballTuneRoiBadge(String r, String margin) {
    return 'ROI r=${r}px  margin=$margin';
  }

  @override
  String get ballTuneRoiToggleTooltip => 'ROI 叠图开关';

  @override
  String get ballTuneSectionRealtime => '实时（拉了立刻重绘）';

  @override
  String get ballTuneSliderResidual => '质量门控 残差上限';

  @override
  String get ballTuneSliderP1MaxDist => 'P1 最远距离';

  @override
  String get ballTuneRoiMaskSection => 'ROI / 遮罩（可直接在预览上拖拉）';

  @override
  String get ballTuneSliderRoiRadius => 'ROI 半径';

  @override
  String get ballTuneSliderGolferMargin => '球员遮罩 margin';

  @override
  String get ballTuneSliderRoiMissScale => 'ROI miss 大扩张×';

  @override
  String get ballTuneSliderRoiRadiusMax => 'ROI 半径上限';

  @override
  String get ballTuneSliderStepMaxPost => '击球后 step 上限';

  @override
  String get ballTuneSliderPredMaxPost => '击球后 pred 上限';

  @override
  String get ballTuneSliderMissPatiencePost => '击球后 miss 容忍';

  @override
  String get ballTuneSectionReextract => '重新提取（改完按下方按钮）';

  @override
  String get ballTuneSliderDiffThresh => 'diffThresh 帧差门槛';

  @override
  String get ballTuneRedetectButton => '重新检测（应用 diffThresh）';

  @override
  String clipCandTitle(int count) {
    return '确认击球片段（$count 个候选）';
  }

  @override
  String get clipCandTapToPreview => '点候选可预览';

  @override
  String get clipCandRangeTooShort => '切片区段需至少 0.5 秒（终点需在起点之后）';

  @override
  String clipCandConfirmClip(int count) {
    return '切出 $count 个片段';
  }

  @override
  String clipCandManualHint(String start) {
    return '起点 $start → 拖到终点后按「加入区段」';
  }

  @override
  String get clipCandManualPrompt => '自由切片：拖时间轴到起点';

  @override
  String get clipCandSetStart => '设为起点';

  @override
  String get clipCandReset => '重设';

  @override
  String get clipCandAddRange => '加入区段';

  @override
  String clipCandCandidateLabel(int index, String time) {
    return '候选 $index ・ $time';
  }

  @override
  String get clipCandFromAudio => '击球声检测';

  @override
  String get clipCandFromMotion => '录影中动作检测';

  @override
  String clipCandManualRangeLabel(String start, String end) {
    return '自定区段 ・ $start - $end';
  }

  @override
  String clipCandRangeDuration(String seconds) {
    return '长度 $seconds 秒';
  }

  @override
  String get compareLoadingVideos => '加载视频中…';

  @override
  String get highlightTitle => 'Highlight 预览';

  @override
  String get highlightShareSystem => '系统分享';

  @override
  String get highlightExportDebug => '导出 debug';

  @override
  String get highlightShareDebug => '分享 debug';

  @override
  String get highlightShareText => '我的挥杆 Highlight';

  @override
  String get highlightDebugFileError => '无法创建 debug 文件';

  @override
  String get highlightStoragePermissionRequired => '需要存储权限以导出至下载文件夹';

  @override
  String get highlightDownloadsDirNotFound => '找不到下载文件夹';

  @override
  String highlightSavedTo(String path) {
    return '已另存至：$path';
  }

  @override
  String highlightExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String historySubtitle(int total, int good, int bad) {
    return '共 $total 笔 · 好球 $good · 坏球 $bad';
  }

  @override
  String get historySearchHint => '搜索录影…';

  @override
  String historySearchResult(int count, int total) {
    return '搜索结果 $count / $total 笔';
  }

  @override
  String get historySearchNoResult => '找不到匹配的记录';

  @override
  String historySearchNoResultHint(Object query) {
    return '没有符合「$query」的结果';
  }

  @override
  String get historySearchClear => '清除搜索';

  @override
  String get historyEmptyTitle => '还没有任何录影';

  @override
  String get historyEmptySubtitle => '开始录制挥杆来累积记录吧';

  @override
  String get historyFilterLabelSort => '排序';

  @override
  String get historyFilterLabelDate => '日期';

  @override
  String get historyFilterLabelVideo => '影片';

  @override
  String get historyFilterLabelGoodBad => '评级';

  @override
  String get historyFilterLabelAnalysis => '分析';

  @override
  String get historyFilterLabelClip => '切片';

  @override
  String get historyFilterLabelAI => 'AI';

  @override
  String get historyFilterLabelPosture => '姿势';

  @override
  String get historyFilterAll => '全部';

  @override
  String get historyFilterToday => '今天';

  @override
  String get historyFilterWeek => '本周';

  @override
  String get historyFilterMonth => '本月';

  @override
  String get historyFilterCustomDate => '自定日期范围';

  @override
  String get historyFilterSort => '排序方式';

  @override
  String get historyFilterGood => '优';

  @override
  String get historyFilterBad => '劣';

  @override
  String get historyFilterAnalyzed => '已分析';

  @override
  String get historyFilterNotAnalyzed => '未分析';

  @override
  String get historyFilterAiAnalyzed => 'AI 已分析';

  @override
  String get historyFilterAiNotAnalyzed => 'AI 未分析';

  @override
  String get historyFilterClipped => '已切片';

  @override
  String get historyFilterNotClipped => '未切片';

  @override
  String get historyFilterLongVideo => '长影片';

  @override
  String get historyFilterShortVideo => '短影片';

  @override
  String get historySortDate => '时间';

  @override
  String get historySortPeakSpeed => '最佳速度';

  @override
  String get historySortClipTime => '片段时间';

  @override
  String get historyDateRangeHelp => '选择日期范围';

  @override
  String get historyDeleteTitle => '删除录影';

  @override
  String historyDeleteClipConfirm(Object title) {
    return '确定删除切片「$title」？';
  }

  @override
  String historyDeleteVideoConfirm(Object title) {
    return '确定删除录影「$title」？';
  }

  @override
  String historyDeleteVideoWithClipsConfirm(Object title, Object count) {
    return '确定删除「$title」及其 $count 个切片？';
  }

  @override
  String historyDeletedSnack(Object name) {
    return '已删除 $name';
  }

  @override
  String historyDeletedWithClipsSnack(Object name, Object count) {
    return '已删除 $name 及 $count 个切片';
  }

  @override
  String get historyRenameTitle => '重命名录影';

  @override
  String get historyRenameClipTitle => '重命名切片';

  @override
  String get historyRenameLabel => '新名称';

  @override
  String get historyRenameHelper => '留空以还原默认名称';

  @override
  String get historyRenameValidation => '名称不能为空白';

  @override
  String historyRenamedSnack(Object name) {
    return '已重命名为「$name」';
  }

  @override
  String historyRenameResetSnack(Object name) {
    return '已还原默认名称「$name」';
  }

  @override
  String historyFileNotFound(Object name) {
    return '找不到文件：$name';
  }

  @override
  String get historyClipFileNotExist => '切片文件不存在，请重新检测';

  @override
  String get historyAlreadyClipped => '此影片已有切片，重新检测将取代现有切片。';

  @override
  String get historyProgressPreparingSkeleton => '准备骨架分析…';

  @override
  String get historyProgressPreparing => '准备中…';

  @override
  String get historyDetectingShots => '检测挥杆中';

  @override
  String get historyCancelledDetection => '已取消检测';

  @override
  String get historyCancelledAnalysis => '已取消分析';

  @override
  String get historyV2NoAudio => '未找到音频轨，无法使用音频检测模式';

  @override
  String get historyV3NoShot => '骨架分析未检测到任何挥杆';

  @override
  String get historyV3NoValidHit => '过滤后无有效击球点';

  @override
  String get historyNoShotDetected => '未检测到挥杆';

  @override
  String get historyClipFailed => '切片生成失败';

  @override
  String historyClipsGenerated(Object count) {
    return '已生成 $count 个切片';
  }

  @override
  String historyClipsGeneratedBg(Object count) {
    return '已将 $count 个切片存入记录';
  }

  @override
  String historyDetectFailed(Object error) {
    return '检测失败：$error';
  }

  @override
  String get historyLongVideoTitle => '长影片提示';

  @override
  String historyLongVideoContent(Object seconds) {
    return '此影片长达 $seconds 秒，完整分析可能需要较长时间。';
  }

  @override
  String get historyContinueAnalysis => '继续分析';

  @override
  String get historyFullAnalysisTitle => '分析中';

  @override
  String historyInvalidDuration(Object seconds) {
    return '影片时长无效：$seconds 秒';
  }

  @override
  String historyAnalysisComplete(Object audio) {
    return '分析完成$audio';
  }

  @override
  String historyAnalysisFailed(Object error) {
    return '分析失败：$error';
  }

  @override
  String get historyQuotaExhaustedTitle => '今日配额已用尽';

  @override
  String historyQuotaExhaustedContent(Object used, Object total) {
    return '今日已使用 $used/$total 次，升级方案以继续使用。';
  }

  @override
  String get historyGotIt => '知道了';

  @override
  String get historyAiAnalysisConfirmTitle => 'AI 分析';

  @override
  String get historyAiAnalysisConfirmDesc => '提交此挥杆进行 AI 分析，将消耗 1 颗球。';

  @override
  String get historyAiAnalysisConfirmBtn => '开始分析';

  @override
  String historyAiSubmitFailed(Object error) {
    return '提交失败：$error';
  }

  @override
  String get historyNoOtherVideoToCompare => '没有其他影片可供比较';

  @override
  String get historyCompareTitle => '比较挥杆';

  @override
  String historyCompareSubtitle(Object title) {
    return '选择要与「$title」比较的影片';
  }

  @override
  String get historyPhasesJsonMissing => '找不到 phases.json，请重新分析';

  @override
  String get historyPhasesJsonInvalid => 'phases.json 格式错误，请重新分析';

  @override
  String get historySelectAiModeTitle => '选择 AI 模式';

  @override
  String get historyAiModeV1Title => '基础 (V1)';

  @override
  String get historyAiModeV1Desc => '音频峰值检测';

  @override
  String get historyAiModeV2Title => '标准 (V2)';

  @override
  String get historyAiModeV2Desc => '音频 + 骨架混合';

  @override
  String get historyAiModeV3Title => '进阶 (V3)';

  @override
  String get historyAiModeV3Desc => '骨架主导加音频精修';

  @override
  String get historySelectDetectModeTitle => '选择检测模式';

  @override
  String get historyDetectV1Title => '骨架检测 (V1)';

  @override
  String get historyDetectV1Desc => 'MediaPipe 姿势估计';

  @override
  String get historyDetectBadgePrecise => '精准';

  @override
  String get historyDetectV1Time => '~10 秒';

  @override
  String get historyDetectV2Title => '音频检测 (V2)';

  @override
  String get historyDetectV2Desc => '快速音频峰值检测';

  @override
  String get historyDetectBadgeFast => '快速';

  @override
  String get historyDetectV2Time => '~30 秒';

  @override
  String get historyDetectV3Title => '混合检测 (V3)';

  @override
  String get historyDetectV3Desc => '骨架主导加音频精修';

  @override
  String get historyDetectBadgeBalanced => '均衡';

  @override
  String get historyDetectV3Time => '~45 秒';

  @override
  String get historySkipToday => '今日不再提醒';

  @override
  String get historyStartDetect => '开始检测';

  @override
  String get historySelectQualityTitle => '选择导出质量';

  @override
  String get historyStartAnalysis => '开始分析';

  @override
  String get historyActionDetect => '检测杆数';

  @override
  String get historyActionAiAnalysis => 'AI 分析';

  @override
  String get historyActionFullAnalysis => '完整分析';

  @override
  String get historyActionChart => '统计图表';

  @override
  String get historyActionPlay => '播放';

  @override
  String get historyActionExpand => '展开切片';

  @override
  String get historyActionCollapse => '收合切片';

  @override
  String get historyMenuRename => '重命名';

  @override
  String get historyMenuAddNote => '新增备注';

  @override
  String get historyMenuEditNote => '编辑备注';

  @override
  String get historyMenuShare => '分享';

  @override
  String get historyMenuDownload => '下载';

  @override
  String get historyMenuDownloading => '下载中…';

  @override
  String get historyMenuCompare => '比较';

  @override
  String historyMenuUploadReward(int balls) {
    return '上传奖励 +$balls 球';
  }

  @override
  String get historyMenuUploaded => '已上传';

  @override
  String get historyMenuAnalyzing => '分析中…';

  @override
  String get historyMenuDeleteVideo => '删除影片';

  @override
  String get historyMoreActions => '更多操作';

  @override
  String get historyBadgeNoAudio => '无音频';

  @override
  String get historyBadgeAnalyzed => '已分析';

  @override
  String get historySweetSpot => '甜蜜点';

  @override
  String get historySweetSpotHit => '命中';

  @override
  String get historySweetSpotMiss => '未命中';

  @override
  String get historyHitSummary => '击球统计';

  @override
  String historyClipDefaultName(Object index) {
    return '第 $index 杆';
  }

  @override
  String historyClipHitAt(Object time) {
    return '击球 @ $time';
  }

  @override
  String historyClipRange(Object start, Object end) {
    return '片段 $start–$end 秒';
  }

  @override
  String historyRoundLabel(Object index) {
    return '第 $index 轮';
  }

  @override
  String historyDurationLine(Object time, Object seconds) {
    return '$time · $seconds 秒';
  }

  @override
  String historyImportedFrom(Object name) {
    return '来自 $name';
  }

  @override
  String get historyNoteDialogTitle => '影片备注';

  @override
  String get historyNoteHint => '记下练习心得、场地、使用杆型…';

  @override
  String get historyNoteHelper => '可留空以清除备注';

  @override
  String get historySaveLocationTitle => '选择保存位置';

  @override
  String get historySaveLocationDownloads => '下载文件夹';

  @override
  String get historySaveLocationDownloadsSub => '保存到系统默认下载位置';

  @override
  String get historySaveLocationPick => '选择文件夹';

  @override
  String get historySaveLocationPickSub => '自定保存位置';

  @override
  String get historyDownloadVersionTitle => '选择下载版本';

  @override
  String historyExportSaved(Object label) {
    return '「$label」已保存 ✅';
  }

  @override
  String historyExportSavedPhotos(Object label) {
    return '「$label」已保存到相机胶卷 ✅';
  }

  @override
  String historyExportFailed(Object detail) {
    return '下载失败：$detail';
  }

  @override
  String get historyUploadRewardTitle => '上传分析资料';

  @override
  String historyUploadRewardContent(Object title, Object balls) {
    return '将上传「$title」的分析资料，用于改善挥杆检测模型。\n\n上传后需经审核，审核通过将发放 +$balls 球奖励。\n\n确定上传？';
  }

  @override
  String get historyUploadSubmit => '上传送审';

  @override
  String get historyUploadingProgress => '上传影片与分析资料中…';

  @override
  String historyUploadFailed(Object error) {
    return '上传失败：$error';
  }

  @override
  String get historyUploadSubmitFailed =>
      '送审未成功：此影片可能已提交过（含审核未通过者不可重送），或网络异常请稍后再试';

  @override
  String historyUploadReviewPending(Object balls) {
    return '已送出审核，通过后将发放 +$balls 球';
  }

  @override
  String get hitsSummaryEmpty => '尚未检测到任何挥杆';

  @override
  String hitsSummaryHitIndex(int index) {
    return '第 $index 杆';
  }

  @override
  String get hitsSummaryPeak => '峰值';

  @override
  String get hitsSummaryDuration => '时长';

  @override
  String get hitsSummaryStart => '开始';

  @override
  String get hitsSummaryEnd => '结束';

  @override
  String hitsSummaryDetectFrom(String source) {
    return '检测来源：$source';
  }

  @override
  String get hitsSummaryTitle => '挥杆摘要';

  @override
  String hitsSummaryCount(int count) {
    return '共 $count 杆';
  }

  @override
  String get homeCurrentSuggestions => '目前训练建议';

  @override
  String homeNextGoal(String goal) {
    return '下次目标：$goal';
  }

  @override
  String get authInviteCodeOptional => '选填';

  @override
  String get authInviteCodeLabel => '邀请码';

  @override
  String get authInviteCodeHint => '如有好友邀请码，请在此填写';

  @override
  String get authInviteCodeHelper => '填写邀请码，双方各获得 +5 球奖励';

  @override
  String get devTestAccounts => '测试账号';

  @override
  String get devTestPassword => '密码：Test1234!';

  @override
  String get forgotTitle => '忘记密码';

  @override
  String get forgotEnterCodeTitle => '输入验证码';

  @override
  String get forgotEmailSubtitle => '输入您的 Email，我们将发送 6 位数验证码';

  @override
  String forgotCodeSentSubtitle(String email) {
    return '验证码已发送至 $email';
  }

  @override
  String get forgotSixDigitCodeLabel => '6 位验证码';

  @override
  String get forgotNewPasswordLabel => '新密码';

  @override
  String get forgotNewPasswordHint => '至少 8 位，含大写、小写、数字';

  @override
  String get forgotConfirmPasswordLabel => '确认新密码';

  @override
  String get forgotSendCodeButton => '发送验证码';

  @override
  String get forgotConfirmResetButton => '确认重置密码';

  @override
  String get forgotReEnterEmail => '重新输入 Email';

  @override
  String get forgotEnterValidEmail => '请输入有效的 Email';

  @override
  String get forgotSendFailed => '发送失败';

  @override
  String get forgotNetworkError => '网络错误，请稍后再试';

  @override
  String get forgotEnterSixDigitCode => '请输入 6 位数验证码';

  @override
  String get forgotPasswordComplexity => '密码须至少 8 位且包含大写、小写及数字';

  @override
  String get forgotPasswordMismatch => '两次密码不一致';

  @override
  String get forgotResetSuccess => '密码已重置，请用新密码登录';

  @override
  String get forgotResetFailed => '重置失败';

  @override
  String get playerTitle => '视频查看';

  @override
  String get playerNoteAdd => '添加备注';

  @override
  String get playerNoteEdit => '编辑备注';

  @override
  String get playerNoteCleared => '已清除备注';

  @override
  String get playerNoteSaved => '已保存备注';

  @override
  String get playerVideoNotFound => '找不到视频文件';

  @override
  String get playerVideoLoadFailed => '视频加载失败';

  @override
  String get playerSkeletonNotFound => '骨架数据不存在';

  @override
  String get playerOverlaySkeleton => '骨架';

  @override
  String get playerOverlayTrajectory => '轨迹';

  @override
  String get playerOverlayEffect => '特效';

  @override
  String get playerTrajectoryTuning => '轨迹调参';

  @override
  String playerShotLabel(int index, String time) {
    return '第$index球 $time';
  }

  @override
  String get playerStatsEmpty => '暂无统计数据（需轨迹或阶段分析）';

  @override
  String get playerStatLaunchAngle => '发射角';

  @override
  String get playerStatTempo => '节奏 (上杆:下杆)';

  @override
  String get playerStatBackDownswing => '上杆 / 下杆';

  @override
  String get playerStatFlightTime => '入镜飞行';

  @override
  String get playerChartEmpty => '暂无图表数据，请先完成分析';

  @override
  String get playerChartNoData => '无数据';

  @override
  String get playerChartAudioEmpty => '声音峰值 无数据';

  @override
  String get playerChartWristYEmpty => '手腕 Y 无数据';

  @override
  String get playerChartSpeedEmpty => '速度 无数据';

  @override
  String get playerChartTabAudio => '声音峰值';

  @override
  String get playerChartTabWristY => '手腕 Y';

  @override
  String get playerChartTabSpeed => '速度';

  @override
  String get playerChartTabPosture => '姿势';

  @override
  String get playerChartTabAudioFeature => '音频特征';

  @override
  String get playerLoadDetailScore => '加载详细分数';

  @override
  String get playerPostureEmpty => '暂无姿势分析，请先完成分析';

  @override
  String playerAudioPassCount(int count) {
    return '$count / 5 项通过';
  }

  @override
  String get playerAudioEmpty => '暂无音频分析';

  @override
  String playerAiAnalysisFailed(String error) {
    return 'AI 分析失败: $error';
  }

  @override
  String get playerAiNotStarted => '尚未进行 AI 教练分析';

  @override
  String get playerAiStartAnalysis => '开始分析';

  @override
  String get playerAiViewProgress => '查看进度';

  @override
  String get playerAiCoachTitle => 'AI 教练分析';

  @override
  String get playerAiPrimaryIssue => '主要问题';

  @override
  String get playerAiCoachFeedback => '教练评语';

  @override
  String get playerAiPracticeSuggestions => '训练建议';

  @override
  String get playerAiNextGoal => '下次目标';

  @override
  String get playerAiReanalyze => '重新分析';

  @override
  String get playerAiViewDetail => '查看详细';

  @override
  String get playerAiStatusPending => '准备中...';

  @override
  String get playerAiStatusQueued => '等待分析队列...';

  @override
  String get playerAiStatusProcessing => 'AI 教练分析中...';

  @override
  String get playerAiStatusAnalyzing => '分析中...';

  @override
  String get playerSeverityHigh => '严重';

  @override
  String get playerSeverityMedium => '中等';

  @override
  String get playerSeverityLow => '轻微';

  @override
  String get playerHighlightPreview => '精彩片段预览';

  @override
  String get playerSweetSpotHit => '甜蜜点命中';

  @override
  String get playerSweetSpot => '甜蜜点';

  @override
  String get playerThinShot => '偏虚球';

  @override
  String playerAudioPassCountBadge(int count) {
    return '$count/5 特征符合';
  }

  @override
  String get playerNoteDialogTitle => '视频备注';

  @override
  String get playerNoteHint => '记下练习心得、场地、使用杆型…';

  @override
  String get playerNoteHelper => '可留空以清除备注';

  @override
  String get playerPhaseAddress => '准备';

  @override
  String get playerPhaseTakeaway => '起杆';

  @override
  String get playerPhaseBackswing => '上杆';

  @override
  String get playerPhaseTop => '顶点';

  @override
  String get playerPhaseDownswing => '下杆';

  @override
  String get playerPhaseImpact => '击球';

  @override
  String get clipLegendStart => '开始';

  @override
  String get clipLegendEnd => '结束';

  @override
  String get playerPhaseFollowthrough => '送杆';

  @override
  String get playerPhaseFinish => '收杆';

  @override
  String get postureTitle => '姿势分析';

  @override
  String get postureNoData => '暂无 AI 分析数据';

  @override
  String get profileSubtitle => '调整个人信息以获得更精准的挥杆分析，完成后记得保存。';

  @override
  String get profileAvatarHint => '设置个人头像让教练更容易识别';

  @override
  String get profileAvatarSaveFailed => '保存头像失败，请稍后再试。';

  @override
  String get profileDisplayNameLabel => '昵称';

  @override
  String get profileDisplayNameHint => '输入想在首页显示的名称';

  @override
  String get profileDisplayNameRequired => '请输入昵称';

  @override
  String get profileEmailLabel => '电子邮件';

  @override
  String get profilePhoneLabel => '联系电话';

  @override
  String get profilePhoneHint => '例：0912-345-678';

  @override
  String get profileHandicapLabel => '差点';

  @override
  String get profileHandicapHint => '可填写目前差点或目标数值';

  @override
  String get purchaseTestPanelTitle => '🧪 购买测试面板';

  @override
  String get purchaseTestSimulateSuccessMsg => '✅ 模拟购买成功！用户已设置为高级用户';

  @override
  String purchaseTestErrorMsg(String error) {
    return '❌ 错误: $error';
  }

  @override
  String get purchaseTestClearSuccessMsg => '🔄 已清除购买记录！用户现在是普通用户';

  @override
  String get purchaseTestPremiumStatusLabel => '高级用户状态: ';

  @override
  String get purchaseTestStatusPurchased => '✅ 已购买';

  @override
  String get purchaseTestStatusNotPurchased => '❌ 未购买';

  @override
  String purchaseTestPaymentMethod(String method) {
    return '支付方式: $method';
  }

  @override
  String get purchaseTestPaymentMethodNone => '无';

  @override
  String get purchaseTestSimulateBtn => '模拟购买成功';

  @override
  String get purchaseTestClearBtn => '清除购买';

  @override
  String get purchaseTestRefreshBtn => '刷新状态';

  @override
  String get purchaseTestDialogTitle => '🧪 购买功能测试';

  @override
  String get recDetailDownloadVideo => '下载视频';

  @override
  String get exportCustomTitle => '自定义导出';

  @override
  String get exportCustomSubtitle => '选择要烧录到视频上的元素';

  @override
  String get exportElementSkeleton => '骨架';

  @override
  String get exportElementSkeletonDesc => '挥杆姿势关节骨架';

  @override
  String get exportElementTrajectory => '球轨迹';

  @override
  String get exportElementTrajectoryDesc => '击球后球体飞行轨迹';

  @override
  String get exportElementGlow => '击球光晕';

  @override
  String get exportElementGlowDesc => '击球瞬间的扩散光圈';

  @override
  String get exportElementSweetSpot => '甜蜜点';

  @override
  String get exportElementSweetSpotDesc => '击球质量光圈（金／蓝／灰）';

  @override
  String get swingBothHands => '双手判断';

  @override
  String get swingBothHandsDesc => '双手腕一起移动才算一次挥杆；其中一手被遮挡时自动改用另一手';

  @override
  String get exportNoOverlayMaterial => '此视频没有可叠加的分析素材，将输出原片。';

  @override
  String get exportWatermarkFree => '免费版成品将含 ORVIA 水印，升级可移除';

  @override
  String get exportWatermarkPaid => '已订阅：成品不含水印';

  @override
  String get exportComposeAndDownload => '合成并下载';

  @override
  String get recDetailNoVideoFound => '找不到可下载的视频';

  @override
  String recDetailBurning(String label) {
    return '渲染「$label」中…';
  }

  @override
  String get recDetailBurnFailed => '渲染失败，请稍后重试';

  @override
  String recDetailSavedToDownloads(String label) {
    return '「$label」已保存到下载文件夹 ✅';
  }

  @override
  String recDetailSavedToPhotos(String label) {
    return '「$label」已保存到相册 ✅';
  }

  @override
  String get recDetailSharedViaSheet => '已打开分享 ✅';

  @override
  String recDetailDownloadFailed(String detail) {
    return '下载失败：$detail';
  }

  @override
  String get recDetailSkeletonPreview => '骨架预览';

  @override
  String get recDetailSkeletonLoadFailed => '骨架预览加载失败';

  @override
  String get recDetailAudioPeak => '声音峰值';

  @override
  String get recDetailAudioPeakSubtitle => 'RMS dBFS';

  @override
  String get recDetailAudioPeakMissing => '需完成音频分析';

  @override
  String get recDetailWristY => '手腕 Y';

  @override
  String get recDetailWristYSubtitle => '右手腕 Y 位置（像素）';

  @override
  String get recDetailPoseMissing => '需完成姿势分析';

  @override
  String get recDetailSpeedSubtitle => '手腕移动速度（px/frame）';

  @override
  String get recDetailSpeedMissing => '速度';

  @override
  String get recDetailSweetSpot => '甜蜜点';

  @override
  String get recDetailOffCenter => '击球偏虚';

  @override
  String get recDetailAudioFeaturesTitle => '音频特征分析';

  @override
  String recDetailFeaturePassCount(int count) {
    return '$count / 5 项特征符合甜蜜点范围';
  }

  @override
  String get recDetailAutoAnalyzing => '姿势分析上传中，请稍候…';

  @override
  String get recDetailOnnxTitle => 'ONNX 姿势分析';

  @override
  String recDetailOnnxLoadFailed(String error) {
    return '加载失败: $error';
  }

  @override
  String get recDetailOnnxNoResult => '暂无 ONNX 结果';

  @override
  String get recDetailOnnxNoScores => '无分数数据';

  @override
  String get recDetailSwingPhases => '挥杆阶段';

  @override
  String get recDetailRegenerate => '重新生成';

  @override
  String get recDetailGeneratePhases => '生成阶段';

  @override
  String get recDetailNoChartData => '暂无图表数据';

  @override
  String get recDetailNoChartHint => '请先完成音频分析与姿势分析';

  @override
  String get recDetailLoadFailed => '加载失败';

  @override
  String get recDetailSelectDownloadVersion => '选择下载版本';

  @override
  String get recDetailOptLabelFull => '分析完整版';

  @override
  String get recDetailOptDescFull => '骨架 + 球轨迹';

  @override
  String get recDetailOptLabelSkeleton => '骨架版';

  @override
  String get recDetailOptDescSkeleton => '仅含骨架 overlay';

  @override
  String get recDetailOptLabelClip => '原始片段';

  @override
  String get recDetailOptDescNoOverlay => '无任何 overlay';

  @override
  String get recDetailOptLabelRaw => '原始视频';

  @override
  String get recDetailOptLabelRawMov => '原始视频 (MOV)';

  @override
  String get recDetailOptDescRawMov => '原始 MOV 文件';

  @override
  String get recDetailPhaseAddress => '①准备';

  @override
  String get recDetailPhaseTakeaway => '②起杆';

  @override
  String get recDetailPhaseBackswing => '③上杆';

  @override
  String get recDetailPhaseTop => '④顶点';

  @override
  String get recDetailPhaseDownswing => '⑤下杆';

  @override
  String get recDetailPhaseImpact => '⑥击球';

  @override
  String get recDetailPhaseFollowthrough => '⑦送杆';

  @override
  String get recDetailPhaseFinish => '⑧收杆';

  @override
  String get recHistSheetEmptyHint => '目前没有录影记录，完成录影后会自动显示在此处。';

  @override
  String get recHistSheetPickFromFolder => '从文件文件夹选取视频';

  @override
  String recHistSheetDurationSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get recSelPreparingProgress => '准备中...';

  @override
  String get recSelAnalyzingDialogTitle => '影片分析中';

  @override
  String get recSelNoFileSelected => '❌ 未选择任何文件';

  @override
  String recSelVideoTooLong(int durationSec) {
    return '❌ 影片超过 10 分钟限制（$durationSec 秒）\n请选择 600 秒以内的影片';
  }

  @override
  String recSelVideoDurationOk(int durationSec) {
    return '✅ 影片时长 $durationSec 秒，符合 10 分钟限制';
  }

  @override
  String get recSelImportFailed => '❌ 导入失败\n文件可能不存在或格式不支持';

  @override
  String recSelImportSuccess(String name, String duration) {
    return '✅ 导入成功！\n$name\n时长: $duration';
  }

  @override
  String recSelImportError(String error) {
    return '❌ 导入出错\n$error';
  }

  @override
  String get recSelImportingVideo => '正在导入影片...';

  @override
  String get recSelDoNotClose => '请勿关闭应用';

  @override
  String get recSelShotModeTitle => '即时挥杆模式';

  @override
  String get recSelShotModeSubtitle => '挥杆自动检测并切片，无需录长影片';

  @override
  String get recSelNewFeatureBadge => '新功能';

  @override
  String get recSelRecordTitle => '开始录制';

  @override
  String get recSelRecordSubtitle => '即时拍摄并进行挥杆分析';

  @override
  String get recSelLocalVideoTitle => '选择本地影片';

  @override
  String get recSelLocalVideoSubtitle => '从设备中选择已有影片（上限 10 分钟）';

  @override
  String get recSelShareLinkTitle => '从分享链接获取';

  @override
  String get recSelShareLinkSubtitle => '输入 16 位分享码下载影片';

  @override
  String get recSelHeaderTitle => '选择录制方式';

  @override
  String get recSelHeaderSubtitle => '即时拍摄、导入本地影片或通过分享码获取';

  @override
  String get recSelIOSSourceSheetTitle => '选择影片来源';

  @override
  String get recSelPhotoLibrary => '相册';

  @override
  String get recSelFilesApp => '文件 App（文件夹）';

  @override
  String recTabsTitle(int count) {
    return '录影历史 ($count)';
  }

  @override
  String get recTabsEmpty => '没有录影记录';

  @override
  String get recTabsEmptyHint => '完成新的录影后，将在此显示';

  @override
  String recTabsMode(String label) {
    return '模式：$label';
  }

  @override
  String recTabsDuration(int seconds) {
    return '时长：$seconds秒';
  }

  @override
  String get recordTitle => '高尔夫挥杆录制';

  @override
  String get recordOverlayToggle => '轮廓叠加切换';

  @override
  String get recordSettings => '录制设置';

  @override
  String get recordPermissionTitle => '需要相机与麦克风权限';

  @override
  String get recordPermissionMicOnly => '录影需要麦克风权限以录制击球声，请开启后再试。';

  @override
  String get recordPermissionCameraAndMic => '挥杆录影需要相机与麦克风权限，请开启后再试。';

  @override
  String get recordGoToSettings => '前往设置';

  @override
  String get recordGotIt => '知道了';

  @override
  String get recordLowEndDeviceWarning => '此设备不支持录影期间同步骨架检测，录影结束后恢复';

  @override
  String get recordFailed => '本次录制失败（未取得有效影像），请重新录制';

  @override
  String get recordVideoQuality => '视频画质';

  @override
  String get recordFrameRate => '帧率';

  @override
  String get recordAudio => '录制音频';

  @override
  String get recordApply => '套用';

  @override
  String get rewardTitle => '奖励球数';

  @override
  String get rewardUsageHistoryTooltip => '使用记录';

  @override
  String rewardEarnedSnackbar(String source, int balls) {
    return '通过「$source」获得 +$balls 额外球数！';
  }

  @override
  String rewardUploadSubmittedPending(int pending) {
    return '已送出 $pending 笔审核，通过后将发放球数奖励';
  }

  @override
  String get rewardUploadSubmittedDuplicate => '资料已提交（重复资料不再送审）';

  @override
  String get rewardStatBonusBalls => '累计奖励';

  @override
  String get rewardUnitBall => '球';

  @override
  String get rewardStatAdToday => '今日广告';

  @override
  String get rewardAdDailyUnit => '/ 5 次';

  @override
  String get rewardStatInvites => '邀请好友';

  @override
  String get rewardUnitPerson => '位';

  @override
  String rewardBallsBadge(int balls) {
    return '+$balls 球';
  }

  @override
  String rewardAdProgress(int used, int cap) {
    return '$used / $cap 次';
  }

  @override
  String get rewardDoneToday => '今日已完成';

  @override
  String get rewardAdNotCompleted => '广告未播放完成或暂时无法加载，请稍后再试';

  @override
  String rewardAdFailed(String error) {
    return '广告奖励失败：$error';
  }

  @override
  String get rewardWatchAdTitle => '看广告';

  @override
  String rewardWatchAdButton(int balls) {
    return '观看广告 +$balls 球';
  }

  @override
  String get rewardInviteFriendTitle => '邀请好友';

  @override
  String rewardInviteFriendDesc(int balls) {
    return '好友使用邀请码注册后，你获得 +$balls 球，好友也获得 +$balls 球';
  }

  @override
  String get rewardGetInviteCode => '获取邀请码';

  @override
  String get rewardYourInviteCode => '你的邀请码';

  @override
  String get rewardInviteCodeCopied => '邀请码已复制';

  @override
  String get rewardInvitedFriends => '已邀请好友';

  @override
  String get rewardNoInviteHistory => '暂无邀请记录';

  @override
  String get rewardShareInviteHint => '分享你的邀请码，邀请好友一起练习！';

  @override
  String get rewardEnterCodeTitle => '输入邀请码';

  @override
  String rewardEnterCodeDesc(int balls) {
    return '输入好友的邀请码，你获得 +$balls 球，好友也获得 +$balls 球';
  }

  @override
  String get rewardEnterCodeEmpty => '请输入邀请码';

  @override
  String get rewardInviteCodeInvalid => '邀请码无效';

  @override
  String rewardApplyFailed(String error) {
    return '套用失败：$error';
  }

  @override
  String get rewardApplying => '套用中...';

  @override
  String rewardApplyButton(int balls) {
    return '套用 +$balls 球';
  }

  @override
  String get rewardEnterFriendCode => '输入好友邀请码';

  @override
  String get rewardFeedbackTitle => '问题反馈';

  @override
  String get rewardFeedbackTypeBug => '🐛 问题反馈';

  @override
  String get rewardFeedbackTypeFeature => '💡 功能建议';

  @override
  String get rewardFeedbackTypeOther => '💬 其他';

  @override
  String get rewardFeedbackHint => '请详细描述你的反馈...';

  @override
  String get rewardSelectVideo => '选择影片';

  @override
  String get rewardChangeVideo => '更换影片';

  @override
  String get rewardUploadImage => '上传图片';

  @override
  String get rewardChangeImage => '更换图片';

  @override
  String get rewardFeedbackEmpty => '请输入反馈内容';

  @override
  String get rewardFeedbackSubmitted => '反馈已送出，感谢你的意见！';

  @override
  String rewardSubmitFailed(String error) {
    return '提交失败：$error';
  }

  @override
  String get rewardSubmitFeedback => '送出反馈';

  @override
  String rewardSubmitFeedbackWithBalls(int balls) {
    return '送出反馈 +$balls 球';
  }

  @override
  String get rewardWriteFeedback => '填写反馈';

  @override
  String rewardWriteFeedbackWithBalls(int balls) {
    return '填写反馈 +$balls 球';
  }

  @override
  String get rewardNoVideoHistory => '暂无历史录影';

  @override
  String get rewardLongVideo => '长影片';

  @override
  String get rewardShortVideo => '短影片';

  @override
  String get rewardUploadDataTitle => '上传分析资料';

  @override
  String get rewardNoUploadable => '目前没有可上传的分析资料';

  @override
  String rewardUploadPartialFail(int count) {
    return '$count 笔上传失败，已略过';
  }

  @override
  String get rewardUploadFailed => '上传失败，请稍后再试';

  @override
  String get rewardUploadResubmitBlocked =>
      '送审未成功：资料可能已提交过（含审核未通过者不可重送），或网络异常请稍后再试';

  @override
  String rewardUploadError(String error) {
    return '上传失败：$error';
  }

  @override
  String rewardUploadAvailableCount(int available, int uploaded) {
    return '可上传 $available 笔，已上传 $uploaded 笔';
  }

  @override
  String rewardUploadAllDone(int count) {
    return '所有分析资料已上传（共 $count 笔）';
  }

  @override
  String rewardUploadReviewStatus(int pending, int approved) {
    return '审核中 $pending 笔 / 已通过 $approved 笔';
  }

  @override
  String rewardUploadRejectedSuffix(int count) {
    return ' / 未通过 $count 笔';
  }

  @override
  String get rewardUploadRejectedNote => '未通过审核的资料不可重新提交';

  @override
  String get rewardSelectUploadVideo => '选择要上传的录影';

  @override
  String get rewardSelectUploadSubtitle => '选择一笔后按「确认上传」获得奖励';

  @override
  String get rewardNoneSelected => '尚未选择';

  @override
  String get rewardOneSelected => '已选 1 笔';

  @override
  String rewardConfirmUpload(int balls) {
    return '确认上传 +$balls 球';
  }

  @override
  String get rewardAnalyzed => '已分析';

  @override
  String rewardDurationSec(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get settingsNameSyncFailed => '名称已更新，但服务器同步失败';

  @override
  String get settingsGoogleCredentialFailed => '无法获取 Google 凭证，请重试';

  @override
  String get settingsGoogleLinkFailed => 'Google 绑定失败，请稍后再试';

  @override
  String get shareImportTitle => '从分享链接获取';

  @override
  String get shareImportEnterCodeTitle => '输入 16 位分享码';

  @override
  String get shareImportEnterCodeDesc => '对方分享后，输入分享码即可下载影片到本机';

  @override
  String get shareImportCodeValidator => '请输入完整的 16 位分享码';

  @override
  String get shareImportLooking => '查询中…';

  @override
  String get shareImportLookup => '查询';

  @override
  String get shareImportFrom => '来自';

  @override
  String get shareImportSize => '大小';

  @override
  String get shareImportExpiry => '到期';

  @override
  String get shareImportReenter => '重新输入';

  @override
  String get shareImportDownload => '下载到本机';

  @override
  String get shareImportPreparing => '准备下载…';

  @override
  String get shareImportDownloading => '下载中…';

  @override
  String get shareImportExtracting => '解压缩中…';

  @override
  String get shareImportDoneTitle => '下载完成！';

  @override
  String get shareImportDoneDesc => '影片已加入历史记录';

  @override
  String get shareImportBack => '返回';

  @override
  String get shareUploadTitle => '分享链接';

  @override
  String get shareUploadChecking => '检查分享状态…';

  @override
  String get shareUploadCompressing => '压缩中…';

  @override
  String get shareUploadUnknownError => '未知错误';

  @override
  String shareUploadUploading(String percent) {
    return '上传中…  $percent%';
  }

  @override
  String get shareUploadCodeReused => '现有分享码（尚未过期）';

  @override
  String get shareUploadCodeNew => '分享码（有效 1 天）';

  @override
  String get shareUploadCopy => '复制';

  @override
  String get shareUploadCopied => '已复制分享码';

  @override
  String shareUploadShareText(String code) {
    return '高尔夫挥杆分享码：$code\n（有效 1 天，请在 App 中输入此码获取视频）';
  }

  @override
  String get shareUploadSystemShare => '系统分享';

  @override
  String get shotRecTitle => '实时挥杆模式';

  @override
  String get shotRecSettings => '录制设置';

  @override
  String shotRecShotsCompleted(int count) {
    return '已完成 $count 杆';
  }

  @override
  String get shotRecReady => '准备';

  @override
  String get shotRecCalibrating => '校准中…请保持静止';

  @override
  String shotRecAddressPrompt(int current, int total) {
    return '请站到准备姿势 ($current/$total)';
  }

  @override
  String get shotRecAddressSubText => '站定后将自动开始录影';

  @override
  String get shotRecDetecting => '⚡ 检测中…请挥杆';

  @override
  String get shotRecStop => '停止';

  @override
  String shotRecSwingDetected(String seconds) {
    return '检测到挥杆 ✓\n倒数 ${seconds}s';
  }

  @override
  String get shotRecAnalyzing => '分析中…';

  @override
  String get shotRecExtractingAudio => '提取音频…';

  @override
  String get shotRecDetectingImpact => '检测击球…';

  @override
  String get shotRecClipping => '切片中…';

  @override
  String get shotRecScoringAudio => '声音分析中…';

  @override
  String get shotRecDone => '完成！';

  @override
  String get shotRecWatch => '观看';

  @override
  String shotRecNextShot(int countdown) {
    return '下一杆 ($countdown)';
  }

  @override
  String get shotRecVideoQuality => '视频画质';

  @override
  String get shotRecFrameRate => '帧率';

  @override
  String get shotRecEnableAudio => '录制音频';

  @override
  String get shotRecApply => '套用';

  @override
  String get shotRecAddressTimeout => '未检测到准备姿势，已取消';

  @override
  String get shotRecNoAnalysisWarning => '此设备不支持录影期间同步骨架检测，仍会自动检测挥杆';

  @override
  String get shotRecRecordFailed => '本次挥杆录制失败（未取得有效影像），请重试';

  @override
  String get shotRecNoSwingDetected => '未检测到挥杆，请重试';

  @override
  String get shotRecClipFailed => '切片失败，请重试';

  @override
  String shotRecLiveShotName(int number) {
    return '即时第$number杆';
  }

  @override
  String get termsPageSubtitle => '用户条款与隐私政策';

  @override
  String get termsReadPrompt => '请阅读以下条款后，勾选同意即可开始使用';

  @override
  String get termsScrolledToBottom => '已阅读至条款末端，请返回顶部勾选同意。';

  @override
  String get termsDeclineTitle => '确认离开';

  @override
  String get termsDeclineContent => '不同意用户条款将无法使用 ORVIA。确定要离开吗？';

  @override
  String get termsDeclineBack => '返回';

  @override
  String get termsDeclineExit => '离开';

  @override
  String get termsPrivacyOpenFailed => '无法打开隐私政策页面，请稍后再试';

  @override
  String get termsAgreePrefix => '我已阅读并同意《用户条款》与《';

  @override
  String get termsPrivacyLink => '隐私政策';

  @override
  String get termsAgreeSuffix => '》';

  @override
  String get termsAnalyticsTitle => '允许使用统计追踪（可选）';

  @override
  String get termsAnalyticsDesc => '协助我们改善 App 体验，不包含个人身份信息';

  @override
  String get termsScrollFirst => '请先滑动阅读完整条款后方可勾选同意';

  @override
  String get termsDisagree => '不同意';

  @override
  String get termsAgreeAndContinue => '同意并继续';

  @override
  String get termsOpenPrivacyFull => '打开完整隐私政策';

  @override
  String get termsSec1Title => '一、服务说明';

  @override
  String get termsSec1Body =>
      'ORVIA（以下简称「本服务」）由 ORVIA 团队提供，旨在协助用户通过移动设备录制、分析高尔夫挥杆动作，并提供相关数据统计与建议。\n\n使用本服务前，请仔细阅读以下条款。一旦您开始使用本服务，即表示您已阅读、理解并同意本条款的所有内容。';

  @override
  String get termsSec2Title => '二、账号与安全';

  @override
  String get termsSec2Body =>
      '1. 您须通过电子邮件或 Google 账号完成注册，方可使用完整功能。\n2. 您有责任妥善保管账号密码，并对所有使用您账号进行的活动负责。\n3. 若发现账号遭未授权使用，请立即通知我们。\n4. 您不得将账号转让给他人。';

  @override
  String get termsSec3Title => '三、用户行为规范';

  @override
  String get termsSec3Body =>
      '使用本服务时，您同意：\n\n1. 仅上传您本人拍摄或拥有合法授权的视频内容。\n2. 不上传任何违法、侵权或不当内容。\n3. 不干扰或破坏本服务的正常运作。\n4. 不尝试未授权访问本服务的系统或数据。';

  @override
  String get termsSec4Title => '四、视频与数据处理';

  @override
  String get termsSec4Body =>
      '1. 您上传的视频与分析数据将储存于本服务的云端系统，以提供挥杆分析功能。\n2. 分享功能生成的分享链接有效期为 1 天，到期后将自动删除相关文件。\n3. 您可随时在 App 内删除个人数据及录影记录。\n4. 我们不会将您的个人视频提供给未经授权的第三方。';

  @override
  String get termsSec5Title => '五、隐私政策';

  @override
  String get termsSec5Body =>
      '我们重视您的隐私，并依照以下原则收集与使用您的信息：\n\n收集的信息：\n• 账号信息（电子邮件、显示名称）\n• 挥杆视频及分析结果\n• 设备信息与使用记录\n\n使用统计追踪（需您同意）：\n• 我们可能收集匿名使用数据（功能点击、页面浏览等）\n• 用于改善 App 体验与功能设计\n• 不包含个人身份信息，可随时在设置中关闭\n\n数据保护：\n• 所有数据传输采用 TLS 加密\n• 服务器端数据进行加密存储\n• 定期进行安全审计\n\n完整隐私政策请见：https://orvia.atk.tw/privacy.html';

  @override
  String get termsSec6Title => '六、知识产权';

  @override
  String get termsSec6Body =>
      '1. 本服务的软件、界面设计、商标及所有相关内容均属 ORVIA 所有，受著作权法保护。\n2. 您上传的视频著作权归您所有，但您授予本服务使用这些内容以提供分析服务的有限授权。\n3. 未经授权，您不得复制、修改或散布本服务的任何部分。';

  @override
  String get termsSec7Title => '七、免责声明';

  @override
  String get termsSec7Body =>
      '1. 本服务提供的挥杆分析结果仅供参考，不构成专业运动指导建议。\n2. 本服务以「现状」提供，不保证服务永远不中断或无误差。\n3. 对于因使用本服务所产生的任何直接或间接损失，本服务不负赔偿责任。\n4. 挥杆练习涉及身体活动，请在安全环境下进行，并自行评估身体状况。';

  @override
  String get termsSec8Title => '八、服务变更与终止';

  @override
  String get termsSec8Body =>
      '1. 我们保留在任何时间修改、暂停或终止本服务的权利。\n2. 若本条款有重大变更，我们将通过 App 通知您。\n3. 继续使用本服务视为接受更新后的条款。';

  @override
  String get termsSec9Title => '九、联系我们';

  @override
  String get termsSec9Body =>
      '若您对本条款有任何疑问，请通过以下方式联系我们：\n\n电子邮件：support@atk.tw\n服务网站：https://orvia.atk.tw\n隐私政策：https://orvia.atk.tw/privacy.html\n\n本条款最后更新日期：2026 年 5 月 25 日';

  @override
  String get testVideoTitle => '选择测试视频';

  @override
  String testVideoLoadError(String error) {
    return '加载视频失败\n$error';
  }

  @override
  String get testVideoEmpty => '暂无已导入的视频';

  @override
  String get testVideoSelect => '选择';

  @override
  String get testVideoHint => '💡 提示：选择一个视频作为测试录制，用于演示和测试分析功能';

  @override
  String get upgradeSubscribed => '已订阅';

  @override
  String get upgradeCurrentPlanActive => '当前方案';

  @override
  String get upgradeMonthly => '月付';

  @override
  String get upgradeYearly => '年付（享约 2 个月折扣）';

  @override
  String upgradeSubscribeFailed(String error) {
    return '订阅失败：$error';
  }

  @override
  String get upgradeProductLoadFailed => '商品加载失败，请稍后再试';

  @override
  String get upgradeAppStoreSubscribe => 'App Store 订阅';

  @override
  String get upgradeGooglePlaySubscribe => 'Google Play 订阅';

  @override
  String get upgradeManageSubscriptionIos => '订阅后可随时在 App Store 管理或取消';

  @override
  String get upgradeManageSubscriptionAndroid => '订阅后可随时在 Google Play 管理或取消';

  @override
  String get upgradeBuyBalls => '单买球数';

  @override
  String get upgradeNoExpiry => '不限时间使用';

  @override
  String upgradeBallCount(int count) {
    return '$count 球';
  }

  @override
  String get upgradeBallPackValidity => '永久有效，随时使用';

  @override
  String get upgradeBuyButton => '购买';

  @override
  String upgradePurchaseFailed(String error) {
    return '购买失败：$error';
  }

  @override
  String upgradeBuyBallCount(int count) {
    return '购买 $count 球';
  }

  @override
  String get upgradeBallPackDescription => '球数永久有效，不限时间使用。用完每日配额后自动消耗。';

  @override
  String get upgradeAppStorePurchase => 'App Store 购买';

  @override
  String get upgradeGooglePlayPurchase => 'Google Play 购买';

  @override
  String get usageTitle => '使用记录';

  @override
  String get usageSubtitle => 'AI 分析 & 球数流水账';

  @override
  String get usageTabAnalysis => 'AI 分析记录';

  @override
  String get usageTabBalls => '球数流水账';

  @override
  String get usageLoadFailed => '加载失败，请下拉重试';

  @override
  String usageLoadError(String error) {
    return '加载错误：$error';
  }

  @override
  String get usageEmptyAnalysis => '暂无分析记录';

  @override
  String get usageAllLoaded => '已加载全部记录';

  @override
  String get usageSummaryTotalAnalysis => '累计分析';

  @override
  String get usageUnitTimes => '次';

  @override
  String get usageSummaryTodayUsed => '今日已用';

  @override
  String get usageAnalysisItemTitle => 'AI 挥杆分析';

  @override
  String get usageSourceDailyQuota => '每日配额';

  @override
  String get usageSourceBonusBall => '奖励球';

  @override
  String get usageSourceDailyQuotaDesc => '使用每日配额';

  @override
  String get usageSourceBonusBallDesc => '消耗 1 颗球';

  @override
  String get usageEmptyBalls => '暂无球数记录';

  @override
  String get usageSummaryTotalRecords => '累计笔数';

  @override
  String get usageUnitRecords => '笔';

  @override
  String get usageSummaryCurrentBalls => '当前球数';

  @override
  String get usageUnitBalls => '球';

  @override
  String usageBallBalance(int balance) {
    return '余额 $balance 球';
  }

  @override
  String get usageDateToday => '今天';

  @override
  String get usageDateYesterday => '昨天';

  @override
  String waveformCrispScore(int score) {
    return '清脆度 $score';
  }

  @override
  String waveformPeakLabel(String level) {
    return '峰值 $level';
  }

  @override
  String get extImportProgressCopying => '复制视频中...';

  @override
  String get extImportProgressTranscoding => '转档准备中...';

  @override
  String get extImportProgressDurationInvalid => '视频时长不符 (需 1-600 秒)';

  @override
  String get extImportProgressThumbnail => '生成缩图中...';

  @override
  String get extImportProgressDone => '导入完成 ✅';

  @override
  String get learnHubGoodSwingTitle => '良好挥杆示范';

  @override
  String get learnHubGoodSwingDesc => '节奏平顺、重心稳定、击球后收杆完整。';

  @override
  String get learnHubEarlyReleaseTitle => '常见错误：提前释放';

  @override
  String get learnHubEarlyReleaseDesc => '手腕提前放松，导致杆头加速度不足，球路弱/右曲。';

  @override
  String get learnHubMarkerBackswingTop => '上杆顶点';

  @override
  String get learnHubMarkerBackswingTopNote => '重心仍在脚中，杆身与手臂成直线';

  @override
  String get learnHubMarkerImpact => '击球瞬间';

  @override
  String get learnHubMarkerImpactNote => '手位在球前方，身体旋转带动击球';

  @override
  String get learnHubMarkerFinish => '收杆';

  @override
  String get learnHubMarkerFinishNote => '重心转向前脚，身体保持平衡';

  @override
  String get learnHubMarkerEarlyReleaseTopNote => '手腕角度过早放松，杆头落后';

  @override
  String get learnHubMarkerPreImpact => '击球前';

  @override
  String get learnHubMarkerPreImpactNote => '手部领先不足，重心偏后';

  @override
  String get learnHubMarkerEarlyReleaseFinishNote => '重心未移到前脚，平衡不佳';

  @override
  String get playerTimelineAbbrAddress => '准';

  @override
  String get playerTimelineAbbrTakeaway => '起';

  @override
  String get playerTimelineAbbrBackswing => '上';

  @override
  String get playerTimelineAbbrTop => '顶';

  @override
  String get playerTimelineAbbrDownswing => '下';

  @override
  String get playerTimelineAbbrImpact => '击';

  @override
  String get playerTimelineAbbrFollowthrough => '送';

  @override
  String get playerTimelineAbbrFinish => '收';

  @override
  String get recHistSheetTitle => '曾经录影记录';

  @override
  String get recTabsToday => '今天';

  @override
  String get recTabsYesterday => '昨天';

  @override
  String recTabsDateMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get recWidgetsZoomWide => '最广';

  @override
  String get recWidgetsSavingVideo => '保存视频中…';

  @override
  String get rewardFriendFallbackName => '好友';

  @override
  String get upgradeHighlightFullFeatured => '完整录影与分析功能';

  @override
  String get upgradeHighlightAiDaily10 => 'AI 教练分析每日 10 次';

  @override
  String get upgradeHighlightBuyMore => '球数用完可购买加值';

  @override
  String get upgradeHighlightAiDaily90 => 'AI 教练分析每日 90 次';

  @override
  String get upgradeHighlightAiUnlimited => 'AI 教练分析无限次';

  @override
  String get upgradeFeatureAutoClip => '长视频自动切片';

  @override
  String get upgradeFeatureVoiceHint => '实时语音提示';

  @override
  String get upgradeFeatureAudioScore => '音频分析（击球评分）';

  @override
  String get upgradeFeatureDualVideo => '双视频比较';

  @override
  String get upgradeFeatureAiCoachAnalysis => 'AI 教练分析';

  @override
  String get upgradeQuotaDaily10 => '每日10球';

  @override
  String get upgradeQuotaDaily90 => '每日90球';

  @override
  String get upgradeQuotaUnlimited => '无限';

  @override
  String get upgradeBadgePopular => '热门';

  @override
  String get upgradeBadgeValue => '划算';

  @override
  String get upgradeBadgeBestDeal => '最优惠';

  @override
  String get upgradePerYear => '/年';

  @override
  String get usageReasonAd => '看广告奖励';

  @override
  String get usageReasonFeedback => '问题反馈奖励';

  @override
  String get usageReasonInvite => '邀请好友奖励';

  @override
  String get usageReasonUpload => '上传数据奖励';

  @override
  String get usageReasonAnalysis => 'AI 分析消耗';

  @override
  String get usageReasonManual => '手动调整';

  @override
  String get usageReasonOther => '其他';

  @override
  String get waveformPeakHigh => '高';

  @override
  String get waveformPeakMid => '中';

  @override
  String get waveformPeakLow => '低';

  @override
  String get waveformFreqCrispy => '偏清脆';

  @override
  String get waveformFreqMid => '中音';

  @override
  String get waveformFreqMuffled => '偏闷';

  @override
  String get historyProgressV2AudioScan => 'V2 音频扫描中...';

  @override
  String get historyProgressV3AudioScan => 'V3 音频扫描中...';

  @override
  String get historyProgressWaitingConfirm => '等待确认片段...';

  @override
  String get historyProgressClipping => '裁切片段中...';

  @override
  String historyProgressClippingPct(int pct, int cur, int total) {
    return '裁切片段中... $pct% ($cur/$total)';
  }

  @override
  String historyProgressV3SkeletonAnalysis(int cur, int total) {
    return 'V3 骨架分析 $cur/$total';
  }

  @override
  String historyProgressV3SkeletonItem(int cur, int total) {
    return '第$cur/$total个';
  }

  @override
  String get historyProgressDetectingHit => '检测击球中...';

  @override
  String get historyProgressVideoAnalysis => '视频分析中...';

  @override
  String get historyProgressDetectingPhase => '检测挥杆阶段...';

  @override
  String get historyProgressAudioAnalysis => '音频分析中...';

  @override
  String get historyDlLabelFull => '完整分析';

  @override
  String get historyDlDescFull => '骨架 + 球轨迹 overlay';

  @override
  String get historyDlLabelSkeleton => '骨架版';

  @override
  String get historyDlDescSkeleton => '只含骨架 overlay';

  @override
  String get historyDlLabelClip => '原始切片';

  @override
  String get historyDlDescClip => '无 overlay 的原始切片';

  @override
  String get historyDlLabelRaw => '原始影片';

  @override
  String get historyDlDescRaw => '无任何 overlay';

  @override
  String get historyDlLabelRawMov => '原始影片 (MOV)';

  @override
  String get historyDlDescRawMov => '原始 MOV 文件';

  @override
  String historyCandidateDuration(int seconds) {
    return '$seconds 秒';
  }

  @override
  String recDetailPointCount(int count) {
    return '$count 点';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appName => 'ORVIA';

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
  String get authLoginSubtitle => '請登入 ORVIA 以同步揮桿資料並探索最新分析報告。';

  @override
  String get authRegisterTitle => '建立帳號';

  @override
  String get authRegisterSubtitle => '填寫以下資料即可開始使用 ORVIA。';

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
  String get authLoginButton => '登入 ORVIA';

  @override
  String get authRegisterButton => '建立帳號';

  @override
  String get authSocialDivider => '或使用社群帳號快速登入';

  @override
  String get authLoginWithGoogle => '使用 Google 登入';

  @override
  String get authGoogleSigningIn => 'Google 登入中...';

  @override
  String get authLoginWithApple => '使用 Apple 登入';

  @override
  String get authAppleSigningIn => 'Apple 登入中...';

  @override
  String get authNoAccount => '還沒有帳戶？立即註冊';

  @override
  String get authHaveAccount => '已有帳戶？返回登入';

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
  String get validationPasswordTooShort => '密碼須至少 8 碼且包含大寫、小寫字母及數字';

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
  String get msgAppleLoginCancelled => '已取消 Apple 登入流程';

  @override
  String get msgAppleLoginSuccess => 'Apple 登入成功，歡迎回來！';

  @override
  String msgAppleLoginFailed(Object error) {
    return 'Apple 登入失敗：$error';
  }

  @override
  String get msgAppleLoginNoToken => 'Apple 登入失敗：後端未返回認證令牌';

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
      '請在系統設定中允許以下權限：\n1. 進入「應用程式與通知」\n2. 選擇 ORVIA → 權限\n3. 啟用「附近裝置、藍牙」與「定位」';

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

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsSectionAccount => '帳號';

  @override
  String get settingsChangeName => '修改名稱';

  @override
  String get settingsChangeNameHint => '請輸入顯示名稱';

  @override
  String get settingsChangePassword => '修改密碼';

  @override
  String get settingsCurrentPassword => '目前密碼';

  @override
  String get settingsNewPassword => '新密碼';

  @override
  String get settingsConfirmNewPassword => '確認新密碼';

  @override
  String get settingsCurrentPasswordRequired => '請輸入目前密碼';

  @override
  String get settingsConfirmChange => '確認修改';

  @override
  String get settingsPasswordChanged => '密碼已修改';

  @override
  String get settingsSetPassword => '設定密碼';

  @override
  String get settingsSetPasswordDesc => '設定密碼後也可用 Email 登入';

  @override
  String get settingsPasswordSet => '密碼已設定';

  @override
  String get settingsGoogleLogin => 'Google 登入';

  @override
  String get settingsGoogleLinked => '已綁定';

  @override
  String get settingsGoogleNotLinked => '尚未綁定，點擊連結 Google 帳號';

  @override
  String get settingsAppleLogin => 'Apple 登入';

  @override
  String get settingsAppleLinked => '已綁定';

  @override
  String get settingsAppleNotLinked => '尚未綁定，點擊連結 Apple 帳號';

  @override
  String get settingsAppleCredentialFailed => '無法取得 Apple 憑證，請重試';

  @override
  String get settingsAppleLinkFailed => 'Apple 綁定失敗，請稍後再試';

  @override
  String get settingsSectionAnalysis => '分析偏好';

  @override
  String get settingsAnalysisQuality => '完整分析輸出品質';

  @override
  String get settingsQualityHint => '選擇後將作為預設值，下次分析自動套用';

  @override
  String get settingsApply => '套用';

  @override
  String settingsQualityUpdated(String quality) {
    return '輸出品質已更新為「$quality」';
  }

  @override
  String get settingsSectionSubscription => '訂閱';

  @override
  String get settingsViewSubscription => '查看訂閱方案';

  @override
  String get settingsSectionGeneral => '一般';

  @override
  String get settingsLanguage => '語言 / Language';

  @override
  String get settingsTheme => '外觀主題';

  @override
  String get settingsThemeSystem => '跟隨系統';

  @override
  String get settingsThemeLight => '日間模式';

  @override
  String get settingsThemeDark => '夜間模式';

  @override
  String get settingsCheckUpdate => '檢查更新';

  @override
  String get settingsAnalytics => '使用統計追蹤';

  @override
  String get settingsAnalyticsDesc => '匿名使用統計，協助改善 App 體驗';

  @override
  String get settingsPrivacyPolicy => '隱私權政策';

  @override
  String get settingsTermsOfService => '使用條款';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsPrivacyOpenFailed => '無法開啟隱私政策頁面，請稍後再試';

  @override
  String get settingsVersionCopied => '已複製版本';

  @override
  String settingsAlreadyLatest(String version) {
    return '已是最新版本 v$version';
  }

  @override
  String get settingsUpdateCheckFailed => '檢查更新失敗，請稍後再試';

  @override
  String get settingsConfirmLogout => '確定登出？';

  @override
  String get settingsLogoutWarning => '登出後需重新登入才能使用雲端功能。';

  @override
  String get commonContinue => '繼續';

  @override
  String get settingsDeleteAccount => '刪除帳號';

  @override
  String get settingsDeleteAccountWarning =>
      '刪除帳號將永久移除你的個人資料、訂閱與分析紀錄，且無法復原。此操作不會自動退款，訂閱請另於 App Store／Google Play 取消。確定要繼續嗎？';

  @override
  String get settingsDeleteAccountConfirmTitle => '最後確認';

  @override
  String get settingsDeleteAccountConfirmHint => '請輸入「DELETE」以確認永久刪除帳號。';

  @override
  String get settingsDeleteAccountFailed => '刪除帳號失敗，請稍後再試或聯絡客服。';

  @override
  String get settingsNameUpdated => '名稱已更新';

  @override
  String get settingsPickFromGallery => '從相簿選擇';

  @override
  String get settingsRemoveAvatar => '移除大頭貼';

  @override
  String get homeTodayOverview => '今日概況';

  @override
  String homeHi(String name) {
    return '嗨，$name 👋';
  }

  @override
  String get homeRounds => '練習輪次';

  @override
  String get homePractices => '練習次數';

  @override
  String get homeTodayGoodRate => '今日好球率';

  @override
  String homeGoodTimes(int count) {
    return '好球 $count 次';
  }

  @override
  String homeBadTimes(int count) {
    return '壞球 $count 次';
  }

  @override
  String get homeTodayPosture => '今日姿勢分析';

  @override
  String get homeTopSpeed => '最佳速度';

  @override
  String get homeSweetSpot => '甜蜜點';

  @override
  String get homeCrispness => '清脆度';

  @override
  String get homeAnnouncements => '公告欄';

  @override
  String get homeRewardBalls => '獎勵球數';

  @override
  String get homeGreetingQuestion => '今天的揮桿目標，準備開始了嗎？';

  @override
  String get homeTodayQuota => '今日用量';

  @override
  String homeQuotaBalls(int used, int total) {
    return '$used / $total 球';
  }

  @override
  String get homeHitAnalysis => '擊球分析';

  @override
  String get homeHitRecordsLabel => '筆擊球紀錄';

  @override
  String homeImprovedVsAvg(String pct) {
    return '持續進步中！本次表現較平均提升 $pct%。';
  }

  @override
  String get homeTrainingFocus => '訓練重點';

  @override
  String get homeViewNow => '立刻查看';

  @override
  String get homeNoShotsToday => '今天還沒有擊球紀錄，去錄一桿吧！';

  @override
  String get homeEmptyHint => '錄下第一桿，開始累積你的數據';

  @override
  String get weekdayMon => '週一';

  @override
  String get weekdayTue => '週二';

  @override
  String get weekdayWed => '週三';

  @override
  String get weekdayThu => '週四';

  @override
  String get weekdayFri => '週五';

  @override
  String get weekdaySat => '週六';

  @override
  String get weekdaySun => '週日';

  @override
  String get todayTitleToday => '今日概況';

  @override
  String get todayTitleHistory => '歷史概況';

  @override
  String get todayLoadFailed => '載入失敗，請下拉重新整理';

  @override
  String get todaySweetSpotHit => '甜蜜點命中';

  @override
  String get todayCrispness => '聲音清脆度';

  @override
  String get todayTopSpeed => '最佳速度';

  @override
  String get todayNoRecord => '今天還沒有練習記錄';

  @override
  String get todayNoRecordDate => '這天沒有練習記錄';

  @override
  String get todayGoRecord => '去錄一支揮桿吧！';

  @override
  String get todayPostureToday => '今日姿勢分析';

  @override
  String get todayPosture => '姿勢分析';

  @override
  String get annBoardTitle => '公告欄';

  @override
  String annUnreadCount(int count) {
    return '$count 則未讀';
  }

  @override
  String get annAllAnnouncements => '所有公告';

  @override
  String get annMarkAllRead => '全部已讀';

  @override
  String get annRefresh => '重新整理';

  @override
  String get annLoadFailed => '載入失敗，請下拉重試';

  @override
  String annMinutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String annHoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String annDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get annDetailTitle => '公告詳情';

  @override
  String annExpiresAt(String date) {
    return '有效期限至 $date';
  }

  @override
  String get annEmpty => '目前沒有公告';

  @override
  String get annEmptySubtitle => '新公告將會顯示在這裡';

  @override
  String get updateNotes => '更新內容';

  @override
  String get updateForcedWarning => '此版本已停止支援，請更新後繼續使用';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateRemindLater => '稍後提醒';

  @override
  String get updateDontRemind => '不再提醒';

  @override
  String get updateCannotOpenStore => '無法開啟商店頁面，請手動前往更新';

  @override
  String get updateRequiredTitle => '必要更新';

  @override
  String get updateRequiredSubtitle => '請更新後繼續使用 ORVIA';

  @override
  String get updateFoundTitle => '發現新版本';

  @override
  String get updateFoundSubtitle => '建議更新以獲得最佳體驗';

  @override
  String get updateCurrentVersion => '目前版本';

  @override
  String get updateLatestVersion => '最新版本';

  @override
  String get upgradePageTitle => '升級您的方案';

  @override
  String get upgradePageSubtitle => '解鎖更多揮桿分析功能，精進您的球技';

  @override
  String get upgradeFullComparison => '完整功能比較';

  @override
  String get upgradeFeatureColumn => '功能';

  @override
  String upgradeSubscribePlan(String plan) {
    return '升級 $plan 方案';
  }

  @override
  String get upgradeSelectPayment => '選擇付款方式';

  @override
  String get upgradeApplePayFailed => 'Apple Pay 設定載入失敗';

  @override
  String get upgradeGooglePayFailed => 'Google Pay 設定載入失敗';

  @override
  String get upgradePaymentFailed => '付款驗證失敗，請稍後重試';

  @override
  String get upgradeSuccessMsg => '升級成功';

  @override
  String get upgradeAlreadyFree => '您目前使用的已是免費方案';

  @override
  String get learningTitle => '揮桿學習';

  @override
  String get learningMoreComing => '更多課程陸續更新中';

  @override
  String get learningVideoComingSoon => '示範影片待補充，先提供重點與標記供對照學習。';

  @override
  String get learningKeyMarkers => '關鍵標記';

  @override
  String get myFeedbackTitle => '我的回饋';

  @override
  String get myFeedbackSubtitle => '已送出的回饋與官方回覆';

  @override
  String get myFeedbackEntry => '查看我的回饋';

  @override
  String get myFeedbackEmpty => '尚無回饋紀錄';

  @override
  String get myFeedbackLoadFailed => '載入失敗，請下拉重試';

  @override
  String get myFeedbackAllLoaded => '已載入全部回饋';

  @override
  String get myFeedbackTypeBug => '問題回報';

  @override
  String get myFeedbackTypeFeature => '功能建議';

  @override
  String get myFeedbackTypeOther => '其他';

  @override
  String get myFeedbackAdminReply => '官方回覆';

  @override
  String get myFeedbackNoReply => '等待回覆中';

  @override
  String get myFeedbackAttachedVideo => '已附影片';

  @override
  String get onboardingSkip => '跳過';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingStart => '開始使用';

  @override
  String get onboardingRecordTitle => '錄製你的揮桿';

  @override
  String get onboardingRecordDesc => '點選底部中央的錄製按鈕開始錄影，ORVIA 會邊錄邊自動偵測每一次擊球。';

  @override
  String get onboardingClipTitle => '自動切片';

  @override
  String get onboardingClipDesc => '錄影結束後，每一桿會自動切成 5 秒片段，可在歷史頁逐段檢查。';

  @override
  String get onboardingAiTitle => 'AI 分析';

  @override
  String get onboardingAiDesc => '將切片送交 AI 教練，分析姿勢、8 階段揮桿與球體軌跡。';

  @override
  String get onboardingBallsTitle => '球數與獎勵';

  @override
  String get onboardingBallsDesc => '分析需要消耗球數。每天有免費額度，也可透過看廣告、提交回饋或邀請好友賺取更多。';

  @override
  String get settingsReplayTutorial => '重看教學引導';

  @override
  String recFrameCount(int count) {
    return '$count 幀';
  }

  @override
  String recDetectedShots(int count) {
    return '已偵測 $count 桿';
  }

  @override
  String recImpactShot(int number) {
    return '第 $number 桿';
  }

  @override
  String get privacySettingsTitle => '隱私與分析';

  @override
  String get privacySectionDataCollection => '資料蒐集說明';

  @override
  String get privacyDataCollectionDesc =>
      '你的影片與分析資料只會在你主動操作時上傳——AI 分析、分享、上傳獎勵或回饋附件。ORVIA 沒有背景上傳，也沒有隱藏的遙測。';

  @override
  String get privacySectionPolicies => '政策文件';

  @override
  String get privacySectionUpload => '分析資料上傳';

  @override
  String get privacyUploadDesc =>
      '你可以自願提交揮桿影片與感測 CSV 資料，協助改善揮桿偵測模型。每筆提交都會人工審核，通過後發放獎勵球。';

  @override
  String get privacyUploadStatusEntry => '查看我的上傳審核狀態';

  @override
  String get privacySectionAccount => '帳號';

  @override
  String get privacyDeleteAccountSubtitle => '軟刪除：將無法再登入，資料會被匿名化';

  @override
  String get rewardSubtitle => '完成任務累積球數，兌換分析次數';

  @override
  String get historyFilterReset => '重置';

  @override
  String aiCoachUpgradeFailed(String error) {
    return '升級失敗: $error';
  }

  @override
  String get aiCoachQuotaExhaustedTitle => '今日球數已用完';

  @override
  String aiCoachQuotaExhaustedBody(int todayUsed, int totalLimit) {
    return '今日已使用 $todayUsed 次，已達上限 $totalLimit 次。\n\n明天可繼續使用，或升級方案取得更多次數。';
  }

  @override
  String get aiCoachGotIt => '知道了';

  @override
  String get aiCoachAnalysisFailed => '分析失敗，請重試';

  @override
  String get aiCoachStatusPending => '準備中...';

  @override
  String get aiCoachStatusQueued => '等待分析佇列...';

  @override
  String get aiCoachStatusProcessing => 'AI 教練正在分析影片...';

  @override
  String get aiCoachStatusIdle => '等待 AI 教練分析...';

  @override
  String get aiCoachStatusConnecting => '連接中...';

  @override
  String get aiCoachLoadingHint => '通常需要 10~30 秒';

  @override
  String get aiCoachPostureAnalysisDone => '已完成錯誤姿勢分析';

  @override
  String get aiCoachSubmitting => '送出中...';

  @override
  String get aiCoachStartAnalysis => '開始 AI 教練分析';

  @override
  String get aiCoachAnalysisHint => '* AI 教練將依據姿勢分析結果，提供詳細教練評語與訓練建議';

  @override
  String get aiCoachEvidence => '依據';

  @override
  String get aiCoachSeverityHigh => '嚴重';

  @override
  String get aiCoachSeverityMedium => '中等';

  @override
  String get aiCoachSeverityLow => '輕微';

  @override
  String get aiCoachImpactPremiumSweetSpot => '高品質甜蜜點';

  @override
  String get aiCoachImpactSweetSpot => '甜蜜點';

  @override
  String get aiCoachImpactNearSweetSpot => '接近甜蜜點';

  @override
  String get aiCoachImpactFair => '普通';

  @override
  String get aiCoachImpactPoor => '擊球偏虛';

  @override
  String get aiCoachImpactQualityTitle => '擊球品質（音訊）';

  @override
  String aiCoachImpactFeatureCount(int passCount, int totalFeatures) {
    return '$passCount / $totalFeatures 項特徵符合甜蜜點範圍';
  }

  @override
  String get aiCoachFeedbackTitle => '教練評語';

  @override
  String get aiCoachPracticeTitle => '訓練建議';

  @override
  String get aiCoachNextGoalTitle => '下次練習目標';

  @override
  String get aiCoachReanalyzeSubmitting => '提交重新分析中...';

  @override
  String aiCoachReanalyzeFailed(String error) {
    return '重新分析失敗: $error';
  }

  @override
  String get ballTuneTitle => '球軌跡調參';

  @override
  String get ballTuneHudInit => '初始化中…';

  @override
  String get ballTuneHudDetecting => '偵測中…';

  @override
  String get ballTuneHudBlobFailed => 'blob 抽取失敗';

  @override
  String ballTuneRoiBadge(String r, String margin) {
    return 'ROI r=${r}px  margin=$margin';
  }

  @override
  String get ballTuneRoiToggleTooltip => 'ROI 疊圖開關';

  @override
  String get ballTuneSectionRealtime => '即時（拉了立刻重畫）';

  @override
  String get ballTuneSliderResidual => '品質閘門 殘差上限';

  @override
  String get ballTuneSliderP1MaxDist => 'P1 最遠距離';

  @override
  String get ballTuneRoiMaskSection => 'ROI / 遮罩（可直接在預覽上拖拉）';

  @override
  String get ballTuneSliderRoiRadius => 'ROI 半徑';

  @override
  String get ballTuneSliderGolferMargin => '球員遮罩 margin';

  @override
  String get ballTuneSliderRoiMissScale => 'ROI miss 大擴張×';

  @override
  String get ballTuneSliderRoiRadiusMax => 'ROI 半徑上限';

  @override
  String get ballTuneSliderStepMaxPost => '擊球後 step 上限';

  @override
  String get ballTuneSliderPredMaxPost => '擊球後 pred 上限';

  @override
  String get ballTuneSliderMissPatiencePost => '擊球後 miss 容忍';

  @override
  String get ballTuneSectionReextract => '重抽（改完按下方按鈕）';

  @override
  String get ballTuneSliderDiffThresh => 'diffThresh 幀差門檻';

  @override
  String get ballTuneRedetectButton => '重新偵測（套用 diffThresh）';

  @override
  String clipCandTitle(int count) {
    return '確認擊球片段（$count 個候選）';
  }

  @override
  String get clipCandTapToPreview => '點候選可預覽';

  @override
  String get clipCandRangeTooShort => '切片區段需至少 0.5 秒（終點需在起點之後）';

  @override
  String clipCandConfirmClip(int count) {
    return '切出 $count 個片段';
  }

  @override
  String clipCandManualHint(String start) {
    return '起點 $start → 拖到終點後按「加入區段」';
  }

  @override
  String get clipCandManualPrompt => '自由切片：拖時間軸到起點';

  @override
  String get clipCandSetStart => '設為起點';

  @override
  String get clipCandReset => '重設';

  @override
  String get clipCandAddRange => '加入區段';

  @override
  String clipCandCandidateLabel(int index, String time) {
    return '候選 $index ・ $time';
  }

  @override
  String get clipCandFromAudio => '擊球聲偵測';

  @override
  String get clipCandFromMotion => '錄影中動作偵測';

  @override
  String clipCandManualRangeLabel(String start, String end) {
    return '自訂區段 ・ $start - $end';
  }

  @override
  String clipCandRangeDuration(String seconds) {
    return '長度 $seconds 秒';
  }

  @override
  String get compareLoadingVideos => '載入影片中…';

  @override
  String get highlightTitle => 'Highlight 預覽';

  @override
  String get highlightShareSystem => '系統分享';

  @override
  String get highlightExportDebug => '匯出 debug';

  @override
  String get highlightShareDebug => '分享 debug';

  @override
  String get highlightShareText => '我的揮桿 Highlight';

  @override
  String get highlightDebugFileError => '無法建立 debug 檔';

  @override
  String get highlightStoragePermissionRequired => '需要儲存權限以匯出至下載資料夾';

  @override
  String get highlightDownloadsDirNotFound => '找不到下載資料夾';

  @override
  String highlightSavedTo(String path) {
    return '已另存至：$path';
  }

  @override
  String highlightExportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String historySubtitle(int total, int good, int bad) {
    return '共 $total 筆 · 好球 $good · 壞球 $bad';
  }

  @override
  String get historySearchHint => '搜尋錄影…';

  @override
  String historySearchResult(int count, int total) {
    return '搜尋結果 $count / $total 筆';
  }

  @override
  String get historySearchNoResult => '找不到相符的紀錄';

  @override
  String historySearchNoResultHint(Object query) {
    return '沒有符合「$query」的結果';
  }

  @override
  String get historySearchClear => '清除搜尋';

  @override
  String get historyEmptyTitle => '還沒有任何錄影';

  @override
  String get historyEmptySubtitle => '開始錄製揮桿來累積紀錄吧';

  @override
  String get historyFilterLabelSort => '排序';

  @override
  String get historyFilterLabelDate => '日期';

  @override
  String get historyFilterLabelVideo => '影片';

  @override
  String get historyFilterLabelGoodBad => '評級';

  @override
  String get historyFilterLabelAnalysis => '分析';

  @override
  String get historyFilterLabelClip => '切片';

  @override
  String get historyFilterLabelAI => 'AI';

  @override
  String get historyFilterLabelPosture => '姿勢';

  @override
  String get historyFilterAll => '全部';

  @override
  String get historyFilterToday => '今天';

  @override
  String get historyFilterWeek => '本週';

  @override
  String get historyFilterMonth => '本月';

  @override
  String get historyFilterCustomDate => '自訂日期範圍';

  @override
  String get historyFilterSort => '排序方式';

  @override
  String get historyFilterGood => '優';

  @override
  String get historyFilterBad => '劣';

  @override
  String get historyFilterAnalyzed => '已分析';

  @override
  String get historyFilterNotAnalyzed => '未分析';

  @override
  String get historyFilterAiAnalyzed => 'AI 已分析';

  @override
  String get historyFilterAiNotAnalyzed => 'AI 未分析';

  @override
  String get historyFilterClipped => '已切片';

  @override
  String get historyFilterNotClipped => '未切片';

  @override
  String get historyFilterLongVideo => '長影片';

  @override
  String get historyFilterShortVideo => '短影片';

  @override
  String get historySortDate => '時間';

  @override
  String get historySortPeakSpeed => '最佳速度';

  @override
  String get historySortClipTime => '片段時間';

  @override
  String get historyDateRangeHelp => '選擇日期範圍';

  @override
  String get historyDeleteTitle => '刪除錄影';

  @override
  String historyDeleteClipConfirm(Object title) {
    return '確定刪除切片「$title」？';
  }

  @override
  String historyDeleteVideoConfirm(Object title) {
    return '確定刪除錄影「$title」？';
  }

  @override
  String historyDeleteVideoWithClipsConfirm(Object title, Object count) {
    return '確定刪除「$title」及其 $count 個切片？';
  }

  @override
  String historyDeletedSnack(Object name) {
    return '已刪除 $name';
  }

  @override
  String historyDeletedWithClipsSnack(Object name, Object count) {
    return '已刪除 $name 及 $count 個切片';
  }

  @override
  String get historyRenameTitle => '重新命名錄影';

  @override
  String get historyRenameClipTitle => '重新命名切片';

  @override
  String get historyRenameLabel => '新名稱';

  @override
  String get historyRenameHelper => '留空以還原預設名稱';

  @override
  String get historyRenameValidation => '名稱不能為空白';

  @override
  String historyRenamedSnack(Object name) {
    return '已重新命名為「$name」';
  }

  @override
  String historyRenameResetSnack(Object name) {
    return '已還原預設名稱「$name」';
  }

  @override
  String historyFileNotFound(Object name) {
    return '找不到檔案：$name';
  }

  @override
  String get historyClipFileNotExist => '切片檔案不存在，請重新偵測';

  @override
  String get historyAlreadyClipped => '此影片已有切片，重新偵測將取代現有切片。';

  @override
  String get historyProgressPreparingSkeleton => '準備骨架分析…';

  @override
  String get historyProgressPreparing => '準備中…';

  @override
  String get historyDetectingShots => '偵測揮桿中';

  @override
  String get historyCancelledDetection => '已取消偵測';

  @override
  String get historyCancelledAnalysis => '已取消分析';

  @override
  String get historyV2NoAudio => '未找到音訊軌，無法使用音訊偵測模式';

  @override
  String get historyV3NoShot => '骨架分析未偵測到任何揮桿';

  @override
  String get historyV3NoValidHit => '過濾後無有效擊球點';

  @override
  String get historyNoShotDetected => '未偵測到揮桿';

  @override
  String get historyClipFailed => '切片生成失敗';

  @override
  String historyClipsGenerated(Object count) {
    return '已生成 $count 個切片';
  }

  @override
  String historyClipsGeneratedBg(Object count) {
    return '已將 $count 個切片存入紀錄';
  }

  @override
  String historyDetectFailed(Object error) {
    return '偵測失敗：$error';
  }

  @override
  String get historyLongVideoTitle => '長影片提示';

  @override
  String historyLongVideoContent(Object seconds) {
    return '此影片長達 $seconds 秒，完整分析可能需要較長時間。';
  }

  @override
  String get historyContinueAnalysis => '繼續分析';

  @override
  String get historyFullAnalysisTitle => '分析中';

  @override
  String historyInvalidDuration(Object seconds) {
    return '影片時長無效：$seconds 秒';
  }

  @override
  String historyAnalysisComplete(Object audio) {
    return '分析完成$audio';
  }

  @override
  String historyAnalysisFailed(Object error) {
    return '分析失敗：$error';
  }

  @override
  String get historyQuotaExhaustedTitle => '今日配額已用盡';

  @override
  String historyQuotaExhaustedContent(Object used, Object total) {
    return '今日已使用 $used/$total 次，升級方案以繼續使用。';
  }

  @override
  String get historyGotIt => '知道了';

  @override
  String get historyAiAnalysisConfirmTitle => 'AI 分析';

  @override
  String get historyAiAnalysisConfirmDesc => '提交此揮桿進行 AI 分析，將消耗 1 顆球。';

  @override
  String get historyAiAnalysisConfirmBtn => '開始分析';

  @override
  String historyAiSubmitFailed(Object error) {
    return '提交失敗：$error';
  }

  @override
  String get historyNoOtherVideoToCompare => '沒有其他影片可供比較';

  @override
  String get historyCompareTitle => '比較揮桿';

  @override
  String historyCompareSubtitle(Object title) {
    return '選擇要與「$title」比較的影片';
  }

  @override
  String get historyPhasesJsonMissing => '找不到 phases.json，請重新分析';

  @override
  String get historyPhasesJsonInvalid => 'phases.json 格式錯誤，請重新分析';

  @override
  String get historySelectAiModeTitle => '選擇 AI 模式';

  @override
  String get historyAiModeV1Title => '基礎 (V1)';

  @override
  String get historyAiModeV1Desc => '音訊峰值偵測';

  @override
  String get historyAiModeV2Title => '標準 (V2)';

  @override
  String get historyAiModeV2Desc => '音訊 + 骨架混合';

  @override
  String get historyAiModeV3Title => '進階 (V3)';

  @override
  String get historyAiModeV3Desc => '骨架主導加音訊精修';

  @override
  String get historySelectDetectModeTitle => '選擇偵測模式';

  @override
  String get historyDetectV1Title => '骨架偵測 (V1)';

  @override
  String get historyDetectV1Desc => 'MediaPipe 姿勢估計';

  @override
  String get historyDetectBadgePrecise => '精準';

  @override
  String get historyDetectV1Time => '~10 秒';

  @override
  String get historyDetectV2Title => '音訊偵測 (V2)';

  @override
  String get historyDetectV2Desc => '快速音訊峰值偵測';

  @override
  String get historyDetectBadgeFast => '快速';

  @override
  String get historyDetectV2Time => '~30 秒';

  @override
  String get historyDetectV3Title => '混合偵測 (V3)';

  @override
  String get historyDetectV3Desc => '骨架主導加音訊精修';

  @override
  String get historyDetectBadgeBalanced => '均衡';

  @override
  String get historyDetectV3Time => '~45 秒';

  @override
  String get historySkipToday => '今日不再提醒';

  @override
  String get historyStartDetect => '開始偵測';

  @override
  String get historySelectQualityTitle => '選擇匯出品質';

  @override
  String get historyStartAnalysis => '開始分析';

  @override
  String get historyActionDetect => '偵測桿數';

  @override
  String get historyActionAiAnalysis => 'AI 分析';

  @override
  String get historyActionFullAnalysis => '完整分析';

  @override
  String get historyActionChart => '統計圖表';

  @override
  String get historyActionPlay => '播放';

  @override
  String get historyActionExpand => '展開切片';

  @override
  String get historyActionCollapse => '收合切片';

  @override
  String get historyMenuRename => '重新命名';

  @override
  String get historyMenuAddNote => '新增備註';

  @override
  String get historyMenuEditNote => '編輯備註';

  @override
  String get historyMenuShare => '分享';

  @override
  String get historyMenuDownload => '下載';

  @override
  String get historyMenuDownloading => '下載中…';

  @override
  String get historyMenuCompare => '比較';

  @override
  String historyMenuUploadReward(int balls) {
    return '上傳獎勵 +$balls 球';
  }

  @override
  String get historyMenuUploaded => '已上傳';

  @override
  String get historyMenuAnalyzing => '分析中…';

  @override
  String get historyMenuDeleteVideo => '刪除影片';

  @override
  String get historyMoreActions => '更多操作';

  @override
  String get historyBadgeNoAudio => '無音訊';

  @override
  String get historyBadgeAnalyzed => '已分析';

  @override
  String get historySweetSpot => '甜蜜點';

  @override
  String get historySweetSpotHit => '命中';

  @override
  String get historySweetSpotMiss => '未命中';

  @override
  String get historyHitSummary => '擊球統計';

  @override
  String historyClipDefaultName(Object index) {
    return '第 $index 桿';
  }

  @override
  String historyClipHitAt(Object time) {
    return '擊球 @ $time';
  }

  @override
  String historyClipRange(Object start, Object end) {
    return '片段 $start–$end 秒';
  }

  @override
  String historyRoundLabel(Object index) {
    return '第 $index 輪';
  }

  @override
  String historyDurationLine(Object time, Object seconds) {
    return '$time · $seconds 秒';
  }

  @override
  String historyImportedFrom(Object name) {
    return '來自 $name';
  }

  @override
  String get historyNoteDialogTitle => '影片備註';

  @override
  String get historyNoteHint => '記下練習心得、場地、使用桿型…';

  @override
  String get historyNoteHelper => '可留空以清除備註';

  @override
  String get historySaveLocationTitle => '選擇儲存位置';

  @override
  String get historySaveLocationDownloads => '下載資料夾';

  @override
  String get historySaveLocationDownloadsSub => '儲存到系統預設下載位置';

  @override
  String get historySaveLocationPick => '選擇資料夾';

  @override
  String get historySaveLocationPickSub => '自訂儲存位置';

  @override
  String get historyDownloadVersionTitle => '選擇下載版本';

  @override
  String historyExportSaved(Object label) {
    return '「$label」已儲存 ✅';
  }

  @override
  String historyExportSavedPhotos(Object label) {
    return '「$label」已儲存到相機膠卷 ✅';
  }

  @override
  String historyExportFailed(Object detail) {
    return '下載失敗：$detail';
  }

  @override
  String get historyUploadRewardTitle => '上傳分析資料';

  @override
  String historyUploadRewardContent(Object title, Object balls) {
    return '將上傳「$title」的分析資料，用於改善揮桿偵測模型。\n\n上傳後需經審核，審核通過將發放 +$balls 球獎勵。\n\n確定上傳？';
  }

  @override
  String get historyUploadSubmit => '上傳送審';

  @override
  String get historyUploadingProgress => '上傳影片與分析資料中…';

  @override
  String historyUploadFailed(Object error) {
    return '上傳失敗：$error';
  }

  @override
  String get historyUploadSubmitFailed =>
      '送審未成功：此影片可能已提交過（含審核未通過者不可重送），或網路異常請稍後再試';

  @override
  String historyUploadReviewPending(Object balls) {
    return '已送出審核，通過後將發放 +$balls 球';
  }

  @override
  String get hitsSummaryEmpty => '尚未偵測到任何揮桿';

  @override
  String hitsSummaryHitIndex(int index) {
    return '第 $index 桿';
  }

  @override
  String get hitsSummaryPeak => '峰值';

  @override
  String get hitsSummaryDuration => '時長';

  @override
  String get hitsSummaryStart => '開始';

  @override
  String get hitsSummaryEnd => '結束';

  @override
  String hitsSummaryDetectFrom(String source) {
    return '偵測來源：$source';
  }

  @override
  String get hitsSummaryTitle => '揮桿摘要';

  @override
  String hitsSummaryCount(int count) {
    return '共 $count 桿';
  }

  @override
  String get homeCurrentSuggestions => '目前訓練建議';

  @override
  String homeNextGoal(String goal) {
    return '下次目標：$goal';
  }

  @override
  String get authInviteCodeOptional => '選填';

  @override
  String get authInviteCodeLabel => '邀請碼';

  @override
  String get authInviteCodeHint => '如有好友邀請碼，請在此填寫';

  @override
  String get authInviteCodeHelper => '填寫邀請碼，雙方各獲得 +5 球獎勵';

  @override
  String get devTestAccounts => '測試帳號';

  @override
  String get devTestPassword => '密碼：Test1234!';

  @override
  String get forgotTitle => '忘記密碼';

  @override
  String get forgotEnterCodeTitle => '輸入驗證碼';

  @override
  String get forgotEmailSubtitle => '輸入您的 Email，我們將寄送 6 位數驗證碼';

  @override
  String forgotCodeSentSubtitle(String email) {
    return '驗證碼已寄至 $email';
  }

  @override
  String get forgotSixDigitCodeLabel => '6 位驗證碼';

  @override
  String get forgotNewPasswordLabel => '新密碼';

  @override
  String get forgotNewPasswordHint => '至少 8 位，含大寫、小寫、數字';

  @override
  String get forgotConfirmPasswordLabel => '確認新密碼';

  @override
  String get forgotSendCodeButton => '寄送驗證碼';

  @override
  String get forgotConfirmResetButton => '確認重設密碼';

  @override
  String get forgotReEnterEmail => '重新輸入 Email';

  @override
  String get forgotEnterValidEmail => '請輸入有效的 Email';

  @override
  String get forgotSendFailed => '寄送失敗';

  @override
  String get forgotNetworkError => '網路錯誤，請稍後再試';

  @override
  String get forgotEnterSixDigitCode => '請輸入 6 位數驗證碼';

  @override
  String get forgotPasswordComplexity => '密碼須至少 8 位且包含大寫、小寫及數字';

  @override
  String get forgotPasswordMismatch => '兩次密碼不一致';

  @override
  String get forgotResetSuccess => '密碼已重設，請用新密碼登入';

  @override
  String get forgotResetFailed => '重設失敗';

  @override
  String get playerTitle => '影片查看';

  @override
  String get playerNoteAdd => '新增備註';

  @override
  String get playerNoteEdit => '編輯備註';

  @override
  String get playerNoteCleared => '已清除備註';

  @override
  String get playerNoteSaved => '已儲存備註';

  @override
  String get playerVideoNotFound => '找不到影片檔案';

  @override
  String get playerVideoLoadFailed => '影片載入失敗';

  @override
  String get playerSkeletonNotFound => '骨架資料不存在';

  @override
  String get playerOverlaySkeleton => '骨架';

  @override
  String get playerOverlayTrajectory => '軌跡';

  @override
  String get playerOverlayEffect => '特效';

  @override
  String get playerTrajectoryTuning => '軌跡調參';

  @override
  String playerShotLabel(int index, String time) {
    return '第$index球 $time';
  }

  @override
  String get playerStatsEmpty => '尚無統計資料（需軌跡或階段分析）';

  @override
  String get playerStatLaunchAngle => '發射角';

  @override
  String get playerStatTempo => '節奏 (上桿:下桿)';

  @override
  String get playerStatBackDownswing => '上桿 / 下桿';

  @override
  String get playerStatFlightTime => '入鏡飛行';

  @override
  String get playerChartEmpty => '尚無圖表資料，請先完成分析';

  @override
  String get playerChartNoData => '無資料';

  @override
  String get playerChartAudioEmpty => '聲音峰值 無資料';

  @override
  String get playerChartWristYEmpty => '手腕 Y 無資料';

  @override
  String get playerChartSpeedEmpty => '速度 無資料';

  @override
  String get playerChartTabAudio => '聲音峰值';

  @override
  String get playerChartTabWristY => '手腕 Y';

  @override
  String get playerChartTabSpeed => '速度';

  @override
  String get playerChartTabPosture => '姿勢';

  @override
  String get playerChartTabAudioFeature => '音頻特徵';

  @override
  String get playerLoadDetailScore => '載入詳細分數';

  @override
  String get playerPostureEmpty => '尚無姿勢分析，請先完成分析';

  @override
  String playerAudioPassCount(int count) {
    return '$count / 5 項通過';
  }

  @override
  String get playerAudioEmpty => '尚無音頻分析';

  @override
  String playerAiAnalysisFailed(String error) {
    return 'AI 分析失敗: $error';
  }

  @override
  String get playerAiNotStarted => '尚未進行 AI 教練分析';

  @override
  String get playerAiStartAnalysis => '開始分析';

  @override
  String get playerAiViewProgress => '查看進度';

  @override
  String get playerAiCoachTitle => 'AI 教練分析';

  @override
  String get playerAiPrimaryIssue => '主要問題';

  @override
  String get playerAiCoachFeedback => '教練評語';

  @override
  String get playerAiPracticeSuggestions => '訓練建議';

  @override
  String get playerAiNextGoal => '下次目標';

  @override
  String get playerAiReanalyze => '重新分析';

  @override
  String get playerAiViewDetail => '查看詳細';

  @override
  String get playerAiStatusPending => '準備中...';

  @override
  String get playerAiStatusQueued => '等待分析佇列...';

  @override
  String get playerAiStatusProcessing => 'AI 教練分析中...';

  @override
  String get playerAiStatusAnalyzing => '分析中...';

  @override
  String get playerSeverityHigh => '嚴重';

  @override
  String get playerSeverityMedium => '中等';

  @override
  String get playerSeverityLow => '輕微';

  @override
  String get playerHighlightPreview => '精彩片段預覽';

  @override
  String get playerSweetSpotHit => '甜蜜點命中';

  @override
  String get playerSweetSpot => '甜蜜點';

  @override
  String get playerThinShot => '偏虛球';

  @override
  String playerAudioPassCountBadge(int count) {
    return '$count/5 特徵符合';
  }

  @override
  String get playerNoteDialogTitle => '影片備註';

  @override
  String get playerNoteHint => '記下練習心得、場地、使用桿型…';

  @override
  String get playerNoteHelper => '可留空以清除備註';

  @override
  String get playerPhaseAddress => '準備';

  @override
  String get playerPhaseTakeaway => '起桿';

  @override
  String get playerPhaseBackswing => '上桿';

  @override
  String get playerPhaseTop => '頂點';

  @override
  String get playerPhaseDownswing => '下桿';

  @override
  String get playerPhaseImpact => '擊球';

  @override
  String get clipLegendStart => '開始';

  @override
  String get clipLegendEnd => '結束';

  @override
  String get playerPhaseFollowthrough => '送桿';

  @override
  String get playerPhaseFinish => '收桿';

  @override
  String get postureTitle => '姿勢分析';

  @override
  String get postureNoData => '尚無 AI 分析資料';

  @override
  String get profileSubtitle => '調整個人資訊以獲得更精準的揮桿分析，完成後記得儲存。';

  @override
  String get profileAvatarHint => '設定個人頭像讓教練更容易識別';

  @override
  String get profileAvatarSaveFailed => '儲存頭像失敗，請稍後再試。';

  @override
  String get profileDisplayNameLabel => '暱稱';

  @override
  String get profileDisplayNameHint => '輸入想在首頁顯示的名稱';

  @override
  String get profileDisplayNameRequired => '請輸入暱稱';

  @override
  String get profileEmailLabel => '電子郵件';

  @override
  String get profilePhoneLabel => '聯絡電話';

  @override
  String get profilePhoneHint => '例：0912-345-678';

  @override
  String get profileHandicapLabel => '差點';

  @override
  String get profileHandicapHint => '可填寫目前差點或目標數值';

  @override
  String get purchaseTestPanelTitle => '🧪 購買測試面板';

  @override
  String get purchaseTestSimulateSuccessMsg => '✅ 模擬購買成功！用戶已設置為高級用戶';

  @override
  String purchaseTestErrorMsg(String error) {
    return '❌ 錯誤: $error';
  }

  @override
  String get purchaseTestClearSuccessMsg => '🔄 已清除購買紀錄！用戶現在是普通用戶';

  @override
  String get purchaseTestPremiumStatusLabel => '高級用戶狀態: ';

  @override
  String get purchaseTestStatusPurchased => '✅ 已購買';

  @override
  String get purchaseTestStatusNotPurchased => '❌ 未購買';

  @override
  String purchaseTestPaymentMethod(String method) {
    return '支付方式: $method';
  }

  @override
  String get purchaseTestPaymentMethodNone => '無';

  @override
  String get purchaseTestSimulateBtn => '模擬購買成功';

  @override
  String get purchaseTestClearBtn => '清除購買';

  @override
  String get purchaseTestRefreshBtn => '刷新狀態';

  @override
  String get purchaseTestDialogTitle => '🧪 購買功能測試';

  @override
  String get recDetailDownloadVideo => '下載影片';

  @override
  String get exportCustomTitle => '自訂匯出';

  @override
  String get exportCustomSubtitle => '選擇要燒錄到影片上的元素';

  @override
  String get exportElementSkeleton => '骨架';

  @override
  String get exportElementSkeletonDesc => '揮桿姿勢關節骨架';

  @override
  String get exportElementTrajectory => '球軌跡';

  @override
  String get exportElementTrajectoryDesc => '擊球後球體飛行軌跡';

  @override
  String get exportElementGlow => '擊球光暈';

  @override
  String get exportElementGlowDesc => '擊球瞬間的擴散光圈';

  @override
  String get exportElementSweetSpot => '甜蜜點';

  @override
  String get exportElementSweetSpotDesc => '擊球品質光圈（金／藍／灰）';

  @override
  String get swingBothHands => '雙手判斷';

  @override
  String get swingBothHandsDesc => '雙手腕一起移動才算一次揮桿；其中一手被遮擋時自動改用另一手';

  @override
  String get exportNoOverlayMaterial => '此影片沒有可疊加的分析素材，將輸出原片。';

  @override
  String get exportWatermarkFree => '免費版成品將含 ORVIA 浮水印，升級可移除';

  @override
  String get exportWatermarkPaid => '已訂閱：成品不含浮水印';

  @override
  String get exportComposeAndDownload => '合成並下載';

  @override
  String get recDetailNoVideoFound => '找不到可下載的影片';

  @override
  String recDetailBurning(String label) {
    return '燒錄「$label」中…';
  }

  @override
  String get recDetailBurnFailed => '燒錄失敗，請稍後重試';

  @override
  String recDetailSavedToDownloads(String label) {
    return '「$label」已儲存到下載資料夾 ✅';
  }

  @override
  String recDetailSavedToPhotos(String label) {
    return '「$label」已儲存到相機膠卷 ✅';
  }

  @override
  String get recDetailSharedViaSheet => '已開啟分享 ✅';

  @override
  String recDetailDownloadFailed(String detail) {
    return '下載失敗：$detail';
  }

  @override
  String get recDetailSkeletonPreview => '骨架預覽';

  @override
  String get recDetailSkeletonLoadFailed => '骨架預覽載入失敗';

  @override
  String get recDetailAudioPeak => '聲音峰值';

  @override
  String get recDetailAudioPeakSubtitle => 'RMS dBFS';

  @override
  String get recDetailAudioPeakMissing => '需完成音頻分析';

  @override
  String get recDetailWristY => '手腕 Y';

  @override
  String get recDetailWristYSubtitle => '右手腕 Y 位置（像素）';

  @override
  String get recDetailPoseMissing => '需完成姿勢分析';

  @override
  String get recDetailSpeedSubtitle => '手腕移動速度（px/frame）';

  @override
  String get recDetailSpeedMissing => '速度';

  @override
  String get recDetailSweetSpot => '甜蜜點';

  @override
  String get recDetailOffCenter => '擊球偏虛';

  @override
  String get recDetailAudioFeaturesTitle => '音頻特徵分析';

  @override
  String recDetailFeaturePassCount(int count) {
    return '$count / 5 項特徵符合甜蜜點範圍';
  }

  @override
  String get recDetailAutoAnalyzing => '姿勢分析上傳中，請稍候…';

  @override
  String get recDetailOnnxTitle => 'ONNX 姿勢分析';

  @override
  String recDetailOnnxLoadFailed(String error) {
    return '載入失敗: $error';
  }

  @override
  String get recDetailOnnxNoResult => '尚無 ONNX 結果';

  @override
  String get recDetailOnnxNoScores => '無分數資料';

  @override
  String get recDetailSwingPhases => '揮桿階段';

  @override
  String get recDetailRegenerate => '重新生成';

  @override
  String get recDetailGeneratePhases => '生成階段';

  @override
  String get recDetailNoChartData => '尚無圖表資料';

  @override
  String get recDetailNoChartHint => '請先完成音頻分析與姿勢分析';

  @override
  String get recDetailLoadFailed => '載入失敗';

  @override
  String get recDetailSelectDownloadVersion => '選擇下載版本';

  @override
  String get recDetailOptLabelFull => '分析完整版';

  @override
  String get recDetailOptDescFull => '骨架 + 球軌跡';

  @override
  String get recDetailOptLabelSkeleton => '骨架版';

  @override
  String get recDetailOptDescSkeleton => '只含骨架 overlay';

  @override
  String get recDetailOptLabelClip => '原始片段';

  @override
  String get recDetailOptDescNoOverlay => '無任何 overlay';

  @override
  String get recDetailOptLabelRaw => '原始影片';

  @override
  String get recDetailOptLabelRawMov => '原始影片 (MOV)';

  @override
  String get recDetailOptDescRawMov => '原始 MOV 檔';

  @override
  String get recDetailPhaseAddress => '①準備';

  @override
  String get recDetailPhaseTakeaway => '②起桿';

  @override
  String get recDetailPhaseBackswing => '③上桿';

  @override
  String get recDetailPhaseTop => '④頂點';

  @override
  String get recDetailPhaseDownswing => '⑤下桿';

  @override
  String get recDetailPhaseImpact => '⑥擊球';

  @override
  String get recDetailPhaseFollowthrough => '⑦送桿';

  @override
  String get recDetailPhaseFinish => '⑧收桿';

  @override
  String get recHistSheetEmptyHint => '目前沒有錄影紀錄，完成錄影後會自動顯示在此處。';

  @override
  String get recHistSheetPickFromFolder => '從檔案資料夾選取影片';

  @override
  String recHistSheetDurationSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get recSelPreparingProgress => '準備中...';

  @override
  String get recSelAnalyzingDialogTitle => '影片分析中';

  @override
  String get recSelNoFileSelected => '❌ 未選擇任何檔案';

  @override
  String recSelVideoTooLong(int durationSec) {
    return '❌ 影片超過 10 分鐘限制（$durationSec 秒）\n請選擇 600 秒以內的影片';
  }

  @override
  String recSelVideoDurationOk(int durationSec) {
    return '✅ 影片時長 $durationSec 秒，符合 10 分鐘限制';
  }

  @override
  String get recSelImportFailed => '❌ 導入失敗\n檔案可能不存在或格式不支援';

  @override
  String recSelImportSuccess(String name, String duration) {
    return '✅ 導入成功！\n$name\n時長: $duration';
  }

  @override
  String recSelImportError(String error) {
    return '❌ 導入出錯\n$error';
  }

  @override
  String get recSelImportingVideo => '正在導入影片...';

  @override
  String get recSelDoNotClose => '請勿關閉應用';

  @override
  String get recSelShotModeTitle => '即時揮桿模式';

  @override
  String get recSelShotModeSubtitle => '揮桿自動偵測並切片，無需錄長影片';

  @override
  String get recSelNewFeatureBadge => '新功能';

  @override
  String get recSelRecordTitle => '開始錄製';

  @override
  String get recSelRecordSubtitle => '即時拍攝並進行揮桿分析';

  @override
  String get recSelLocalVideoTitle => '選擇本地影片';

  @override
  String get recSelLocalVideoSubtitle => '從裝置中選擇已有影片（上限 10 分鐘）';

  @override
  String get recSelShareLinkTitle => '從分享連結取得';

  @override
  String get recSelShareLinkSubtitle => '輸入 16 碼分享碼下載影片';

  @override
  String get recSelHeaderTitle => '選擇錄製方式';

  @override
  String get recSelHeaderSubtitle => '即時拍攝、匯入本地影片或透過分享碼取得';

  @override
  String get recSelIOSSourceSheetTitle => '選擇影片來源';

  @override
  String get recSelPhotoLibrary => '相簿';

  @override
  String get recSelFilesApp => '檔案 App（資料夾）';

  @override
  String recTabsTitle(int count) {
    return '錄影歷史 ($count)';
  }

  @override
  String get recTabsEmpty => '沒有錄影紀錄';

  @override
  String get recTabsEmptyHint => '完成新的錄影後，將在此顯示';

  @override
  String recTabsMode(String label) {
    return '模式：$label';
  }

  @override
  String recTabsDuration(int seconds) {
    return '時長：$seconds秒';
  }

  @override
  String get recordTitle => '高爾夫揮桿錄製';

  @override
  String get recordOverlayToggle => '輪廓疊加切換';

  @override
  String get recordSettings => '錄製設定';

  @override
  String get recordPermissionTitle => '需要相機與麥克風權限';

  @override
  String get recordPermissionMicOnly => '錄影需要麥克風權限以收錄擊球聲，請開啟後再試。';

  @override
  String get recordPermissionCameraAndMic => '揮桿錄影需要相機與麥克風權限，請開啟後再試。';

  @override
  String get recordGoToSettings => '前往設定';

  @override
  String get recordGotIt => '知道了';

  @override
  String get recordLowEndDeviceWarning => '此裝置不支援錄影期間同步骨架偵測，錄影結束後恢復';

  @override
  String get recordFailed => '本次錄製失敗（未取得有效影像），請重新錄製';

  @override
  String get recordVideoQuality => '影片畫質';

  @override
  String get recordFrameRate => '幀率';

  @override
  String get recordAudio => '錄製音訊';

  @override
  String get recordApply => '套用';

  @override
  String get rewardTitle => '獎勵球數';

  @override
  String get rewardUsageHistoryTooltip => '使用紀錄';

  @override
  String rewardEarnedSnackbar(String source, int balls) {
    return '透過「$source」獲得 +$balls 額外球數！';
  }

  @override
  String rewardUploadSubmittedPending(int pending) {
    return '已送出 $pending 筆審核，通過後將發放球數獎勵';
  }

  @override
  String get rewardUploadSubmittedDuplicate => '資料已提交（重複資料不再送審）';

  @override
  String get rewardStatBonusBalls => '累積獎勵';

  @override
  String get rewardUnitBall => '球';

  @override
  String get rewardStatAdToday => '今日廣告';

  @override
  String get rewardAdDailyUnit => '/ 5 次';

  @override
  String get rewardStatInvites => '邀請好友';

  @override
  String get rewardUnitPerson => '位';

  @override
  String rewardBallsBadge(int balls) {
    return '+$balls 球';
  }

  @override
  String rewardAdProgress(int used, int cap) {
    return '$used / $cap 次';
  }

  @override
  String get rewardDoneToday => '今日已完成';

  @override
  String get rewardAdNotCompleted => '廣告未播放完成或暫時無法載入，請稍後再試';

  @override
  String rewardAdFailed(String error) {
    return '廣告獎勵失敗：$error';
  }

  @override
  String get rewardWatchAdTitle => '看廣告';

  @override
  String rewardWatchAdButton(int balls) {
    return '觀看廣告 +$balls 球';
  }

  @override
  String get rewardInviteFriendTitle => '邀請好友';

  @override
  String rewardInviteFriendDesc(int balls) {
    return '好友使用邀請碼註冊後，你獲得 +$balls 球，好友也獲得 +$balls 球';
  }

  @override
  String get rewardGetInviteCode => '取得邀請碼';

  @override
  String get rewardYourInviteCode => '你的邀請碼';

  @override
  String get rewardInviteCodeCopied => '邀請碼已複製';

  @override
  String get rewardInvitedFriends => '已邀請好友';

  @override
  String get rewardNoInviteHistory => '尚無邀請紀錄';

  @override
  String get rewardShareInviteHint => '分享你的邀請碼，邀請好友一起練習！';

  @override
  String get rewardEnterCodeTitle => '輸入邀請碼';

  @override
  String rewardEnterCodeDesc(int balls) {
    return '輸入好友的邀請碼，你獲得 +$balls 球，好友也獲得 +$balls 球';
  }

  @override
  String get rewardEnterCodeEmpty => '請輸入邀請碼';

  @override
  String get rewardInviteCodeInvalid => '邀請碼無效';

  @override
  String rewardApplyFailed(String error) {
    return '套用失敗：$error';
  }

  @override
  String get rewardApplying => '套用中...';

  @override
  String rewardApplyButton(int balls) {
    return '套用 +$balls 球';
  }

  @override
  String get rewardEnterFriendCode => '輸入好友邀請碼';

  @override
  String get rewardFeedbackTitle => '問題回饋';

  @override
  String get rewardFeedbackTypeBug => '🐛 問題回報';

  @override
  String get rewardFeedbackTypeFeature => '💡 功能建議';

  @override
  String get rewardFeedbackTypeOther => '💬 其他';

  @override
  String get rewardFeedbackHint => '請詳細描述你的回饋...';

  @override
  String get rewardSelectVideo => '選擇影片';

  @override
  String get rewardChangeVideo => '更換影片';

  @override
  String get rewardUploadImage => '上傳圖片';

  @override
  String get rewardChangeImage => '更換圖片';

  @override
  String get rewardFeedbackEmpty => '請輸入回饋內容';

  @override
  String get rewardFeedbackSubmitted => '回饋已送出，感謝你的意見！';

  @override
  String rewardSubmitFailed(String error) {
    return '提交失敗：$error';
  }

  @override
  String get rewardSubmitFeedback => '送出回饋';

  @override
  String rewardSubmitFeedbackWithBalls(int balls) {
    return '送出回饋 +$balls 球';
  }

  @override
  String get rewardWriteFeedback => '填寫回饋';

  @override
  String rewardWriteFeedbackWithBalls(int balls) {
    return '填寫回饋 +$balls 球';
  }

  @override
  String get rewardNoVideoHistory => '尚無歷史錄影';

  @override
  String get rewardLongVideo => '長影片';

  @override
  String get rewardShortVideo => '短影片';

  @override
  String get rewardUploadDataTitle => '上傳分析資料';

  @override
  String get rewardNoUploadable => '目前沒有可上傳的分析資料';

  @override
  String rewardUploadPartialFail(int count) {
    return '$count 筆上傳失敗，已略過';
  }

  @override
  String get rewardUploadFailed => '上傳失敗，請稍後再試';

  @override
  String get rewardUploadResubmitBlocked =>
      '送審未成功：資料可能已提交過（含審核未通過者不可重送），或網路異常請稍後再試';

  @override
  String rewardUploadError(String error) {
    return '上傳失敗：$error';
  }

  @override
  String rewardUploadAvailableCount(int available, int uploaded) {
    return '可上傳 $available 筆，已上傳 $uploaded 筆';
  }

  @override
  String rewardUploadAllDone(int count) {
    return '所有分析資料已上傳（共 $count 筆）';
  }

  @override
  String rewardUploadReviewStatus(int pending, int approved) {
    return '審核中 $pending 筆 / 已通過 $approved 筆';
  }

  @override
  String rewardUploadRejectedSuffix(int count) {
    return ' / 未通過 $count 筆';
  }

  @override
  String get rewardUploadRejectedNote => '未通過審核的資料不可重新提交';

  @override
  String get rewardSelectUploadVideo => '選擇要上傳的錄影';

  @override
  String get rewardSelectUploadSubtitle => '選擇一筆後按「確認上傳」獲得獎勵';

  @override
  String get rewardNoneSelected => '尚未選擇';

  @override
  String get rewardOneSelected => '已選 1 筆';

  @override
  String rewardConfirmUpload(int balls) {
    return '確認上傳 +$balls 球';
  }

  @override
  String get rewardAnalyzed => '已分析';

  @override
  String rewardDurationSec(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get settingsNameSyncFailed => '名稱已更新，但伺服器同步失敗';

  @override
  String get settingsGoogleCredentialFailed => '無法取得 Google 憑證，請重試';

  @override
  String get settingsGoogleLinkFailed => 'Google 綁定失敗，請稍後再試';

  @override
  String get shareImportTitle => '從分享連結取得';

  @override
  String get shareImportEnterCodeTitle => '輸入 16 碼分享碼';

  @override
  String get shareImportEnterCodeDesc => '對方分享後，輸入分享碼即可下載影片到本機';

  @override
  String get shareImportCodeValidator => '請輸入完整的 16 碼分享碼';

  @override
  String get shareImportLooking => '查詢中…';

  @override
  String get shareImportLookup => '查詢';

  @override
  String get shareImportFrom => '來自';

  @override
  String get shareImportSize => '大小';

  @override
  String get shareImportExpiry => '到期';

  @override
  String get shareImportReenter => '重新輸入';

  @override
  String get shareImportDownload => '下載到本機';

  @override
  String get shareImportPreparing => '準備下載…';

  @override
  String get shareImportDownloading => '下載中…';

  @override
  String get shareImportExtracting => '解壓縮中…';

  @override
  String get shareImportDoneTitle => '下載完成！';

  @override
  String get shareImportDoneDesc => '影片已加入歷史記錄';

  @override
  String get shareImportBack => '返回';

  @override
  String get shareUploadTitle => '分享連結';

  @override
  String get shareUploadChecking => '檢查分享狀態…';

  @override
  String get shareUploadCompressing => '壓縮中…';

  @override
  String get shareUploadUnknownError => '未知錯誤';

  @override
  String shareUploadUploading(String percent) {
    return '上傳中…  $percent%';
  }

  @override
  String get shareUploadCodeReused => '現有分享碼（尚未過期）';

  @override
  String get shareUploadCodeNew => '分享碼（有效 1 天）';

  @override
  String get shareUploadCopy => '複製';

  @override
  String get shareUploadCopied => '已複製分享碼';

  @override
  String shareUploadShareText(String code) {
    return '高爾夫揮桿分享碼：$code\n（有效 1 天，請在 App 中輸入此碼取得影片）';
  }

  @override
  String get shareUploadSystemShare => '系統分享';

  @override
  String get shotRecTitle => '即時揮桿模式';

  @override
  String get shotRecSettings => '錄製設定';

  @override
  String shotRecShotsCompleted(int count) {
    return '已完成 $count 桿';
  }

  @override
  String get shotRecReady => '準備';

  @override
  String get shotRecCalibrating => '校準中…請保持靜止';

  @override
  String shotRecAddressPrompt(int current, int total) {
    return '請站到準備姿勢 ($current/$total)';
  }

  @override
  String get shotRecAddressSubText => '站定後將自動開始錄影';

  @override
  String get shotRecDetecting => '⚡ 偵測中…請揮桿';

  @override
  String get shotRecStop => '停止';

  @override
  String shotRecSwingDetected(String seconds) {
    return '偵測到揮桿 ✓\n倒數 ${seconds}s';
  }

  @override
  String get shotRecAnalyzing => '分析中…';

  @override
  String get shotRecExtractingAudio => '提取音訊…';

  @override
  String get shotRecDetectingImpact => '偵測擊球…';

  @override
  String get shotRecClipping => '切片中…';

  @override
  String get shotRecScoringAudio => '聲音分析中…';

  @override
  String get shotRecDone => '完成！';

  @override
  String get shotRecWatch => '觀看';

  @override
  String shotRecNextShot(int countdown) {
    return '下一桿 ($countdown)';
  }

  @override
  String get shotRecVideoQuality => '影片畫質';

  @override
  String get shotRecFrameRate => '幀率';

  @override
  String get shotRecEnableAudio => '錄製音訊';

  @override
  String get shotRecApply => '套用';

  @override
  String get shotRecAddressTimeout => '未偵測到準備姿勢，已取消';

  @override
  String get shotRecNoAnalysisWarning => '此裝置不支援錄影期間同步骨架偵測，仍會自動偵測揮桿';

  @override
  String get shotRecRecordFailed => '本次揮桿錄製失敗（未取得有效影像），請重試';

  @override
  String get shotRecNoSwingDetected => '未偵測到揮桿，請重試';

  @override
  String get shotRecClipFailed => '切片失敗，請重試';

  @override
  String shotRecLiveShotName(int number) {
    return '即時第$number桿';
  }

  @override
  String get termsPageSubtitle => '使用者條款與隱私政策';

  @override
  String get termsReadPrompt => '請閱讀以下條款後，勾選同意即可開始使用';

  @override
  String get termsScrolledToBottom => '已閱讀至條款末端，請返回頂部勾選同意。';

  @override
  String get termsDeclineTitle => '確認離開';

  @override
  String get termsDeclineContent => '不同意使用者條款將無法使用 ORVIA。確定要離開嗎？';

  @override
  String get termsDeclineBack => '返回';

  @override
  String get termsDeclineExit => '離開';

  @override
  String get termsPrivacyOpenFailed => '無法開啟隱私政策頁面，請稍後再試';

  @override
  String get termsAgreePrefix => '我已閱讀並同意《使用者條款》與《';

  @override
  String get termsPrivacyLink => '隱私政策';

  @override
  String get termsAgreeSuffix => '》';

  @override
  String get termsAnalyticsTitle => '允許使用統計追蹤（選用）';

  @override
  String get termsAnalyticsDesc => '協助我們改善 App 體驗，不包含個人身份資訊';

  @override
  String get termsScrollFirst => '請先滑動閱讀完整條款後方可勾選同意';

  @override
  String get termsDisagree => '不同意';

  @override
  String get termsAgreeAndContinue => '同意並繼續';

  @override
  String get termsOpenPrivacyFull => '開啟完整隱私政策';

  @override
  String get termsSec1Title => '一、服務說明';

  @override
  String get termsSec1Body =>
      'ORVIA（以下簡稱「本服務」）由 ORVIA 團隊提供，旨在協助使用者透過行動裝置錄製、分析高爾夫揮桿動作，並提供相關數據統計與建議。\n\n使用本服務前，請仔細閱讀以下條款。一旦您開始使用本服務，即表示您已閱讀、理解並同意本條款之所有內容。';

  @override
  String get termsSec2Title => '二、帳號與安全';

  @override
  String get termsSec2Body =>
      '1. 您須透過電子郵件或 Google 帳號完成註冊，方可使用完整功能。\n2. 您有責任妥善保管帳號密碼，並對所有使用您帳號進行的活動負責。\n3. 若發現帳號遭未授權使用，請立即通知我們。\n4. 您不得將帳號轉讓予他人。';

  @override
  String get termsSec3Title => '三、使用者行為規範';

  @override
  String get termsSec3Body =>
      '使用本服務時，您同意：\n\n1. 僅上傳您本人拍攝或擁有合法授權的影片內容。\n2. 不上傳任何違法、侵權或不當內容。\n3. 不干擾或破壞本服務的正常運作。\n4. 不嘗試未授權存取本服務的系統或資料。';

  @override
  String get termsSec4Title => '四、影片與資料處理';

  @override
  String get termsSec4Body =>
      '1. 您上傳的影片與分析資料將儲存於本服務的雲端系統，以提供揮桿分析功能。\n2. 分享功能產生的分享連結有效期為 1 天，到期後將自動刪除相關檔案。\n3. 您可隨時在 App 內刪除個人資料及錄影記錄。\n4. 我們不會將您的個人影片提供給未經授權的第三方。';

  @override
  String get termsSec5Title => '五、隱私政策';

  @override
  String get termsSec5Body =>
      '我們重視您的隱私，並依照以下原則收集與使用您的資訊：\n\n收集的資訊：\n• 帳號資訊（電子郵件、顯示名稱）\n• 揮桿影片及分析結果\n• 裝置資訊與使用紀錄\n\n使用統計追蹤（需您同意）：\n• 我們可能收集匿名使用資料（功能點擊、頁面瀏覽等）\n• 用於改善 App 體驗與功能設計\n• 不包含個人身份資訊，可隨時在設定中關閉\n\n資料保護：\n• 所有資料傳輸採用 TLS 加密\n• 伺服器端資料進行加密儲存\n• 定期進行安全稽核\n\n完整隱私政策請見：https://orvia.atk.tw/privacy.html';

  @override
  String get termsSec6Title => '六、智慧財產權';

  @override
  String get termsSec6Body =>
      '1. 本服務的軟體、介面設計、商標及所有相關內容均屬 ORVIA 所有，受著作權法保護。\n2. 您上傳的影片著作權歸您所有，但您授予本服務使用這些內容以提供分析服務的有限授權。\n3. 未經授權，您不得複製、修改或散布本服務的任何部分。';

  @override
  String get termsSec7Title => '七、免責聲明';

  @override
  String get termsSec7Body =>
      '1. 本服務提供的揮桿分析結果僅供參考，不構成專業運動指導建議。\n2. 本服務以「現狀」提供，不保證服務永遠不間斷或無誤差。\n3. 對於因使用本服務所產生的任何直接或間接損失，本服務不負賠償責任。\n4. 揮桿練習涉及身體活動，請在安全環境下進行，並自行評估身體狀況。';

  @override
  String get termsSec8Title => '八、服務變更與終止';

  @override
  String get termsSec8Body =>
      '1. 我們保留在任何時間修改、暫停或終止本服務的權利。\n2. 若本條款有重大變更，我們將透過 App 通知您。\n3. 繼續使用本服務視為接受更新後的條款。';

  @override
  String get termsSec9Title => '九、聯絡我們';

  @override
  String get termsSec9Body =>
      '若您對本條款有任何疑問，請透過以下方式聯絡我們：\n\n電子郵件：support@atk.tw\n服務網站：https://orvia.atk.tw\n隱私政策：https://orvia.atk.tw/privacy.html\n\n本條款最後更新日期：2026 年 5 月 25 日';

  @override
  String get testVideoTitle => '選擇測試影片';

  @override
  String testVideoLoadError(String error) {
    return '載入影片失敗\n$error';
  }

  @override
  String get testVideoEmpty => '尚無已導入的影片';

  @override
  String get testVideoSelect => '選擇';

  @override
  String get testVideoHint => '💡 提示：選擇一支影片作為測試錄製，用於演示和測試分析功能';

  @override
  String get upgradeSubscribed => '已訂閱';

  @override
  String get upgradeCurrentPlanActive => '目前方案';

  @override
  String get upgradeMonthly => '月繳';

  @override
  String get upgradeYearly => '年繳（享約 2 個月折扣）';

  @override
  String upgradeSubscribeFailed(String error) {
    return '訂閱失敗：$error';
  }

  @override
  String get upgradeProductLoadFailed => '商品載入失敗，請稍後再試';

  @override
  String get upgradeAppStoreSubscribe => 'App Store 訂閱';

  @override
  String get upgradeGooglePlaySubscribe => 'Google Play 訂閱';

  @override
  String get upgradeManageSubscriptionIos => '訂閱後可隨時在 App Store 管理或取消';

  @override
  String get upgradeManageSubscriptionAndroid => '訂閱後可隨時在 Google Play 管理或取消';

  @override
  String get upgradeBuyBalls => '單買球數';

  @override
  String get upgradeNoExpiry => '不限時間使用';

  @override
  String upgradeBallCount(int count) {
    return '$count 球';
  }

  @override
  String get upgradeBallPackValidity => '永久有效，隨時使用';

  @override
  String get upgradeBuyButton => '購買';

  @override
  String upgradePurchaseFailed(String error) {
    return '購買失敗：$error';
  }

  @override
  String upgradeBuyBallCount(int count) {
    return '購買 $count 球';
  }

  @override
  String get upgradeBallPackDescription => '球數永久有效，不限時間使用。用完每日配額後自動消耗。';

  @override
  String get upgradeAppStorePurchase => 'App Store 購買';

  @override
  String get upgradeGooglePlayPurchase => 'Google Play 購買';

  @override
  String get usageTitle => '使用紀錄';

  @override
  String get usageSubtitle => 'AI 分析 & 球數流水帳';

  @override
  String get usageTabAnalysis => 'AI 分析紀錄';

  @override
  String get usageTabBalls => '球數流水帳';

  @override
  String get usageLoadFailed => '載入失敗，請下拉重試';

  @override
  String usageLoadError(String error) {
    return '載入錯誤：$error';
  }

  @override
  String get usageEmptyAnalysis => '尚無分析紀錄';

  @override
  String get usageAllLoaded => '已載入全部紀錄';

  @override
  String get usageSummaryTotalAnalysis => '累計分析';

  @override
  String get usageUnitTimes => '次';

  @override
  String get usageSummaryTodayUsed => '今日已用';

  @override
  String get usageAnalysisItemTitle => 'AI 揮桿分析';

  @override
  String get usageSourceDailyQuota => '每日配額';

  @override
  String get usageSourceBonusBall => '獎勵球';

  @override
  String get usageSourceDailyQuotaDesc => '使用每日配額';

  @override
  String get usageSourceBonusBallDesc => '消耗 1 顆球';

  @override
  String get usageEmptyBalls => '尚無球數紀錄';

  @override
  String get usageSummaryTotalRecords => '累計筆數';

  @override
  String get usageUnitRecords => '筆';

  @override
  String get usageSummaryCurrentBalls => '目前球數';

  @override
  String get usageUnitBalls => '球';

  @override
  String usageBallBalance(int balance) {
    return '餘額 $balance 球';
  }

  @override
  String get usageDateToday => '今天';

  @override
  String get usageDateYesterday => '昨天';

  @override
  String waveformCrispScore(int score) {
    return '清脆度 $score';
  }

  @override
  String waveformPeakLabel(String level) {
    return '峰值 $level';
  }

  @override
  String get extImportProgressCopying => '複製影片中...';

  @override
  String get extImportProgressTranscoding => '轉檔準備中...';

  @override
  String get extImportProgressDurationInvalid => '影片時長不符 (需 1-600 秒)';

  @override
  String get extImportProgressThumbnail => '生成縮圖中...';

  @override
  String get extImportProgressDone => '匯入完成 ✅';

  @override
  String get learnHubGoodSwingTitle => '良好揮桿示範';

  @override
  String get learnHubGoodSwingDesc => '節奏平順、重心穩定、擊球後收桿完整。';

  @override
  String get learnHubEarlyReleaseTitle => '常見錯誤：提前釋放';

  @override
  String get learnHubEarlyReleaseDesc => '手腕提前放鬆，導致桿頭加速度不足，球路弱/右曲。';

  @override
  String get learnHubMarkerBackswingTop => '上桿頂點';

  @override
  String get learnHubMarkerBackswingTopNote => '重心仍在腳中，桿身與手臂成直線';

  @override
  String get learnHubMarkerImpact => '擊球瞬間';

  @override
  String get learnHubMarkerImpactNote => '手位在球前方，身體旋轉帶動擊球';

  @override
  String get learnHubMarkerFinish => '收桿';

  @override
  String get learnHubMarkerFinishNote => '重心轉向前腳，身體保持平衡';

  @override
  String get learnHubMarkerEarlyReleaseTopNote => '手腕角度過早放鬆，桿頭落後';

  @override
  String get learnHubMarkerPreImpact => '擊球前';

  @override
  String get learnHubMarkerPreImpactNote => '手部領先不足，重心偏後';

  @override
  String get learnHubMarkerEarlyReleaseFinishNote => '重心未移到前腳，平衡不佳';

  @override
  String get playerTimelineAbbrAddress => '準';

  @override
  String get playerTimelineAbbrTakeaway => '起';

  @override
  String get playerTimelineAbbrBackswing => '上';

  @override
  String get playerTimelineAbbrTop => '頂';

  @override
  String get playerTimelineAbbrDownswing => '下';

  @override
  String get playerTimelineAbbrImpact => '擊';

  @override
  String get playerTimelineAbbrFollowthrough => '送';

  @override
  String get playerTimelineAbbrFinish => '收';

  @override
  String get recHistSheetTitle => '曾經錄影紀錄';

  @override
  String get recTabsToday => '今天';

  @override
  String get recTabsYesterday => '昨天';

  @override
  String recTabsDateMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get recWidgetsZoomWide => '最廣';

  @override
  String get recWidgetsSavingVideo => '儲存影片中…';

  @override
  String get rewardFriendFallbackName => '好友';

  @override
  String get upgradeHighlightFullFeatured => '完整錄影與分析功能';

  @override
  String get upgradeHighlightAiDaily10 => 'AI 教練分析每日 10 次';

  @override
  String get upgradeHighlightBuyMore => '球數用完可購買加值';

  @override
  String get upgradeHighlightAiDaily90 => 'AI 教練分析每日 90 次';

  @override
  String get upgradeHighlightAiUnlimited => 'AI 教練分析無限次';

  @override
  String get upgradeFeatureAutoClip => '長影片自動切片';

  @override
  String get upgradeFeatureVoiceHint => '即時語音提示';

  @override
  String get upgradeFeatureAudioScore => '音頻分析（擊球評分）';

  @override
  String get upgradeFeatureDualVideo => '雙影片比較';

  @override
  String get upgradeFeatureAiCoachAnalysis => 'AI 教練分析';

  @override
  String get upgradeQuotaDaily10 => '每日10球';

  @override
  String get upgradeQuotaDaily90 => '每日90球';

  @override
  String get upgradeQuotaUnlimited => '無限';

  @override
  String get upgradeBadgePopular => '熱門';

  @override
  String get upgradeBadgeValue => '划算';

  @override
  String get upgradeBadgeBestDeal => '最優惠';

  @override
  String get upgradePerYear => '/年';

  @override
  String get usageReasonAd => '看廣告獎勵';

  @override
  String get usageReasonFeedback => '問題回饋獎勵';

  @override
  String get usageReasonInvite => '邀請好友獎勵';

  @override
  String get usageReasonUpload => '上傳資料獎勵';

  @override
  String get usageReasonAnalysis => 'AI 分析消耗';

  @override
  String get usageReasonManual => '手動調整';

  @override
  String get usageReasonOther => '其他';

  @override
  String get waveformPeakHigh => '高';

  @override
  String get waveformPeakMid => '中';

  @override
  String get waveformPeakLow => '低';

  @override
  String get waveformFreqCrispy => '偏清脆';

  @override
  String get waveformFreqMid => '中音';

  @override
  String get waveformFreqMuffled => '偏悶';

  @override
  String get historyProgressV2AudioScan => 'V2 音訊掃描中...';

  @override
  String get historyProgressV3AudioScan => 'V3 音訊掃描中...';

  @override
  String get historyProgressWaitingConfirm => '等待確認片段...';

  @override
  String get historyProgressClipping => '裁切片段中...';

  @override
  String historyProgressClippingPct(int pct, int cur, int total) {
    return '裁切片段中... $pct% ($cur/$total)';
  }

  @override
  String historyProgressV3SkeletonAnalysis(int cur, int total) {
    return 'V3 骨架分析 $cur/$total';
  }

  @override
  String historyProgressV3SkeletonItem(int cur, int total) {
    return '第$cur/$total個';
  }

  @override
  String get historyProgressDetectingHit => '偵測擊球中...';

  @override
  String get historyProgressVideoAnalysis => '視頻分析中...';

  @override
  String get historyProgressDetectingPhase => '偵測揮桿階段...';

  @override
  String get historyProgressAudioAnalysis => '音頻分析中...';

  @override
  String get historyDlLabelFull => '完整分析';

  @override
  String get historyDlDescFull => '骨架 + 球軌跡 overlay';

  @override
  String get historyDlLabelSkeleton => '骨架版';

  @override
  String get historyDlDescSkeleton => '只含骨架 overlay';

  @override
  String get historyDlLabelClip => '原始切片';

  @override
  String get historyDlDescClip => '無 overlay 的原始切片';

  @override
  String get historyDlLabelRaw => '原始影片';

  @override
  String get historyDlDescRaw => '無任何 overlay';

  @override
  String get historyDlLabelRawMov => '原始影片 (MOV)';

  @override
  String get historyDlDescRawMov => '原始 MOV 檔';

  @override
  String historyCandidateDuration(int seconds) {
    return '$seconds 秒';
  }

  @override
  String recDetailPointCount(int count) {
    return '$count 點';
  }
}
