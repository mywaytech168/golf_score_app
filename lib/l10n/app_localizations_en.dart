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
  String get settingsAppleLogin => 'Apple Sign-In';

  @override
  String get settingsAppleLinked => 'Linked';

  @override
  String get settingsAppleNotLinked => 'Not linked. Tap to link Apple account';

  @override
  String get settingsAppleCredentialFailed =>
      'Unable to retrieve Apple credentials, please try again';

  @override
  String get settingsAppleLinkFailed =>
      'Apple account linking failed, please try again later';

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
  String recImpactShot(int number) {
    return 'Shot $number';
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

  @override
  String get rewardSubtitle =>
      'Complete tasks to earn balls and redeem analyses';

  @override
  String get historyFilterReset => 'Reset';

  @override
  String aiCoachUpgradeFailed(String error) {
    return 'Upgrade failed: $error';
  }

  @override
  String get aiCoachQuotaExhaustedTitle => 'Daily ball quota used up';

  @override
  String aiCoachQuotaExhaustedBody(int todayUsed, int totalLimit) {
    return 'You have used $todayUsed analyses today, reaching the limit of $totalLimit.\n\nYou can continue tomorrow, or upgrade your plan for more analyses.';
  }

  @override
  String get aiCoachGotIt => 'Got it';

  @override
  String get aiCoachAnalysisFailed => 'Analysis failed, please retry';

  @override
  String get aiCoachStatusPending => 'Preparing...';

  @override
  String get aiCoachStatusQueued => 'Waiting in analysis queue...';

  @override
  String get aiCoachStatusProcessing => 'AI Coach is analyzing the video...';

  @override
  String get aiCoachStatusIdle => 'Waiting for AI Coach analysis...';

  @override
  String get aiCoachStatusConnecting => 'Connecting...';

  @override
  String get aiCoachLoadingHint => 'Usually takes 10–30 seconds';

  @override
  String get aiCoachPostureAnalysisDone => 'Posture error analysis complete';

  @override
  String get aiCoachSubmitting => 'Submitting...';

  @override
  String get aiCoachStartAnalysis => 'Start AI Coach Analysis';

  @override
  String get aiCoachAnalysisHint =>
      '* AI Coach will provide detailed feedback and training suggestions based on posture analysis results';

  @override
  String get aiCoachEvidence => 'Evidence';

  @override
  String get aiCoachSeverityHigh => 'Severe';

  @override
  String get aiCoachSeverityMedium => 'Moderate';

  @override
  String get aiCoachSeverityLow => 'Minor';

  @override
  String get aiCoachImpactPremiumSweetSpot => 'Premium Sweet Spot';

  @override
  String get aiCoachImpactSweetSpot => 'Sweet Spot';

  @override
  String get aiCoachImpactNearSweetSpot => 'Near Sweet Spot';

  @override
  String get aiCoachImpactFair => 'Fair';

  @override
  String get aiCoachImpactPoor => 'Off-center Hit';

  @override
  String get aiCoachImpactQualityTitle => 'Impact Quality (Audio)';

  @override
  String aiCoachImpactFeatureCount(int passCount, int totalFeatures) {
    return '$passCount / $totalFeatures features match the sweet spot range';
  }

  @override
  String get aiCoachFeedbackTitle => 'Coach Feedback';

  @override
  String get aiCoachPracticeTitle => 'Training Suggestions';

  @override
  String get aiCoachNextGoalTitle => 'Next Practice Goal';

  @override
  String get aiCoachReanalyzeSubmitting => 'Submitting re-analysis...';

  @override
  String aiCoachReanalyzeFailed(String error) {
    return 'Re-analysis failed: $error';
  }

  @override
  String get ballTuneTitle => 'Ball Trajectory Tuning';

  @override
  String get ballTuneHudInit => 'Initializing…';

  @override
  String get ballTuneHudDetecting => 'Detecting…';

  @override
  String get ballTuneHudBlobFailed => 'Blob extraction failed';

  @override
  String ballTuneRoiBadge(String r, String margin) {
    return 'ROI r=${r}px  margin=$margin';
  }

  @override
  String get ballTuneRoiToggleTooltip => 'Toggle ROI overlay';

  @override
  String get ballTuneSectionRealtime => 'Realtime (applies immediately)';

  @override
  String get ballTuneSliderResidual => 'Quality gate — residual limit';

  @override
  String get ballTuneSliderP1MaxDist => 'P1 max distance';

  @override
  String get ballTuneRoiMaskSection => 'ROI / Mask (drag on preview to adjust)';

  @override
  String get ballTuneSliderRoiRadius => 'ROI radius';

  @override
  String get ballTuneSliderGolferMargin => 'Golfer mask margin';

  @override
  String get ballTuneSliderRoiMissScale => 'ROI miss large expand ×';

  @override
  String get ballTuneSliderRoiRadiusMax => 'ROI radius max';

  @override
  String get ballTuneSliderStepMaxPost => 'Post-impact step max';

  @override
  String get ballTuneSliderPredMaxPost => 'Post-impact pred max';

  @override
  String get ballTuneSliderMissPatiencePost => 'Post-impact miss tolerance';

  @override
  String get ballTuneSectionReextract =>
      'Re-extract (press button below to apply)';

  @override
  String get ballTuneSliderDiffThresh => 'diffThresh frame-diff threshold';

  @override
  String get ballTuneRedetectButton => 'Re-detect (apply diffThresh)';

  @override
  String clipCandTitle(int count) {
    return 'Confirm shots ($count candidates)';
  }

  @override
  String get clipCandTapToPreview => 'Tap to preview';

  @override
  String get clipCandRangeTooShort =>
      'Clip range must be at least 0.5 s (end must be after start)';

  @override
  String clipCandConfirmClip(int count) {
    return 'Clip $count segment(s)';
  }

  @override
  String clipCandManualHint(String start) {
    return 'Start $start → drag to end then tap \"Add range\"';
  }

  @override
  String get clipCandManualPrompt => 'Free clip: drag timeline to start point';

  @override
  String get clipCandSetStart => 'Set start';

  @override
  String get clipCandReset => 'Reset';

  @override
  String get clipCandAddRange => 'Add range';

  @override
  String clipCandCandidateLabel(int index, String time) {
    return 'Candidate $index · $time';
  }

  @override
  String get clipCandFromAudio => 'Detected by impact sound';

  @override
  String get clipCandFromMotion => 'Detected by motion during recording';

  @override
  String clipCandManualRangeLabel(String start, String end) {
    return 'Custom range · $start - $end';
  }

  @override
  String clipCandRangeDuration(String seconds) {
    return 'Duration $seconds s';
  }

  @override
  String get compareLoadingVideos => 'Loading videos…';

  @override
  String get highlightTitle => 'Highlight Preview';

  @override
  String get highlightShareSystem => 'Share';

  @override
  String get highlightExportDebug => 'Export debug';

  @override
  String get highlightShareDebug => 'Share debug';

  @override
  String get highlightShareText => 'My swing highlight';

  @override
  String get highlightDebugFileError => 'Failed to create debug file';

  @override
  String get highlightStoragePermissionRequired =>
      'Storage permission is required to export to the Downloads folder';

  @override
  String get highlightDownloadsDirNotFound => 'Downloads folder not found';

  @override
  String highlightSavedTo(String path) {
    return 'Saved to: $path';
  }

  @override
  String highlightExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String historySubtitle(int total, int good, int bad) {
    return '$total total · $good good · $bad bad';
  }

  @override
  String get historySearchHint => 'Search recordings…';

  @override
  String historySearchResult(int count, int total) {
    return 'Search results $count / $total';
  }

  @override
  String get historySearchNoResult => 'No results found';

  @override
  String historySearchNoResultHint(Object query) {
    return 'No results for \"$query\"';
  }

  @override
  String get historySearchClear => 'Clear search';

  @override
  String get historyEmptyTitle => 'No recordings yet';

  @override
  String get historyEmptySubtitle =>
      'Start recording your swings to see them here';

  @override
  String get historyFilterLabelSort => 'Sort';

  @override
  String get historyFilterLabelDate => 'Date';

  @override
  String get historyFilterLabelVideo => 'Video';

  @override
  String get historyFilterLabelGoodBad => 'Shot';

  @override
  String get historyFilterLabelAnalysis => 'Analysis';

  @override
  String get historyFilterLabelClip => 'Clip';

  @override
  String get historyFilterLabelAI => 'AI';

  @override
  String get historyFilterLabelPosture => 'Posture';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterToday => 'Today';

  @override
  String get historyFilterWeek => 'This week';

  @override
  String get historyFilterMonth => 'This month';

  @override
  String get historyFilterCustomDate => 'Custom range';

  @override
  String get historyFilterSort => 'Sort by';

  @override
  String get historyFilterGood => 'Good';

  @override
  String get historyFilterBad => 'Poor';

  @override
  String get historyFilterAnalyzed => 'Analyzed';

  @override
  String get historyFilterNotAnalyzed => 'Not analyzed';

  @override
  String get historyFilterAiAnalyzed => 'AI analyzed';

  @override
  String get historyFilterAiNotAnalyzed => 'AI not analyzed';

  @override
  String get historyFilterClipped => 'Clipped';

  @override
  String get historyFilterNotClipped => 'Not clipped';

  @override
  String get historyFilterLongVideo => 'Long video';

  @override
  String get historyFilterShortVideo => 'Short video';

  @override
  String get historySortDate => 'Date';

  @override
  String get historySortPeakSpeed => 'Peak speed';

  @override
  String get historySortClipTime => 'Clip time';

  @override
  String get historyDateRangeHelp => 'Select date range';

  @override
  String get historyDeleteTitle => 'Delete recording';

  @override
  String historyDeleteClipConfirm(Object title) {
    return 'Delete clip \"$title\"?';
  }

  @override
  String historyDeleteVideoConfirm(Object title) {
    return 'Delete recording \"$title\"?';
  }

  @override
  String historyDeleteVideoWithClipsConfirm(Object title, Object count) {
    return 'Delete \"$title\" and its $count clips?';
  }

  @override
  String historyDeletedSnack(Object name) {
    return 'Deleted $name';
  }

  @override
  String historyDeletedWithClipsSnack(Object name, Object count) {
    return 'Deleted $name and $count clips';
  }

  @override
  String get historyRenameTitle => 'Rename recording';

  @override
  String get historyRenameClipTitle => 'Rename clip';

  @override
  String get historyRenameLabel => 'New name';

  @override
  String get historyRenameHelper => 'Leave empty to reset to default name';

  @override
  String get historyRenameValidation => 'Name cannot be blank';

  @override
  String historyRenamedSnack(Object name) {
    return 'Renamed to $name';
  }

  @override
  String historyRenameResetSnack(Object name) {
    return 'Reset to default name \"$name\"';
  }

  @override
  String historyFileNotFound(Object name) {
    return 'File not found: $name';
  }

  @override
  String get historyClipFileNotExist =>
      'Clip file does not exist, please re-detect';

  @override
  String get historyAlreadyClipped =>
      'This video already has clips. Re-detect to replace them.';

  @override
  String get historyProgressPreparingSkeleton => 'Preparing skeleton analysis…';

  @override
  String get historyProgressPreparing => 'Preparing…';

  @override
  String get historyDetectingShots => 'Detecting shots';

  @override
  String get historyCancelledDetection => 'Detection cancelled';

  @override
  String get historyCancelledAnalysis => 'Analysis cancelled';

  @override
  String get historyV2NoAudio =>
      'No audio track found, cannot use audio-based detection';

  @override
  String get historyV3NoShot => 'No shot detected in skeleton analysis';

  @override
  String get historyV3NoValidHit => 'No valid impact found after filtering';

  @override
  String get historyNoShotDetected => 'No shots detected';

  @override
  String get historyClipFailed => 'Clip generation failed';

  @override
  String historyClipsGenerated(Object count) {
    return '$count clips generated';
  }

  @override
  String historyClipsGeneratedBg(Object count) {
    return '$count clips saved to history';
  }

  @override
  String historyDetectFailed(Object error) {
    return 'Detection failed: $error';
  }

  @override
  String get historyLongVideoTitle => 'Long video warning';

  @override
  String historyLongVideoContent(Object seconds) {
    return 'This video is ${seconds}s long. Full analysis may take a while.';
  }

  @override
  String get historyContinueAnalysis => 'Continue';

  @override
  String get historyFullAnalysisTitle => 'Analyzing';

  @override
  String historyInvalidDuration(Object seconds) {
    return 'Invalid video duration: ${seconds}s';
  }

  @override
  String historyAnalysisComplete(Object audio) {
    return 'Analysis complete$audio';
  }

  @override
  String historyAnalysisFailed(Object error) {
    return 'Analysis failed: $error';
  }

  @override
  String get historyQuotaExhaustedTitle => 'Daily quota reached';

  @override
  String historyQuotaExhaustedContent(Object used, Object total) {
    return 'Used $used/$total today. Upgrade to continue.';
  }

  @override
  String get historyGotIt => 'Got it';

  @override
  String get historyAiAnalysisConfirmTitle => 'AI Analysis';

  @override
  String get historyAiAnalysisConfirmDesc =>
      'Submit this swing for AI analysis. This will use 1 ball.';

  @override
  String get historyAiAnalysisConfirmBtn => 'Analyze';

  @override
  String historyAiSubmitFailed(Object error) {
    return 'Submission failed: $error';
  }

  @override
  String get historyNoOtherVideoToCompare =>
      'No other videos available to compare';

  @override
  String get historyCompareTitle => 'Compare swings';

  @override
  String historyCompareSubtitle(Object title) {
    return 'Select a video to compare with \"$title\"';
  }

  @override
  String get historyPhasesJsonMissing =>
      'phases.json not found, please re-analyze';

  @override
  String get historyPhasesJsonInvalid =>
      'phases.json is invalid, please re-analyze';

  @override
  String get historySelectAiModeTitle => 'Select AI mode';

  @override
  String get historyAiModeV1Title => 'Basic (V1)';

  @override
  String get historyAiModeV1Desc => 'Audio peak detection';

  @override
  String get historyAiModeV2Title => 'Standard (V2)';

  @override
  String get historyAiModeV2Desc => 'Audio + skeleton hybrid';

  @override
  String get historyAiModeV3Title => 'Advanced (V3)';

  @override
  String get historyAiModeV3Desc => 'Skeleton-first with audio refinement';

  @override
  String get historySelectDetectModeTitle => 'Select detection mode';

  @override
  String get historyDetectV1Title => 'Skeleton (V1)';

  @override
  String get historyDetectV1Desc => 'MediaPipe pose estimation';

  @override
  String get historyDetectBadgePrecise => 'Precise';

  @override
  String get historyDetectV1Time => '~10s';

  @override
  String get historyDetectV2Title => 'Audio (V2)';

  @override
  String get historyDetectV2Desc => 'Fast audio peak detection';

  @override
  String get historyDetectBadgeFast => 'Fast';

  @override
  String get historyDetectV2Time => '~30s';

  @override
  String get historyDetectV3Title => 'Hybrid (V3)';

  @override
  String get historyDetectV3Desc => 'Skeleton-first + audio refinement';

  @override
  String get historyDetectBadgeBalanced => 'Balanced';

  @override
  String get historyDetectV3Time => '~45s';

  @override
  String get historySkipToday => 'Don\'t show today';

  @override
  String get historyStartDetect => 'Start detection';

  @override
  String get historySelectQualityTitle => 'Select export quality';

  @override
  String get historyStartAnalysis => 'Start analysis';

  @override
  String get historyActionDetect => 'Detect shots';

  @override
  String get historyActionAiAnalysis => 'AI analysis';

  @override
  String get historyActionFullAnalysis => 'Full analysis';

  @override
  String get historyActionChart => 'Stats';

  @override
  String get historyActionPlay => 'Play';

  @override
  String get historyActionExpand => 'Expand clips';

  @override
  String get historyActionCollapse => 'Collapse clips';

  @override
  String get historyMenuRename => 'Rename';

  @override
  String get historyMenuAddNote => 'Add note';

  @override
  String get historyMenuEditNote => 'Edit note';

  @override
  String get historyMenuShare => 'Share';

  @override
  String get historyMenuDownload => 'Download';

  @override
  String get historyMenuDownloading => 'Downloading…';

  @override
  String get historyMenuCompare => 'Compare';

  @override
  String historyMenuUploadReward(int balls) {
    return 'Upload for +$balls balls';
  }

  @override
  String get historyMenuUploaded => 'Uploaded';

  @override
  String get historyMenuAnalyzing => 'Analyzing…';

  @override
  String get historyMenuDeleteVideo => 'Delete';

  @override
  String get historyMoreActions => 'More actions';

  @override
  String get historyBadgeNoAudio => 'No audio';

  @override
  String get historyBadgeAnalyzed => 'Analyzed';

  @override
  String get historySweetSpot => 'Sweet spot';

  @override
  String get historySweetSpotHit => 'Hit';

  @override
  String get historySweetSpotMiss => 'Miss';

  @override
  String get historyHitSummary => 'Shot summary';

  @override
  String historyClipDefaultName(Object index) {
    return 'Shot $index';
  }

  @override
  String historyClipHitAt(Object time) {
    return 'Impact @ $time';
  }

  @override
  String historyClipRange(Object start, Object end) {
    return 'Clip $start–${end}s';
  }

  @override
  String historyRoundLabel(Object index) {
    return 'Round $index';
  }

  @override
  String historyDurationLine(Object time, Object seconds) {
    return '$time · ${seconds}s';
  }

  @override
  String historyImportedFrom(Object name) {
    return 'From $name';
  }

  @override
  String get historyNoteDialogTitle => 'Video note';

  @override
  String get historyNoteHint => 'Practice notes, location, club used…';

  @override
  String get historyNoteHelper => 'Leave empty to clear note';

  @override
  String get historySaveLocationTitle => 'Save location';

  @override
  String get historySaveLocationDownloads => 'Downloads folder';

  @override
  String get historySaveLocationDownloadsSub => 'Save to system Downloads';

  @override
  String get historySaveLocationPick => 'Choose folder';

  @override
  String get historySaveLocationPickSub => 'Custom save location';

  @override
  String get historyDownloadVersionTitle => 'Select version';

  @override
  String historyExportSaved(Object label) {
    return '\"$label\" saved ✅';
  }

  @override
  String historyExportSavedPhotos(Object label) {
    return '\"$label\" saved to Camera Roll ✅';
  }

  @override
  String historyExportFailed(Object detail) {
    return 'Download failed: $detail';
  }

  @override
  String get historyUploadRewardTitle => 'Upload for reward';

  @override
  String historyUploadRewardContent(Object title, Object balls) {
    return 'Upload analysis data for \"$title\" to improve swing detection. After review, you\'ll receive +$balls balls.';
  }

  @override
  String get historyUploadSubmit => 'Submit for review';

  @override
  String get historyUploadingProgress => 'Uploading video and analysis data…';

  @override
  String historyUploadFailed(Object error) {
    return 'Upload failed: $error';
  }

  @override
  String get historyUploadSubmitFailed =>
      'Submission failed: this video may have already been submitted (including rejected ones), or please retry later';

  @override
  String historyUploadReviewPending(Object balls) {
    return 'Submitted for review. +$balls balls will be awarded upon approval.';
  }

  @override
  String get hitsSummaryEmpty => 'No shots detected yet';

  @override
  String hitsSummaryHitIndex(int index) {
    return 'Shot #$index';
  }

  @override
  String get hitsSummaryPeak => 'Peak';

  @override
  String get hitsSummaryDuration => 'Duration';

  @override
  String get hitsSummaryStart => 'Start';

  @override
  String get hitsSummaryEnd => 'End';

  @override
  String hitsSummaryDetectFrom(String source) {
    return 'Source: $source';
  }

  @override
  String get hitsSummaryTitle => 'Shot Summary';

  @override
  String hitsSummaryCount(int count) {
    return '$count shots total';
  }

  @override
  String get homeCurrentSuggestions => 'Current Practice Plan';

  @override
  String homeNextGoal(String goal) {
    return 'Next goal: $goal';
  }

  @override
  String get authInviteCodeOptional => 'Optional';

  @override
  String get authInviteCodeLabel => 'Invite Code';

  @override
  String get authInviteCodeHint =>
      'Enter a friend\'s invite code if you have one';

  @override
  String get authInviteCodeHelper =>
      'Enter an invite code — both of you get +5 ball rewards';

  @override
  String get devTestAccounts => 'Test Accounts';

  @override
  String get devTestPassword => 'Password: Test1234!';

  @override
  String get forgotTitle => 'Forgot Password';

  @override
  String get forgotEnterCodeTitle => 'Enter Verification Code';

  @override
  String get forgotEmailSubtitle =>
      'Enter your Email — we\'ll send you a 6-digit verification code';

  @override
  String forgotCodeSentSubtitle(String email) {
    return 'Verification code sent to $email';
  }

  @override
  String get forgotSixDigitCodeLabel => '6-digit Code';

  @override
  String get forgotNewPasswordLabel => 'New Password';

  @override
  String get forgotNewPasswordHint =>
      'At least 8 characters with uppercase, lowercase, and digits';

  @override
  String get forgotConfirmPasswordLabel => 'Confirm New Password';

  @override
  String get forgotSendCodeButton => 'Send Verification Code';

  @override
  String get forgotConfirmResetButton => 'Confirm Password Reset';

  @override
  String get forgotReEnterEmail => 'Re-enter Email';

  @override
  String get forgotEnterValidEmail => 'Please enter a valid Email';

  @override
  String get forgotSendFailed => 'Failed to send';

  @override
  String get forgotNetworkError => 'Network error, please try again later';

  @override
  String get forgotEnterSixDigitCode =>
      'Please enter the 6-digit verification code';

  @override
  String get forgotPasswordComplexity =>
      'Password must be at least 8 characters with uppercase, lowercase, and digits';

  @override
  String get forgotPasswordMismatch => 'Passwords do not match';

  @override
  String get forgotResetSuccess =>
      'Password reset — please sign in with your new password';

  @override
  String get forgotResetFailed => 'Reset failed';

  @override
  String get playerTitle => 'Video Review';

  @override
  String get playerNoteAdd => 'Add Note';

  @override
  String get playerNoteEdit => 'Edit Note';

  @override
  String get playerNoteCleared => 'Note cleared';

  @override
  String get playerNoteSaved => 'Note saved';

  @override
  String get playerVideoNotFound => 'Video file not found';

  @override
  String get playerVideoLoadFailed => 'Failed to load video';

  @override
  String get playerSkeletonNotFound => 'Skeleton data not available';

  @override
  String get playerOverlaySkeleton => 'Skeleton';

  @override
  String get playerOverlayTrajectory => 'Trajectory';

  @override
  String get playerOverlayEffect => 'Effects';

  @override
  String get playerTrajectoryTuning => 'Trajectory Tuning';

  @override
  String playerShotLabel(int index, String time) {
    return 'Shot $index $time';
  }

  @override
  String get playerStatsEmpty =>
      'No statistics yet (requires trajectory or phase analysis)';

  @override
  String get playerStatLaunchAngle => 'Launch Angle';

  @override
  String get playerStatTempo => 'Tempo (Back:Down)';

  @override
  String get playerStatBackDownswing => 'Back / Downswing';

  @override
  String get playerStatFlightTime => 'In-Frame Flight';

  @override
  String get playerChartEmpty =>
      'No chart data. Please complete analysis first.';

  @override
  String get playerChartNoData => 'No data';

  @override
  String get playerChartAudioEmpty => 'Audio peak — no data';

  @override
  String get playerChartWristYEmpty => 'Wrist Y — no data';

  @override
  String get playerChartSpeedEmpty => 'Speed — no data';

  @override
  String get playerChartTabAudio => 'Audio Peak';

  @override
  String get playerChartTabWristY => 'Wrist Y';

  @override
  String get playerChartTabSpeed => 'Speed';

  @override
  String get playerChartTabPosture => 'Posture';

  @override
  String get playerChartTabAudioFeature => 'Audio Features';

  @override
  String get playerLoadDetailScore => 'Load Detailed Scores';

  @override
  String get playerPostureEmpty =>
      'No posture analysis yet. Please complete analysis first.';

  @override
  String playerAudioPassCount(int count) {
    return '$count / 5 features passed';
  }

  @override
  String get playerAudioEmpty => 'No audio analysis yet';

  @override
  String playerAiAnalysisFailed(String error) {
    return 'AI analysis failed: $error';
  }

  @override
  String get playerAiNotStarted => 'AI coach analysis not yet started';

  @override
  String get playerAiStartAnalysis => 'Start Analysis';

  @override
  String get playerAiViewProgress => 'View Progress';

  @override
  String get playerAiCoachTitle => 'AI Coach Analysis';

  @override
  String get playerAiPrimaryIssue => 'Primary Issue';

  @override
  String get playerAiCoachFeedback => 'Coach Feedback';

  @override
  String get playerAiPracticeSuggestions => 'Practice Suggestions';

  @override
  String get playerAiNextGoal => 'Next Goal';

  @override
  String get playerAiReanalyze => 'Re-analyze';

  @override
  String get playerAiViewDetail => 'View Details';

  @override
  String get playerAiStatusPending => 'Preparing...';

  @override
  String get playerAiStatusQueued => 'Waiting in analysis queue...';

  @override
  String get playerAiStatusProcessing => 'AI coach analyzing...';

  @override
  String get playerAiStatusAnalyzing => 'Analyzing...';

  @override
  String get playerSeverityHigh => 'Severe';

  @override
  String get playerSeverityMedium => 'Moderate';

  @override
  String get playerSeverityLow => 'Minor';

  @override
  String get playerHighlightPreview => 'Highlight Preview';

  @override
  String get playerSweetSpotHit => 'Sweet Spot Hit';

  @override
  String get playerSweetSpot => 'Sweet Spot';

  @override
  String get playerThinShot => 'Thin Shot';

  @override
  String playerAudioPassCountBadge(int count) {
    return '$count/5 features matched';
  }

  @override
  String get playerNoteDialogTitle => 'Video Note';

  @override
  String get playerNoteHint => 'Jot down practice thoughts, course, club used…';

  @override
  String get playerNoteHelper => 'Leave empty to clear the note';

  @override
  String get playerPhaseAddress => 'Address';

  @override
  String get playerPhaseTakeaway => 'Takeaway';

  @override
  String get playerPhaseBackswing => 'Backswing';

  @override
  String get playerPhaseTop => 'Top';

  @override
  String get playerPhaseDownswing => 'Downswing';

  @override
  String get playerPhaseImpact => 'Impact';

  @override
  String get clipLegendStart => 'Start';

  @override
  String get clipLegendEnd => 'End';

  @override
  String get playerPhaseFollowthrough => 'Follow-through';

  @override
  String get playerPhaseFinish => 'Finish';

  @override
  String get postureTitle => 'Posture Analysis';

  @override
  String get postureNoData => 'No AI analysis data yet';

  @override
  String get profileSubtitle =>
      'Update your profile for more accurate swing analysis. Remember to save when done.';

  @override
  String get profileAvatarHint =>
      'Set a profile photo so your coach can identify you more easily';

  @override
  String get profileAvatarSaveFailed =>
      'Failed to save photo. Please try again later.';

  @override
  String get profileDisplayNameLabel => 'Nickname';

  @override
  String get profileDisplayNameHint => 'Name shown on the home screen';

  @override
  String get profileDisplayNameRequired => 'Please enter a nickname';

  @override
  String get profileEmailLabel => 'Email';

  @override
  String get profilePhoneLabel => 'Phone number';

  @override
  String get profilePhoneHint => 'e.g. 0912-345-678';

  @override
  String get profileHandicapLabel => 'Handicap';

  @override
  String get profileHandicapHint => 'Enter your current handicap or target';

  @override
  String get purchaseTestPanelTitle => '🧪 Purchase Test Panel';

  @override
  String get purchaseTestSimulateSuccessMsg =>
      '✅ Simulated purchase successful! User set to premium.';

  @override
  String purchaseTestErrorMsg(String error) {
    return '❌ Error: $error';
  }

  @override
  String get purchaseTestClearSuccessMsg =>
      '🔄 Purchase record cleared! User is now a regular user.';

  @override
  String get purchaseTestPremiumStatusLabel => 'Premium status: ';

  @override
  String get purchaseTestStatusPurchased => '✅ Subscribed';

  @override
  String get purchaseTestStatusNotPurchased => '❌ Not subscribed';

  @override
  String purchaseTestPaymentMethod(String method) {
    return 'Payment method: $method';
  }

  @override
  String get purchaseTestPaymentMethodNone => 'None';

  @override
  String get purchaseTestSimulateBtn => 'Simulate Purchase';

  @override
  String get purchaseTestClearBtn => 'Clear Purchase';

  @override
  String get purchaseTestRefreshBtn => 'Refresh Status';

  @override
  String get purchaseTestDialogTitle => '🧪 Purchase Function Test';

  @override
  String get recDetailDownloadVideo => 'Download video';

  @override
  String get exportCustomTitle => 'Custom export';

  @override
  String get exportCustomSubtitle => 'Choose elements to burn into the video';

  @override
  String get exportElementSkeleton => 'Skeleton';

  @override
  String get exportElementSkeletonDesc => 'Body pose skeleton';

  @override
  String get exportElementTrajectory => 'Ball trajectory';

  @override
  String get exportElementTrajectoryDesc => 'Ball flight path after impact';

  @override
  String get exportElementGlow => 'Impact glow';

  @override
  String get exportElementGlowDesc => 'Glowing ring at the moment of impact';

  @override
  String get exportElementSweetSpot => 'Sweet spot';

  @override
  String get exportElementSweetSpotDesc =>
      'Quality ring at impact (gold / blue / gray)';

  @override
  String get swingBothHands => 'Two-hand detection';

  @override
  String get swingBothHandsDesc =>
      'Count a swing only when both wrists move together; falls back to one hand if the other is occluded';

  @override
  String get exportNoOverlayMaterial =>
      'This video has no overlay data; the original will be exported.';

  @override
  String get exportWatermarkFree =>
      'Free exports include an ORVIA watermark — upgrade to remove';

  @override
  String get exportWatermarkPaid => 'Subscribed: no watermark';

  @override
  String get exportComposeAndDownload => 'Compose & download';

  @override
  String get recDetailNoVideoFound => 'No downloadable video found';

  @override
  String recDetailBurning(String label) {
    return 'Rendering \"$label\"…';
  }

  @override
  String get recDetailBurnFailed => 'Rendering failed, please try again later';

  @override
  String recDetailSavedToDownloads(String label) {
    return '\"$label\" saved to Downloads ✅';
  }

  @override
  String recDetailSavedToPhotos(String label) {
    return '\"$label\" saved to Camera Roll ✅';
  }

  @override
  String get recDetailSharedViaSheet => 'Share sheet opened ✅';

  @override
  String recDetailDownloadFailed(String detail) {
    return 'Download failed: $detail';
  }

  @override
  String get recDetailSkeletonPreview => 'Skeleton Preview';

  @override
  String get recDetailSkeletonLoadFailed => 'Failed to load skeleton preview';

  @override
  String get recDetailAudioPeak => 'Audio Peak';

  @override
  String get recDetailAudioPeakSubtitle => 'RMS dBFS';

  @override
  String get recDetailAudioPeakMissing => 'Audio analysis required';

  @override
  String get recDetailWristY => 'Wrist Y';

  @override
  String get recDetailWristYSubtitle => 'Right wrist Y position (px)';

  @override
  String get recDetailPoseMissing => 'Pose analysis required';

  @override
  String get recDetailSpeedSubtitle => 'Wrist movement speed (px/frame)';

  @override
  String get recDetailSpeedMissing => 'Speed';

  @override
  String get recDetailSweetSpot => 'Sweet Spot';

  @override
  String get recDetailOffCenter => 'Off-Center';

  @override
  String get recDetailAudioFeaturesTitle => 'Audio Feature Analysis';

  @override
  String recDetailFeaturePassCount(int count) {
    return '$count / 5 features within sweet spot range';
  }

  @override
  String get recDetailAutoAnalyzing => 'Uploading pose analysis, please wait…';

  @override
  String get recDetailOnnxTitle => 'ONNX Posture Analysis';

  @override
  String recDetailOnnxLoadFailed(String error) {
    return 'Load failed: $error';
  }

  @override
  String get recDetailOnnxNoResult => 'No ONNX result yet';

  @override
  String get recDetailOnnxNoScores => 'No score data';

  @override
  String get recDetailSwingPhases => 'Swing Phases';

  @override
  String get recDetailRegenerate => 'Regenerate';

  @override
  String get recDetailGeneratePhases => 'Generate phases';

  @override
  String get recDetailNoChartData => 'No chart data yet';

  @override
  String get recDetailNoChartHint =>
      'Complete audio analysis and pose analysis first';

  @override
  String get recDetailLoadFailed => 'Load failed';

  @override
  String get recDetailSelectDownloadVersion => 'Select download version';

  @override
  String get recDetailOptLabelFull => 'Full Analysis';

  @override
  String get recDetailOptDescFull => 'Skeleton + ball trajectory';

  @override
  String get recDetailOptLabelSkeleton => 'Skeleton only';

  @override
  String get recDetailOptDescSkeleton => 'Skeleton overlay only';

  @override
  String get recDetailOptLabelClip => 'Raw clip';

  @override
  String get recDetailOptDescNoOverlay => 'No overlays';

  @override
  String get recDetailOptLabelRaw => 'Original video';

  @override
  String get recDetailOptLabelRawMov => 'Original video (MOV)';

  @override
  String get recDetailOptDescRawMov => 'Raw MOV file';

  @override
  String get recDetailPhaseAddress => '①Address';

  @override
  String get recDetailPhaseTakeaway => '②Takeaway';

  @override
  String get recDetailPhaseBackswing => '③Backswing';

  @override
  String get recDetailPhaseTop => '④Top';

  @override
  String get recDetailPhaseDownswing => '⑤Downswing';

  @override
  String get recDetailPhaseImpact => '⑥Impact';

  @override
  String get recDetailPhaseFollowthrough => '⑦Release';

  @override
  String get recDetailPhaseFinish => '⑧Finish';

  @override
  String get recHistSheetEmptyHint =>
      'No recordings yet. Recordings will appear here automatically after you finish recording.';

  @override
  String get recHistSheetPickFromFolder => 'Pick a video from files';

  @override
  String recHistSheetDurationSeconds(int count) {
    return '$count sec';
  }

  @override
  String get recSelPreparingProgress => 'Preparing...';

  @override
  String get recSelAnalyzingDialogTitle => 'Analyzing Video';

  @override
  String get recSelNoFileSelected => '❌ No file selected';

  @override
  String recSelVideoTooLong(int durationSec) {
    return '❌ Video exceeds 10-minute limit ($durationSec seconds)\nPlease select a video under 600 seconds';
  }

  @override
  String recSelVideoDurationOk(int durationSec) {
    return '✅ Video duration $durationSec seconds, within the 10-minute limit';
  }

  @override
  String get recSelImportFailed =>
      '❌ Import failed\nFile may not exist or format is unsupported';

  @override
  String recSelImportSuccess(String name, String duration) {
    return '✅ Import successful!\n$name\nDuration: $duration';
  }

  @override
  String recSelImportError(String error) {
    return '❌ Import error\n$error';
  }

  @override
  String get recSelImportingVideo => 'Importing video...';

  @override
  String get recSelDoNotClose => 'Do not close the app';

  @override
  String get recSelShotModeTitle => 'Live Swing Mode';

  @override
  String get recSelShotModeSubtitle =>
      'Auto-detects and clips each swing — no long recordings needed';

  @override
  String get recSelNewFeatureBadge => 'New';

  @override
  String get recSelRecordTitle => 'Start Recording';

  @override
  String get recSelRecordSubtitle => 'Record live and analyze your swing';

  @override
  String get recSelLocalVideoTitle => 'Select Local Video';

  @override
  String get recSelLocalVideoSubtitle =>
      'Choose an existing video from your device (max 10 minutes)';

  @override
  String get recSelShareLinkTitle => 'Get from Share Link';

  @override
  String get recSelShareLinkSubtitle =>
      'Enter a 16-digit share code to download the video';

  @override
  String get recSelHeaderTitle => 'Select Recording Mode';

  @override
  String get recSelHeaderSubtitle =>
      'Record live, import a local video, or get one via share code';

  @override
  String get recSelIOSSourceSheetTitle => 'Select Video Source';

  @override
  String get recSelPhotoLibrary => 'Photo Library';

  @override
  String get recSelFilesApp => 'Files App (Folder)';

  @override
  String recTabsTitle(int count) {
    return 'Recording History ($count)';
  }

  @override
  String get recTabsEmpty => 'No recordings';

  @override
  String get recTabsEmptyHint =>
      'Recordings will appear here after you complete a new session';

  @override
  String recTabsMode(String label) {
    return 'Mode: $label';
  }

  @override
  String recTabsDuration(int seconds) {
    return 'Duration: ${seconds}s';
  }

  @override
  String get recordTitle => 'Golf Swing Recording';

  @override
  String get recordOverlayToggle => 'Toggle outline overlay';

  @override
  String get recordSettings => 'Recording settings';

  @override
  String get recordPermissionTitle => 'Camera & Microphone Permission Required';

  @override
  String get recordPermissionMicOnly =>
      'Microphone permission is required to record impact sounds. Please grant access and try again.';

  @override
  String get recordPermissionCameraAndMic =>
      'Camera and microphone permissions are required for swing recording. Please grant access and try again.';

  @override
  String get recordGoToSettings => 'Go to Settings';

  @override
  String get recordGotIt => 'Got it';

  @override
  String get recordLowEndDeviceWarning =>
      'This device does not support real-time skeleton detection during recording. Detection will resume after recording stops.';

  @override
  String get recordFailed =>
      'Recording failed (no valid frames captured). Please try again.';

  @override
  String get recordVideoQuality => 'Video Quality';

  @override
  String get recordFrameRate => 'Frame Rate';

  @override
  String get recordAudio => 'Record Audio';

  @override
  String get recordApply => 'Apply';

  @override
  String get rewardTitle => 'Reward Balls';

  @override
  String get rewardUsageHistoryTooltip => 'Usage History';

  @override
  String rewardEarnedSnackbar(String source, int balls) {
    return 'Earned +$balls balls via \"$source\"!';
  }

  @override
  String rewardUploadSubmittedPending(int pending) {
    return 'Submitted $pending item(s) for review. Balls will be awarded after approval.';
  }

  @override
  String get rewardUploadSubmittedDuplicate =>
      'Data submitted (duplicate data will not be re-reviewed).';

  @override
  String get rewardStatBonusBalls => 'Total Rewards';

  @override
  String get rewardUnitBall => 'balls';

  @override
  String get rewardStatAdToday => 'Ads Today';

  @override
  String get rewardAdDailyUnit => '/ 5 times';

  @override
  String get rewardStatInvites => 'Friends Invited';

  @override
  String get rewardUnitPerson => 'friends';

  @override
  String rewardBallsBadge(int balls) {
    return '+$balls balls';
  }

  @override
  String rewardAdProgress(int used, int cap) {
    return '$used / $cap times';
  }

  @override
  String get rewardDoneToday => 'Completed Today';

  @override
  String get rewardAdNotCompleted =>
      'Ad not fully watched or temporarily unavailable. Please try again later.';

  @override
  String rewardAdFailed(String error) {
    return 'Ad reward failed: $error';
  }

  @override
  String get rewardWatchAdTitle => 'Watch Ad';

  @override
  String rewardWatchAdButton(int balls) {
    return 'Watch Ad +$balls balls';
  }

  @override
  String get rewardInviteFriendTitle => 'Invite Friends';

  @override
  String rewardInviteFriendDesc(int balls) {
    return 'When a friend registers with your invite code, you both get +$balls balls.';
  }

  @override
  String get rewardGetInviteCode => 'Get Invite Code';

  @override
  String get rewardYourInviteCode => 'Your Invite Code';

  @override
  String get rewardInviteCodeCopied => 'Invite code copied';

  @override
  String get rewardInvitedFriends => 'Invited Friends';

  @override
  String get rewardNoInviteHistory => 'No invitations yet';

  @override
  String get rewardShareInviteHint =>
      'Share your invite code and practice together!';

  @override
  String get rewardEnterCodeTitle => 'Enter Invite Code';

  @override
  String rewardEnterCodeDesc(int balls) {
    return 'Enter a friend\'s invite code — you both get +$balls balls.';
  }

  @override
  String get rewardEnterCodeEmpty => 'Please enter an invite code';

  @override
  String get rewardInviteCodeInvalid => 'Invalid invite code';

  @override
  String rewardApplyFailed(String error) {
    return 'Apply failed: $error';
  }

  @override
  String get rewardApplying => 'Applying...';

  @override
  String rewardApplyButton(int balls) {
    return 'Apply +$balls balls';
  }

  @override
  String get rewardEnterFriendCode => 'Enter Friend\'s Invite Code';

  @override
  String get rewardFeedbackTitle => 'Submit Feedback';

  @override
  String get rewardFeedbackTypeBug => '🐛 Bug Report';

  @override
  String get rewardFeedbackTypeFeature => '💡 Feature Request';

  @override
  String get rewardFeedbackTypeOther => '💬 Other';

  @override
  String get rewardFeedbackHint => 'Please describe your feedback in detail...';

  @override
  String get rewardSelectVideo => 'Select Video';

  @override
  String get rewardChangeVideo => 'Change Video';

  @override
  String get rewardUploadImage => 'Upload Image';

  @override
  String get rewardChangeImage => 'Change Image';

  @override
  String get rewardFeedbackEmpty => 'Please enter your feedback';

  @override
  String get rewardFeedbackSubmitted =>
      'Feedback submitted. Thank you for your input!';

  @override
  String rewardSubmitFailed(String error) {
    return 'Submission failed: $error';
  }

  @override
  String get rewardSubmitFeedback => 'Submit Feedback';

  @override
  String rewardSubmitFeedbackWithBalls(int balls) {
    return 'Submit Feedback +$balls balls';
  }

  @override
  String get rewardWriteFeedback => 'Write Feedback';

  @override
  String rewardWriteFeedbackWithBalls(int balls) {
    return 'Write Feedback +$balls balls';
  }

  @override
  String get rewardNoVideoHistory => 'No recorded videos yet';

  @override
  String get rewardLongVideo => 'Long video';

  @override
  String get rewardShortVideo => 'Short video';

  @override
  String get rewardUploadDataTitle => 'Upload Analysis Data';

  @override
  String get rewardNoUploadable => 'No analysis data available to upload';

  @override
  String rewardUploadPartialFail(int count) {
    return '$count item(s) failed to upload and were skipped';
  }

  @override
  String get rewardUploadFailed => 'Upload failed. Please try again later.';

  @override
  String get rewardUploadResubmitBlocked =>
      'Review submission failed: data may have been submitted already (rejected items cannot be resubmitted), or there was a network error — please try again.';

  @override
  String rewardUploadError(String error) {
    return 'Upload failed: $error';
  }

  @override
  String rewardUploadAvailableCount(int available, int uploaded) {
    return '$available item(s) available to upload, $uploaded already uploaded';
  }

  @override
  String rewardUploadAllDone(int count) {
    return 'All analysis data uploaded ($count total)';
  }

  @override
  String rewardUploadReviewStatus(int pending, int approved) {
    return 'Under review: $pending / Approved: $approved';
  }

  @override
  String rewardUploadRejectedSuffix(int count) {
    return ' / Rejected: $count';
  }

  @override
  String get rewardUploadRejectedNote => 'Rejected items cannot be resubmitted';

  @override
  String get rewardSelectUploadVideo => 'Select Recording to Upload';

  @override
  String get rewardSelectUploadSubtitle =>
      'Select one and tap \"Confirm Upload\" to earn rewards';

  @override
  String get rewardNoneSelected => 'None selected';

  @override
  String get rewardOneSelected => '1 selected';

  @override
  String rewardConfirmUpload(int balls) {
    return 'Confirm Upload +$balls balls';
  }

  @override
  String get rewardAnalyzed => 'Analyzed';

  @override
  String rewardDurationSec(int seconds) {
    return '${seconds}s';
  }

  @override
  String get settingsNameSyncFailed => 'Name updated, but server sync failed';

  @override
  String get settingsGoogleCredentialFailed =>
      'Unable to retrieve Google credentials, please try again';

  @override
  String get settingsGoogleLinkFailed =>
      'Google account linking failed, please try again later';

  @override
  String get shareImportTitle => 'Import from Share Link';

  @override
  String get shareImportEnterCodeTitle => 'Enter 16-digit Share Code';

  @override
  String get shareImportEnterCodeDesc =>
      'Once someone shares a video, enter the code to download it to your device';

  @override
  String get shareImportCodeValidator =>
      'Please enter the complete 16-digit share code';

  @override
  String get shareImportLooking => 'Looking up…';

  @override
  String get shareImportLookup => 'Look up';

  @override
  String get shareImportFrom => 'From';

  @override
  String get shareImportSize => 'Size';

  @override
  String get shareImportExpiry => 'Expires';

  @override
  String get shareImportReenter => 'Re-enter Code';

  @override
  String get shareImportDownload => 'Download to Device';

  @override
  String get shareImportPreparing => 'Preparing download…';

  @override
  String get shareImportDownloading => 'Downloading…';

  @override
  String get shareImportExtracting => 'Extracting…';

  @override
  String get shareImportDoneTitle => 'Download Complete!';

  @override
  String get shareImportDoneDesc => 'Video has been added to history';

  @override
  String get shareImportBack => 'Back';

  @override
  String get shareUploadTitle => 'Share Link';

  @override
  String get shareUploadChecking => 'Checking share status…';

  @override
  String get shareUploadCompressing => 'Compressing…';

  @override
  String get shareUploadUnknownError => 'Unknown error';

  @override
  String shareUploadUploading(String percent) {
    return 'Uploading…  $percent%';
  }

  @override
  String get shareUploadCodeReused => 'Existing share code (not yet expired)';

  @override
  String get shareUploadCodeNew => 'Share code (valid for 1 day)';

  @override
  String get shareUploadCopy => 'Copy';

  @override
  String get shareUploadCopied => 'Share code copied';

  @override
  String shareUploadShareText(String code) {
    return 'Golf swing share code: $code\n(Valid for 1 day — enter this code in the app to get the video)';
  }

  @override
  String get shareUploadSystemShare => 'Share';

  @override
  String get shotRecTitle => 'Live Swing Mode';

  @override
  String get shotRecSettings => 'Recording Settings';

  @override
  String shotRecShotsCompleted(int count) {
    return 'Completed $count shots';
  }

  @override
  String get shotRecReady => 'Ready';

  @override
  String get shotRecCalibrating => 'Calibrating… Stay still';

  @override
  String shotRecAddressPrompt(int current, int total) {
    return 'Take address position ($current/$total)';
  }

  @override
  String get shotRecAddressSubText =>
      'Recording starts automatically when stance is confirmed';

  @override
  String get shotRecDetecting => '⚡ Detecting… Swing now';

  @override
  String get shotRecStop => 'Stop';

  @override
  String shotRecSwingDetected(String seconds) {
    return 'Swing detected ✓\nCountdown ${seconds}s';
  }

  @override
  String get shotRecAnalyzing => 'Analyzing…';

  @override
  String get shotRecExtractingAudio => 'Extracting audio…';

  @override
  String get shotRecDetectingImpact => 'Detecting impact…';

  @override
  String get shotRecClipping => 'Clipping…';

  @override
  String get shotRecScoringAudio => 'Scoring audio…';

  @override
  String get shotRecDone => 'Done!';

  @override
  String get shotRecWatch => 'Watch';

  @override
  String shotRecNextShot(int countdown) {
    return 'Next shot ($countdown)';
  }

  @override
  String get shotRecVideoQuality => 'Video Quality';

  @override
  String get shotRecFrameRate => 'Frame Rate';

  @override
  String get shotRecEnableAudio => 'Record Audio';

  @override
  String get shotRecApply => 'Apply';

  @override
  String get shotRecAddressTimeout => 'Address posture not detected, cancelled';

  @override
  String get shotRecNoAnalysisWarning =>
      'This device does not support skeleton detection during recording. Swing detection will still work automatically.';

  @override
  String get shotRecRecordFailed =>
      'Recording failed (no valid video captured), please try again';

  @override
  String get shotRecNoSwingDetected => 'No swing detected, please try again';

  @override
  String get shotRecClipFailed => 'Clipping failed, please try again';

  @override
  String shotRecLiveShotName(int number) {
    return 'Live Shot $number';
  }

  @override
  String get termsPageSubtitle => 'Terms of Service & Privacy Policy';

  @override
  String get termsReadPrompt =>
      'Please read the terms below, then check the box to agree and get started';

  @override
  String get termsScrolledToBottom =>
      'You\'ve reached the end of the terms. Please scroll back to the top to check the agreement box.';

  @override
  String get termsDeclineTitle => 'Confirm Exit';

  @override
  String get termsDeclineContent =>
      'You cannot use ORVIA without agreeing to the Terms of Service. Are you sure you want to exit?';

  @override
  String get termsDeclineBack => 'Go Back';

  @override
  String get termsDeclineExit => 'Exit';

  @override
  String get termsPrivacyOpenFailed =>
      'Unable to open the Privacy Policy page. Please try again later.';

  @override
  String get termsAgreePrefix =>
      'I have read and agree to the Terms of Service and the ';

  @override
  String get termsPrivacyLink => 'Privacy Policy';

  @override
  String get termsAgreeSuffix => '》';

  @override
  String get termsAnalyticsTitle => 'Allow usage analytics (optional)';

  @override
  String get termsAnalyticsDesc =>
      'Helps us improve the app experience. No personally identifiable information is included.';

  @override
  String get termsScrollFirst =>
      'Please scroll through the full terms before checking the agreement box';

  @override
  String get termsDisagree => 'Disagree';

  @override
  String get termsAgreeAndContinue => 'Agree & Continue';

  @override
  String get termsOpenPrivacyFull => 'Open Full Privacy Policy';

  @override
  String get termsSec1Title => '1. Service Description';

  @override
  String get termsSec1Body =>
      'ORVIA (hereinafter \"the Service\") is provided by the ORVIA team to help users record and analyze golf swing motions via mobile devices, and to provide related data statistics and recommendations.\n\nBefore using the Service, please read the following terms carefully. By starting to use the Service, you acknowledge that you have read, understood, and agreed to all content of these terms.';

  @override
  String get termsSec2Title => '2. Account & Security';

  @override
  String get termsSec2Body =>
      '1. You must register via email or a Google account to access full features.\n2. You are responsible for keeping your account credentials secure and for all activities conducted under your account.\n3. If you discover unauthorized use of your account, please notify us immediately.\n4. You may not transfer your account to another person.';

  @override
  String get termsSec3Title => '3. User Conduct';

  @override
  String get termsSec3Body =>
      'By using the Service, you agree to:\n\n1. Only upload video content that you personally filmed or hold legitimate authorization for.\n2. Not upload any illegal, infringing, or inappropriate content.\n3. Not interfere with or disrupt the normal operation of the Service.\n4. Not attempt unauthorized access to the Service\'s systems or data.';

  @override
  String get termsSec4Title => '4. Video & Data Processing';

  @override
  String get termsSec4Body =>
      '1. Videos and analysis data you upload will be stored in the Service\'s cloud system to provide swing analysis.\n2. Share links generated by the sharing feature are valid for 1 day; related files will be automatically deleted after expiry.\n3. You may delete your personal data and recording history from within the app at any time.\n4. We will not provide your personal videos to unauthorized third parties.';

  @override
  String get termsSec5Title => '5. Privacy Policy';

  @override
  String get termsSec5Body =>
      'We value your privacy and collect and use your information according to the following principles:\n\nInformation collected:\n• Account information (email, display name)\n• Swing videos and analysis results\n• Device information and usage records\n\nUsage analytics (with your consent):\n• We may collect anonymous usage data (feature clicks, page views, etc.)\n• Used to improve the app experience and feature design\n• Does not include personally identifiable information; can be turned off in Settings at any time\n\nData protection:\n• All data transmissions use TLS encryption\n• Server-side data is encrypted at rest\n• Regular security audits are conducted\n\nFull privacy policy: https://orvia.atk.tw/privacy.html';

  @override
  String get termsSec6Title => '6. Intellectual Property';

  @override
  String get termsSec6Body =>
      '1. The software, interface design, trademarks, and all related content of the Service are owned by ORVIA and protected by copyright law.\n2. The copyright of videos you upload belongs to you; however, you grant the Service a limited license to use that content to provide analysis services.\n3. Without authorization, you may not reproduce, modify, or distribute any part of the Service.';

  @override
  String get termsSec7Title => '7. Disclaimer';

  @override
  String get termsSec7Body =>
      '1. Swing analysis results provided by the Service are for reference only and do not constitute professional sports coaching advice.\n2. The Service is provided \"as is\" and does not guarantee uninterrupted or error-free operation.\n3. The Service is not liable for any direct or indirect losses arising from the use of the Service.\n4. Swing practice involves physical activity; please practice in a safe environment and assess your own physical condition.';

  @override
  String get termsSec8Title => '8. Service Changes & Termination';

  @override
  String get termsSec8Body =>
      '1. We reserve the right to modify, suspend, or terminate the Service at any time.\n2. If there are significant changes to these terms, we will notify you via the app.\n3. Continued use of the Service constitutes acceptance of the updated terms.';

  @override
  String get termsSec9Title => '9. Contact Us';

  @override
  String get termsSec9Body =>
      'If you have any questions about these terms, please contact us via:\n\nEmail: support@atk.tw\nWebsite: https://orvia.atk.tw\nPrivacy Policy: https://orvia.atk.tw/privacy.html\n\nThese terms were last updated: May 25, 2026';

  @override
  String get testVideoTitle => 'Select Test Video';

  @override
  String testVideoLoadError(String error) {
    return 'Failed to load videos\n$error';
  }

  @override
  String get testVideoEmpty => 'No imported videos yet';

  @override
  String get testVideoSelect => 'Select';

  @override
  String get testVideoHint =>
      '💡 Tip: Select a video as the test recording for demo and analysis testing';

  @override
  String get upgradeSubscribed => 'Subscribed';

  @override
  String get upgradeCurrentPlanActive => 'Current Plan';

  @override
  String get upgradeMonthly => 'Monthly';

  @override
  String get upgradeYearly => 'Yearly (save ~2 months)';

  @override
  String upgradeSubscribeFailed(String error) {
    return 'Subscription failed: $error';
  }

  @override
  String get upgradeProductLoadFailed =>
      'Failed to load product, please try again later';

  @override
  String get upgradeAppStoreSubscribe => 'Subscribe on App Store';

  @override
  String get upgradeGooglePlaySubscribe => 'Subscribe on Google Play';

  @override
  String get upgradeManageSubscriptionIos =>
      'You can manage or cancel your subscription anytime in App Store';

  @override
  String get upgradeManageSubscriptionAndroid =>
      'You can manage or cancel your subscription anytime in Google Play';

  @override
  String get upgradeBuyBalls => 'Buy Balls';

  @override
  String get upgradeNoExpiry => 'No expiry';

  @override
  String upgradeBallCount(int count) {
    return '$count balls';
  }

  @override
  String get upgradeBallPackValidity => 'Never expires, use anytime';

  @override
  String get upgradeBuyButton => 'Buy';

  @override
  String upgradePurchaseFailed(String error) {
    return 'Purchase failed: $error';
  }

  @override
  String upgradeBuyBallCount(int count) {
    return 'Buy $count balls';
  }

  @override
  String get upgradeBallPackDescription =>
      'Balls never expire and have no time limit. Used automatically when your daily quota runs out.';

  @override
  String get upgradeAppStorePurchase => 'Buy on App Store';

  @override
  String get upgradeGooglePlayPurchase => 'Buy on Google Play';

  @override
  String get usageTitle => 'Usage History';

  @override
  String get usageSubtitle => 'AI Analysis & Ball Ledger';

  @override
  String get usageTabAnalysis => 'AI Analysis';

  @override
  String get usageTabBalls => 'Ball Ledger';

  @override
  String get usageLoadFailed => 'Failed to load. Pull down to retry.';

  @override
  String usageLoadError(String error) {
    return 'Load error: $error';
  }

  @override
  String get usageEmptyAnalysis => 'No analysis records yet';

  @override
  String get usageAllLoaded => 'All records loaded';

  @override
  String get usageSummaryTotalAnalysis => 'Total Analyses';

  @override
  String get usageUnitTimes => 'times';

  @override
  String get usageSummaryTodayUsed => 'Used Today';

  @override
  String get usageAnalysisItemTitle => 'AI Swing Analysis';

  @override
  String get usageSourceDailyQuota => 'Daily Quota';

  @override
  String get usageSourceBonusBall => 'Bonus Ball';

  @override
  String get usageSourceDailyQuotaDesc => 'Used daily quota';

  @override
  String get usageSourceBonusBallDesc => 'Consumed 1 ball';

  @override
  String get usageEmptyBalls => 'No ball records yet';

  @override
  String get usageSummaryTotalRecords => 'Total Records';

  @override
  String get usageUnitRecords => 'records';

  @override
  String get usageSummaryCurrentBalls => 'Current Balls';

  @override
  String get usageUnitBalls => 'balls';

  @override
  String usageBallBalance(int balance) {
    return 'Balance: $balance balls';
  }

  @override
  String get usageDateToday => 'Today';

  @override
  String get usageDateYesterday => 'Yesterday';

  @override
  String waveformCrispScore(int score) {
    return 'Crispness $score';
  }

  @override
  String waveformPeakLabel(String level) {
    return 'Peak $level';
  }

  @override
  String get extImportProgressCopying => 'Copying video...';

  @override
  String get extImportProgressTranscoding => 'Preparing transcode...';

  @override
  String get extImportProgressDurationInvalid =>
      'Video duration invalid (must be 1–600 seconds)';

  @override
  String get extImportProgressThumbnail => 'Generating thumbnail...';

  @override
  String get extImportProgressDone => 'Import complete ✅';

  @override
  String get learnHubGoodSwingTitle => 'Good Swing Demo';

  @override
  String get learnHubGoodSwingDesc =>
      'Smooth tempo, stable weight shift, complete follow-through after impact.';

  @override
  String get learnHubEarlyReleaseTitle => 'Common Error: Early Release';

  @override
  String get learnHubEarlyReleaseDesc =>
      'Wrists release too early, resulting in insufficient clubhead acceleration and a weak or right-curving shot.';

  @override
  String get learnHubMarkerBackswingTop => 'Top of Backswing';

  @override
  String get learnHubMarkerBackswingTopNote =>
      'Weight still centered over feet, shaft and arms form a straight line.';

  @override
  String get learnHubMarkerImpact => 'Impact';

  @override
  String get learnHubMarkerImpactNote =>
      'Hands ahead of the ball, body rotation drives the impact.';

  @override
  String get learnHubMarkerFinish => 'Follow-Through';

  @override
  String get learnHubMarkerFinishNote =>
      'Weight transferred to lead foot, body maintains balance.';

  @override
  String get learnHubMarkerEarlyReleaseTopNote =>
      'Wrist angle releases too early, clubhead lags behind.';

  @override
  String get learnHubMarkerPreImpact => 'Pre-Impact';

  @override
  String get learnHubMarkerPreImpactNote =>
      'Insufficient hand lead, weight biased to trail side.';

  @override
  String get learnHubMarkerEarlyReleaseFinishNote =>
      'Weight not transferred to lead foot, poor balance.';

  @override
  String get playerTimelineAbbrAddress => 'Adr';

  @override
  String get playerTimelineAbbrTakeaway => 'Tkw';

  @override
  String get playerTimelineAbbrBackswing => 'Bk';

  @override
  String get playerTimelineAbbrTop => 'Top';

  @override
  String get playerTimelineAbbrDownswing => 'Dwn';

  @override
  String get playerTimelineAbbrImpact => 'Imp';

  @override
  String get playerTimelineAbbrFollowthrough => 'Fol';

  @override
  String get playerTimelineAbbrFinish => 'Fin';

  @override
  String get recHistSheetTitle => 'Recording History';

  @override
  String get recTabsToday => 'Today';

  @override
  String get recTabsYesterday => 'Yesterday';

  @override
  String recTabsDateMonthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get recWidgetsZoomWide => 'Wide';

  @override
  String get recWidgetsSavingVideo => 'Saving video…';

  @override
  String get rewardFriendFallbackName => 'Friend';

  @override
  String get upgradeHighlightFullFeatured =>
      'Full recording & analysis features';

  @override
  String get upgradeHighlightAiDaily10 => 'AI coach analysis 10 times per day';

  @override
  String get upgradeHighlightBuyMore => 'Top up balls when quota runs out';

  @override
  String get upgradeHighlightAiDaily90 => 'AI coach analysis 90 times per day';

  @override
  String get upgradeHighlightAiUnlimited => 'Unlimited AI coach analysis';

  @override
  String get upgradeFeatureAutoClip => 'Auto clip long videos';

  @override
  String get upgradeFeatureVoiceHint => 'Real-time voice prompts';

  @override
  String get upgradeFeatureAudioScore => 'Audio analysis (impact scoring)';

  @override
  String get upgradeFeatureDualVideo => 'Dual video comparison';

  @override
  String get upgradeFeatureAiCoachAnalysis => 'AI coach analysis';

  @override
  String get upgradeQuotaDaily10 => '10/day';

  @override
  String get upgradeQuotaDaily90 => '90/day';

  @override
  String get upgradeQuotaUnlimited => 'Unlimited';

  @override
  String get upgradeBadgePopular => 'Popular';

  @override
  String get upgradeBadgeValue => 'Good Value';

  @override
  String get upgradeBadgeBestDeal => 'Best Deal';

  @override
  String get upgradePerYear => '/year';

  @override
  String get usageReasonAd => 'Watch Ad Reward';

  @override
  String get usageReasonFeedback => 'Feedback Reward';

  @override
  String get usageReasonInvite => 'Invite Friend Reward';

  @override
  String get usageReasonUpload => 'Upload Data Reward';

  @override
  String get usageReasonAnalysis => 'AI Analysis Cost';

  @override
  String get usageReasonManual => 'Manual Adjustment';

  @override
  String get usageReasonOther => 'Other';

  @override
  String get waveformPeakHigh => 'High';

  @override
  String get waveformPeakMid => 'Mid';

  @override
  String get waveformPeakLow => 'Low';

  @override
  String get waveformFreqCrispy => 'Crispy';

  @override
  String get waveformFreqMid => 'Mid tone';

  @override
  String get waveformFreqMuffled => 'Muffled';

  @override
  String get historyProgressV2AudioScan => 'V2 audio scanning...';

  @override
  String get historyProgressV3AudioScan => 'V3 audio scanning...';

  @override
  String get historyProgressWaitingConfirm =>
      'Waiting for clip confirmation...';

  @override
  String get historyProgressClipping => 'Trimming clips...';

  @override
  String historyProgressClippingPct(int pct, int cur, int total) {
    return 'Trimming clips... $pct% ($cur/$total)';
  }

  @override
  String historyProgressV3SkeletonAnalysis(int cur, int total) {
    return 'V3 skeleton analysis $cur/$total';
  }

  @override
  String historyProgressV3SkeletonItem(int cur, int total) {
    return 'Item $cur/$total';
  }

  @override
  String get historyProgressDetectingHit => 'Detecting impact...';

  @override
  String get historyProgressVideoAnalysis => 'Analyzing video...';

  @override
  String get historyProgressDetectingPhase => 'Detecting swing phases...';

  @override
  String get historyProgressAudioAnalysis => 'Analyzing audio...';

  @override
  String get historyDlLabelFull => 'Full Analysis';

  @override
  String get historyDlDescFull => 'Skeleton + ball trajectory overlay';

  @override
  String get historyDlLabelSkeleton => 'Skeleton Version';

  @override
  String get historyDlDescSkeleton => 'Skeleton overlay only';

  @override
  String get historyDlLabelClip => 'Original Clip';

  @override
  String get historyDlDescClip => 'Original clip without overlay';

  @override
  String get historyDlLabelRaw => 'Original Video';

  @override
  String get historyDlDescRaw => 'No overlay';

  @override
  String get historyDlLabelRawMov => 'Original Video (MOV)';

  @override
  String get historyDlDescRawMov => 'Original MOV file';

  @override
  String historyCandidateDuration(int seconds) {
    return '$seconds sec';
  }

  @override
  String recDetailPointCount(int count) {
    return '$count pts';
  }
}
