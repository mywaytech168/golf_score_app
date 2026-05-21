// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'TekSwing';

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
      'Login to TekSwing to sync swing data and explore the latest analysis reports.';

  @override
  String get authRegisterTitle => 'Create Account';

  @override
  String get authRegisterSubtitle =>
      'Fill in the details below to start using TekSwing.';

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
  String get authLoginButton => 'Login to TekSwing';

  @override
  String get authRegisterButton => 'Create Account';

  @override
  String get authSocialDivider => 'Or sign in with social account';

  @override
  String get authLoginWithGoogle => 'Continue with Google';

  @override
  String get authGoogleSigningIn => 'Signing in with Google...';

  @override
  String get authNoAccount => 'Don\'t have an account? Register now';

  @override
  String get authHaveAccount => 'Already have an account? Back to Login';

  @override
  String get authEncryptionNote => 'All data protected with 256-bit encryption';

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
      'Password must be at least 6 characters';

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
      'Please allow the following permissions in system settings:\n1. Go to \"Apps & Notifications\"\n2. Select TekSwing → Permissions\n3. Enable \"Nearby Devices, Bluetooth\" and \"Location\"';

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
}
