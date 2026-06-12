// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ORVIA';

  @override
  String get appTagline => 'Smart Swing Training Platform';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonOpenSettings => 'Open Settings';

  @override
  String get commonOk => 'OK';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonUnknownError =>
      'An unknown error occurred, please try again later';

  @override
  String get authWelcomeBack => 'Welcome Back!';

  @override
  String get authLoginSubtitle =>
      'Login to ORVIA to sync swing data and explore the latest analysis reports.';

  @override
  String get authRegisterTitle => 'Create Account';

  @override
  String get authRegisterSubtitle =>
      'Fill in the details below to start using ORVIA.';

  @override
  String get authLoginTitle => 'Sign In';

  @override
  String get authUsernameOrEmail => 'Username / Email';

  @override
  String get authUsernameHint => 'username or you@example.com';

  @override
  String get authUsername => 'Username';

  @override
  String get authUsernameHintReg => 'Used for login, must be unique';

  @override
  String get authEmail => 'Email';

  @override
  String get authDisplayName => 'Display Name (Optional)';

  @override
  String get authDisplayNameHint => 'Same as username if left empty';

  @override
  String get authPassword => 'Password';

  @override
  String get authPasswordLabel => 'Password (at least 6 characters)';

  @override
  String get authConfirmPassword => 'Confirm Password';

  @override
  String get authRememberMe => 'Remember Me';

  @override
  String get authForgotPassword => 'Forgot Password?';

  @override
  String get authLoginButton => 'Login to ORVIA';

  @override
  String get authRegisterButton => 'Create Account';

  @override
  String get authSocialDivider => 'Or sign in with social account';

  @override
  String get authLoginWithGoogle => 'Continue with Google';

  @override
  String get authGoogleSigningIn => 'Signing in with Google...';

  @override
  String get authLoginWithApple => 'Continue with Apple';

  @override
  String get authAppleSigningIn => 'Signing in with Apple...';

  @override
  String get authNoAccount => 'Don\'t have an account? Register now';

  @override
  String get authHaveAccount => 'Already have an account? Back to Login';

  @override
  String get validationEnterUsernameOrEmail =>
      'Please enter your username or email';

  @override
  String get validationEnterPassword => 'Please enter your password';

  @override
  String get validationEnterEmail => 'Please enter your email';

  @override
  String get validationInvalidEmail => 'Invalid email format';

  @override
  String get validationEnterUsername => 'Please enter a username';

  @override
  String get validationUsernameTooShort =>
      'Username must be at least 3 characters';

  @override
  String get validationPasswordTooShort =>
      'Password must be 8+ characters with uppercase, lowercase and a digit';

  @override
  String get validationPasswordMismatch => 'Passwords do not match';

  @override
  String get validationEnterPasswordAgain => 'Please re-enter your password';

  @override
  String get msgLoginSuccess => 'Login successful, welcome back!';

  @override
  String get msgLoginFailed => 'Login failed, please check your credentials';

  @override
  String msgLoginFailedWithError(String error) {
    return 'Login failed: $error';
  }

  @override
  String get msgRegisterSuccess => 'Registration successful, please login';

  @override
  String get msgRegisterFailed => 'Registration failed';

  @override
  String msgRegisterFailedWithError(String error) {
    return 'Registration failed: $error';
  }

  @override
  String get msgGoogleLoginCancelled => 'Google login cancelled';

  @override
  String get msgGoogleLoginSuccess => 'Google login successful, welcome back!';

  @override
  String msgGoogleLoginFailed(String error) {
    return 'Google login failed: $error';
  }

  @override
  String get msgGoogleLoginNoToken =>
      'Google login failed: server did not return an auth token';

  @override
  String get msgAppleLoginCancelled => 'Apple sign-in cancelled';

  @override
  String get msgAppleLoginSuccess => 'Apple sign-in successful, welcome back!';

  @override
  String msgAppleLoginFailed(Object error) {
    return 'Apple sign-in failed: $error';
  }

  @override
  String get msgAppleLoginNoToken =>
      'Apple sign-in failed: server did not return an auth token';

  @override
  String get permTitle => 'Please Allow Bluetooth & Location';

  @override
  String get permSubtitle => 'Bluetooth permission is required on first login.';

  @override
  String get permGranted => 'Granted';

  @override
  String get permDenied => 'Not Allowed';

  @override
  String get permLocation => 'Location';

  @override
  String get permCheckAgain => 'Check Permissions Again';

  @override
  String get permStatusTitle => 'Permission Status';

  @override
  String get permNotChecked => 'Permissions not yet checked';

  @override
  String get permDialogTitle => 'Permission Required';

  @override
  String get permGoToSettings => 'Go to Settings';

  @override
  String get permIKnow => 'Got It';

  @override
  String get permBluetooth => 'Please allow Bluetooth permission.';

  @override
  String get permIosInstructions =>
      'Location permission is required for Bluetooth scanning:\n\n1. Tap \"Open Settings\"\n2. Find \"Golf Score App\"\n3. Tap \"Location\" → \"While Using the App\"\n4. Return to the app and login again';

  @override
  String get permAndroidInstructions =>
      'Please allow the following permissions in system settings:\n1. Go to \"Apps & Notifications\"\n2. Select ORVIA → Permissions\n3. Enable \"Nearby Devices, Bluetooth\" and \"Location\"';

  @override
  String get permStatusGranted => 'Granted';

  @override
  String get permStatusDenied => 'Denied';

  @override
  String get navHome => 'Home';

  @override
  String get navData => 'Data';

  @override
  String get navRecord => 'Record';

  @override
  String get navHistory => 'History';

  @override
  String get navPremium => 'Premium';

  @override
  String get homeLogout => 'Logout';

  @override
  String get homeConfirmLogout => 'Confirm Logout';

  @override
  String get homeConfirmLogoutMsg => 'Are you sure you want to logout?';

  @override
  String get homeConfirmLogoutBtn => 'Confirm Logout';

  @override
  String get homeTodayUnlimited => 'Today: Unlimited 🏆';

  @override
  String homeTodayUsage(int used, int total) {
    return 'Today: $used / $total balls';
  }

  @override
  String homeTodayUsageBonus(int used, int total, int bonus) {
    return 'Today: $used / $total balls (incl. +$bonus bonus)';
  }

  @override
  String get homeTodayLimit => '⚠️ Limit reached';

  @override
  String get homeProfile => 'Profile';

  @override
  String get homeRewards => 'Rewards';

  @override
  String get homeGoodShot => 'Good Shot';

  @override
  String get homeBadShot => 'Bad Shot';

  @override
  String get homeTotalShots => 'Total Shots';

  @override
  String get homeAvgScore => 'Avg Score';

  @override
  String get homeNoDataYet => 'No data yet today';

  @override
  String get homeStartRecording => 'Start Recording';

  @override
  String get recTitle => 'New Session';

  @override
  String get recStartRecording => 'Start Recording';

  @override
  String get recSelectLocalVideo => 'Select Local Video';

  @override
  String get recImportFromShare => 'Import from Share Link';

  @override
  String get recImporting => 'Importing...';

  @override
  String get recSelected => 'Selected';

  @override
  String get recSuccess => 'Import Successful';

  @override
  String get recFailed => 'Import Failed';

  @override
  String get recCancelled => 'Cancelled';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty => 'No recordings yet';

  @override
  String get historyDeleteConfirm => 'Delete this recording?';

  @override
  String get historyDeleteConfirmMsg => 'This action cannot be undone.';

  @override
  String get upgradeTitle => 'Upgrade Plan';

  @override
  String get upgradeFreeForever => 'Free Forever';

  @override
  String get upgradePerMonth => '/month';

  @override
  String get upgradeRecommended => 'Recommended';

  @override
  String get upgradeCurrentPlan => 'Current Plan';

  @override
  String get upgradeSubscribe => 'Subscribe Now';

  @override
  String get upgradeFeatureSwingRecording => 'Swing Recording';

  @override
  String get upgradeFeatureVideoAnalysis => 'Video Clip Analysis';

  @override
  String get upgradeFeatureVoice => 'Real-time Voice';

  @override
  String get upgradeFeatureBallTrack => 'Ball Trajectory';

  @override
  String get upgradeFeatureOverlay => 'Overlay Analysis';

  @override
  String get upgradeFeatureClubTrack => 'Club Head Tracking';

  @override
  String get upgradeFeaturePose => 'Pose Skeleton Analysis';

  @override
  String get upgradeFeatureRhythm => 'Rhythm / Speed Analysis';

  @override
  String get upgradeFeatureScore => 'Swing Score';

  @override
  String get upgradeFeatureAiCoach => 'AI Posture Advice';

  @override
  String get upgradeFeatureTraining => 'Training Suggestions';

  @override
  String get upgradeFeatureCorrection => 'Correction Tracking';

  @override
  String get upgradeFeatureReport => 'Daily / Monthly Reports';

  @override
  String get upgradeFeatureCompare => 'Compare with Others';

  @override
  String get upgradeFeatureAds => 'Ads';

  @override
  String get upgradeUnlimited => 'Unlimited';

  @override
  String get upgradeHighQuality => 'High Quality';

  @override
  String get upgradeHistoryCompare => 'History Compare';

  @override
  String get upgradeNoAds => 'Ad-free';

  @override
  String get upgradeAdvanced => 'Advanced';

  @override
  String get todayTitle => 'Today';

  @override
  String get todaySwingCount => 'Swing Count';

  @override
  String get todayGoodRate => 'Good Rate';

  @override
  String get todayAvgSpeed => 'Avg Speed';

  @override
  String get aiCoachTitle => 'AI Coach Analysis';

  @override
  String get aiCoachAnalyzing => 'Analyzing... usually 10–30 seconds';

  @override
  String get aiCoachNoData => 'No analysis data';

  @override
  String get aiCoachBasis => 'Basis';

  @override
  String get aiCoachSuggestion => 'Suggestion';

  @override
  String get profileTitle => 'Edit Profile';

  @override
  String get profileAvatar =>
      'Set an avatar so coaches can identify you more easily';

  @override
  String get profileRemoveAvatar => 'Remove Avatar';

  @override
  String get profilePersonalInfo => 'Personal Info';

  @override
  String get profileDisplayName => 'Display Name';

  @override
  String get profileSaveChanges => 'Save Changes';

  @override
  String get langTitle => 'Language';

  @override
  String get langZhTW => '繁體中文';

  @override
  String get langZhCN => '简体中文';

  @override
  String get langEn => 'English';

  @override
  String get langSelectTitle => 'Select Language';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsChangeName => 'Change Name';

  @override
  String get settingsChangeNameHint => 'Enter display name';

  @override
  String get settingsChangePassword => 'Change Password';

  @override
  String get settingsCurrentPassword => 'Current Password';

  @override
  String get settingsNewPassword => 'New Password';

  @override
  String get settingsConfirmNewPassword => 'Confirm New Password';

  @override
  String get settingsCurrentPasswordRequired => 'Please enter current password';

  @override
  String get settingsConfirmChange => 'Confirm Change';

  @override
  String get settingsPasswordChanged => 'Password changed';

  @override
  String get settingsSetPassword => 'Set Password';

  @override
  String get settingsSetPasswordDesc =>
      'Set a password to also sign in with email';

  @override
  String get settingsPasswordSet => 'Password set';

  @override
  String get settingsGoogleLogin => 'Google Sign-In';

  @override
  String get settingsGoogleLinked => 'Linked';

  @override
  String get settingsGoogleNotLinked =>
      'Not linked. Tap to link Google account';

  @override
  String get settingsSectionAnalysis => 'Analysis Preferences';

  @override
  String get settingsAnalysisQuality => 'Analysis Output Quality';

  @override
  String get settingsQualityHint => 'Saved as default for future analyses';

  @override
  String get settingsApply => 'Apply';

  @override
  String settingsQualityUpdated(String quality) {
    return 'Output quality updated to \"$quality\"';
  }

  @override
  String get settingsSectionSubscription => 'Subscription';

  @override
  String get settingsViewSubscription => 'View Subscription Plans';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeSystem => 'Follow system';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsCheckUpdate => 'Check for Updates';

  @override
  String get settingsAnalytics => 'Usage Analytics';

  @override
  String get settingsAnalyticsDesc =>
      'Anonymous usage statistics to help improve the app';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTermsOfService => 'Terms & Conditions';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsPrivacyOpenFailed =>
      'Unable to open the privacy policy page, please try again later';

  @override
  String get settingsVersionCopied => 'Version copied';

  @override
  String settingsAlreadyLatest(String version) {
    return 'Already on latest version v$version';
  }

  @override
  String get settingsUpdateCheckFailed =>
      'Update check failed, please try again later';

  @override
  String get settingsConfirmLogout => 'Confirm Logout?';

  @override
  String get settingsLogoutWarning =>
      'You\'ll need to sign in again to use cloud features.';

  @override
  String get commonContinue => 'Continue';

  @override
  String get settingsDeleteAccount => 'Delete Account';

  @override
  String get settingsDeleteAccountWarning =>
      'Deleting your account permanently removes your profile, subscription and analysis history. This cannot be undone. It does not automatically refund any purchase — please cancel subscriptions separately in the App Store / Google Play. Continue?';

  @override
  String get settingsDeleteAccountConfirmTitle => 'Final Confirmation';

  @override
  String get settingsDeleteAccountConfirmHint =>
      'Type \"DELETE\" to confirm permanent account deletion.';

  @override
  String get settingsDeleteAccountFailed =>
      'Failed to delete account. Please try again later or contact support.';

  @override
  String get settingsNameUpdated => 'Name updated';

  @override
  String get settingsPickFromGallery => 'Choose from Gallery';

  @override
  String get settingsRemoveAvatar => 'Remove Avatar';

  @override
  String get homeTodayOverview => 'Today\'s Overview';

  @override
  String homeHi(String name) {
    return 'Hi, $name 👋';
  }

  @override
  String get homeRounds => 'Rounds';

  @override
  String get homePractices => 'Practice';

  @override
  String get homeTodayGoodRate => 'Today\'s Good Rate';

  @override
  String homeGoodTimes(int count) {
    return 'Good $count';
  }

  @override
  String homeBadTimes(int count) {
    return 'Bad $count';
  }

  @override
  String get homeTodayPosture => 'Today\'s Posture';

  @override
  String get homeTopSpeed => 'Peak Speed';

  @override
  String get homeSweetSpot => 'Sweet Spot';

  @override
  String get homeCrispness => 'Crispness';

  @override
  String get homeAnnouncements => 'Announcements';

  @override
  String get homeRewardBalls => 'Reward Balls';

  @override
  String get homeGreetingQuestion => 'Ready to start today\'s swing goals?';

  @override
  String get homeTodayQuota => 'Today\'s Usage';

  @override
  String homeQuotaBalls(int used, int total) {
    return '$used / $total balls';
  }

  @override
  String get homeHitAnalysis => 'Shot Analysis';

  @override
  String get homeHitRecordsLabel => 'shots recorded';

  @override
  String homeImprovedVsAvg(String pct) {
    return 'Keep it up! Today is $pct% above your average.';
  }

  @override
  String get homeTrainingFocus => 'Training Focus';

  @override
  String get homeViewNow => 'View';

  @override
  String get homeNoShotsToday => 'No shots recorded today — go record a swing!';

  @override
  String get homeEmptyHint =>
      'Record your first swing to start building your stats';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get todayTitleToday => 'Today\'s Summary';

  @override
  String get todayTitleHistory => 'History Summary';

  @override
  String get todayLoadFailed => 'Failed to load, pull down to refresh';

  @override
  String get todaySweetSpotHit => 'Sweet Spot Hit';

  @override
  String get todayCrispness => 'Sound Crispness';

  @override
  String get todayTopSpeed => 'Peak Speed';

  @override
  String get todayNoRecord => 'No practice records today';

  @override
  String get todayNoRecordDate => 'No practice records on this day';

  @override
  String get todayGoRecord => 'Go record a swing!';

  @override
  String get todayPostureToday => 'Today\'s Posture Analysis';

  @override
  String get todayPosture => 'Posture Analysis';

  @override
  String get annBoardTitle => 'Announcements';

  @override
  String annUnreadCount(int count) {
    return '$count unread';
  }

  @override
  String get annAllAnnouncements => 'All Announcements';

  @override
  String get annMarkAllRead => 'Mark All Read';

  @override
  String get annRefresh => 'Refresh';

  @override
  String get annLoadFailed => 'Failed to load, pull down to retry';

  @override
  String annMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String annHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String annDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get annDetailTitle => 'Announcement Detail';

  @override
  String annExpiresAt(String date) {
    return 'Valid until $date';
  }

  @override
  String get annEmpty => 'No announcements';

  @override
  String get annEmptySubtitle => 'New announcements will appear here';

  @override
  String get updateNotes => 'What\'s New';

  @override
  String get updateForcedWarning =>
      'This version is no longer supported. Please update to continue.';

  @override
  String get updateNow => 'Update Now';

  @override
  String get updateRemindLater => 'Remind Me Later';

  @override
  String get updateDontRemind => 'Don\'t Remind';

  @override
  String get updateCannotOpenStore =>
      'Cannot open store. Please update manually.';

  @override
  String get updateRequiredTitle => 'Required Update';

  @override
  String get updateRequiredSubtitle => 'Please update to continue using ORVIA';

  @override
  String get updateFoundTitle => 'New Version Available';

  @override
  String get updateFoundSubtitle =>
      'Update recommended for the best experience';

  @override
  String get updateCurrentVersion => 'Current Version';

  @override
  String get updateLatestVersion => 'Latest Version';

  @override
  String get upgradePageTitle => 'Upgrade Your Plan';

  @override
  String get upgradePageSubtitle =>
      'Unlock more swing analysis features and sharpen your game';

  @override
  String get upgradeFullComparison => 'Full Feature Comparison';

  @override
  String get upgradeFeatureColumn => 'Feature';

  @override
  String upgradeSubscribePlan(String plan) {
    return 'Upgrade to $plan';
  }

  @override
  String get upgradeSelectPayment => 'Select Payment Method';

  @override
  String get upgradeApplePayFailed => 'Apple Pay configuration failed to load';

  @override
  String get upgradeGooglePayFailed =>
      'Google Pay configuration failed to load';

  @override
  String get upgradePaymentFailed =>
      'Payment verification failed, please try again';

  @override
  String get upgradeSuccessMsg => 'Upgrade successful';

  @override
  String get upgradeAlreadyFree => 'You are already on the free plan';

  @override
  String get learningTitle => 'Swing Learning';

  @override
  String get learningMoreComing => 'More courses coming soon';

  @override
  String get learningVideoComingSoon =>
      'Demo video coming soon. Key points and markers available for reference.';

  @override
  String get learningKeyMarkers => 'Key Markers';

  @override
  String get myFeedbackTitle => 'My Feedback';

  @override
  String get myFeedbackSubtitle => 'Submitted feedback & official replies';

  @override
  String get myFeedbackEntry => 'View My Feedback';

  @override
  String get myFeedbackEmpty => 'No feedback yet';

  @override
  String get myFeedbackLoadFailed => 'Failed to load. Pull down to retry.';

  @override
  String get myFeedbackAllLoaded => 'All feedback loaded';

  @override
  String get myFeedbackTypeBug => 'Bug Report';

  @override
  String get myFeedbackTypeFeature => 'Feature Request';

  @override
  String get myFeedbackTypeOther => 'Other';

  @override
  String get myFeedbackAdminReply => 'Official Reply';

  @override
  String get myFeedbackNoReply => 'Awaiting reply';

  @override
  String get myFeedbackAttachedVideo => 'Video attached';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingStart => 'Get Started';

  @override
  String get onboardingRecordTitle => 'Record Your Swing';

  @override
  String get onboardingRecordDesc =>
      'Tap the record button at the bottom center to start filming. ORVIA detects each ball strike while you record.';

  @override
  String get onboardingClipTitle => 'Automatic Clipping';

  @override
  String get onboardingClipDesc =>
      'After recording, each swing is automatically cut into a 5-second clip. Review every clip on the history page.';

  @override
  String get onboardingAiTitle => 'AI Analysis';

  @override
  String get onboardingAiDesc =>
      'Send a clip to the AI coach to analyze your posture, the 8 swing phases, and the ball trajectory.';

  @override
  String get onboardingBallsTitle => 'Balls & Rewards';

  @override
  String get onboardingBallsDesc =>
      'Analysis costs balls. Get a free daily quota, and earn more by watching ads, sending feedback, or inviting friends.';

  @override
  String get settingsReplayTutorial => 'Replay Tutorial';

  @override
  String recFrameCount(int count) {
    return '$count frames';
  }

  @override
  String recDetectedShots(int count) {
    return '$count detected';
  }

  @override
  String get privacySettingsTitle => 'Privacy & Analytics';

  @override
  String get privacySectionDataCollection => 'DATA COLLECTION';

  @override
  String get privacyDataCollectionDesc =>
      'Your videos and analysis data are uploaded only when you take an action yourself — AI analysis, sharing, reward uploads, or feedback attachments. ORVIA performs no background uploads and no hidden telemetry.';

  @override
  String get privacySectionPolicies => 'POLICIES';

  @override
  String get privacySectionUpload => 'ANALYSIS DATA UPLOAD';

  @override
  String get privacyUploadDesc =>
      'You may voluntarily submit swing videos and sensor CSV data to help improve the swing detection model. Each submission is reviewed manually; approved uploads earn bonus balls.';

  @override
  String get privacyUploadStatusEntry => 'View My Upload Review Status';

  @override
  String get privacySectionAccount => 'ACCOUNT';

  @override
  String get privacyDeleteAccountSubtitle =>
      'Soft delete: you can no longer sign in and your data is anonymized';
}
