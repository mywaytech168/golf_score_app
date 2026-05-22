import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'TekSwing'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart Swing Training Platform'**
  String get appTagline;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get commonOpenSettings;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonUnknownError.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred, please try again later'**
  String get commonUnknownError;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back!'**
  String get authWelcomeBack;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login to TekSwing to sync swing data and explore the latest analysis reports.'**
  String get authLoginSubtitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill in the details below to start using TekSwing.'**
  String get authRegisterSubtitle;

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get authLoginTitle;

  /// No description provided for @authUsernameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Username / Email'**
  String get authUsernameOrEmail;

  /// No description provided for @authUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'username or you@example.com'**
  String get authUsernameHint;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authUsernameHintReg.
  ///
  /// In en, this message translates to:
  /// **'Used for login, must be unique'**
  String get authUsernameHintReg;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name (Optional)'**
  String get authDisplayName;

  /// No description provided for @authDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Same as username if left empty'**
  String get authDisplayNameHint;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password (at least 6 characters)'**
  String get authPasswordLabel;

  /// No description provided for @authConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get authConfirmPassword;

  /// No description provided for @authRememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember Me'**
  String get authRememberMe;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get authForgotPassword;

  /// No description provided for @authLoginButton.
  ///
  /// In en, this message translates to:
  /// **'Login to TekSwing'**
  String get authLoginButton;

  /// No description provided for @authRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterButton;

  /// No description provided for @authSocialDivider.
  ///
  /// In en, this message translates to:
  /// **'Or sign in with social account'**
  String get authSocialDivider;

  /// No description provided for @authLoginWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authLoginWithGoogle;

  /// No description provided for @authGoogleSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in with Google...'**
  String get authGoogleSigningIn;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Register now'**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Back to Login'**
  String get authHaveAccount;

  /// No description provided for @validationEnterUsernameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your username or email'**
  String get validationEnterUsernameOrEmail;

  /// No description provided for @validationEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get validationEnterPassword;

  /// No description provided for @validationEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get validationEnterEmail;

  /// No description provided for @validationInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get validationInvalidEmail;

  /// No description provided for @validationEnterUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get validationEnterUsername;

  /// No description provided for @validationUsernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get validationUsernameTooShort;

  /// No description provided for @validationPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get validationPasswordTooShort;

  /// No description provided for @validationPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get validationPasswordMismatch;

  /// No description provided for @validationEnterPasswordAgain.
  ///
  /// In en, this message translates to:
  /// **'Please re-enter your password'**
  String get validationEnterPasswordAgain;

  /// No description provided for @msgLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Login successful, welcome back!'**
  String get msgLoginSuccess;

  /// No description provided for @msgLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed, please check your credentials'**
  String get msgLoginFailed;

  /// No description provided for @msgLoginFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {error}'**
  String msgLoginFailedWithError(String error);

  /// No description provided for @msgRegisterSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful, please login'**
  String get msgRegisterSuccess;

  /// No description provided for @msgRegisterFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get msgRegisterFailed;

  /// No description provided for @msgRegisterFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Registration failed: {error}'**
  String msgRegisterFailedWithError(String error);

  /// No description provided for @msgGoogleLoginCancelled.
  ///
  /// In en, this message translates to:
  /// **'Google login cancelled'**
  String get msgGoogleLoginCancelled;

  /// No description provided for @msgGoogleLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Google login successful, welcome back!'**
  String get msgGoogleLoginSuccess;

  /// No description provided for @msgGoogleLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Google login failed: {error}'**
  String msgGoogleLoginFailed(String error);

  /// No description provided for @msgGoogleLoginNoToken.
  ///
  /// In en, this message translates to:
  /// **'Google login failed: server did not return an auth token'**
  String get msgGoogleLoginNoToken;

  /// No description provided for @permTitle.
  ///
  /// In en, this message translates to:
  /// **'Please Allow Bluetooth & Location'**
  String get permTitle;

  /// No description provided for @permSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission is required on first login.'**
  String get permSubtitle;

  /// No description provided for @permGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get permGranted;

  /// No description provided for @permDenied.
  ///
  /// In en, this message translates to:
  /// **'Not Allowed'**
  String get permDenied;

  /// No description provided for @permLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permLocation;

  /// No description provided for @permCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check Permissions Again'**
  String get permCheckAgain;

  /// No description provided for @permStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Status'**
  String get permStatusTitle;

  /// No description provided for @permNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Permissions not yet checked'**
  String get permNotChecked;

  /// No description provided for @permDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Required'**
  String get permDialogTitle;

  /// No description provided for @permGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get permGoToSettings;

  /// No description provided for @permIKnow.
  ///
  /// In en, this message translates to:
  /// **'Got It'**
  String get permIKnow;

  /// No description provided for @permBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Please allow Bluetooth permission.'**
  String get permBluetooth;

  /// No description provided for @permIosInstructions.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required for Bluetooth scanning:\n\n1. Tap \"Open Settings\"\n2. Find \"Golf Score App\"\n3. Tap \"Location\" → \"While Using the App\"\n4. Return to the app and login again'**
  String get permIosInstructions;

  /// No description provided for @permAndroidInstructions.
  ///
  /// In en, this message translates to:
  /// **'Please allow the following permissions in system settings:\n1. Go to \"Apps & Notifications\"\n2. Select TekSwing → Permissions\n3. Enable \"Nearby Devices, Bluetooth\" and \"Location\"'**
  String get permAndroidInstructions;

  /// No description provided for @permStatusGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get permStatusGranted;

  /// No description provided for @permStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get permStatusDenied;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get navData;

  /// No description provided for @navRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get navRecord;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get navPremium;

  /// No description provided for @homeLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get homeLogout;

  /// No description provided for @homeConfirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Confirm Logout'**
  String get homeConfirmLogout;

  /// No description provided for @homeConfirmLogoutMsg.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get homeConfirmLogoutMsg;

  /// No description provided for @homeConfirmLogoutBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm Logout'**
  String get homeConfirmLogoutBtn;

  /// No description provided for @homeTodayUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Today: Unlimited 🏆'**
  String get homeTodayUnlimited;

  /// No description provided for @homeTodayUsage.
  ///
  /// In en, this message translates to:
  /// **'Today: {used} / {total} balls'**
  String homeTodayUsage(int used, int total);

  /// No description provided for @homeTodayUsageBonus.
  ///
  /// In en, this message translates to:
  /// **'Today: {used} / {total} balls (incl. +{bonus} bonus)'**
  String homeTodayUsageBonus(int used, int total, int bonus);

  /// No description provided for @homeTodayLimit.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Limit reached'**
  String get homeTodayLimit;

  /// No description provided for @homeProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get homeProfile;

  /// No description provided for @homeRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get homeRewards;

  /// No description provided for @homeGoodShot.
  ///
  /// In en, this message translates to:
  /// **'Good Shot'**
  String get homeGoodShot;

  /// No description provided for @homeBadShot.
  ///
  /// In en, this message translates to:
  /// **'Bad Shot'**
  String get homeBadShot;

  /// No description provided for @homeTotalShots.
  ///
  /// In en, this message translates to:
  /// **'Total Shots'**
  String get homeTotalShots;

  /// No description provided for @homeAvgScore.
  ///
  /// In en, this message translates to:
  /// **'Avg Score'**
  String get homeAvgScore;

  /// No description provided for @homeNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet today'**
  String get homeNoDataYet;

  /// No description provided for @homeStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get homeStartRecording;

  /// No description provided for @recTitle.
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get recTitle;

  /// No description provided for @recStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get recStartRecording;

  /// No description provided for @recSelectLocalVideo.
  ///
  /// In en, this message translates to:
  /// **'Select Local Video'**
  String get recSelectLocalVideo;

  /// No description provided for @recImportFromShare.
  ///
  /// In en, this message translates to:
  /// **'Import from Share Link'**
  String get recImportFromShare;

  /// No description provided for @recImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get recImporting;

  /// No description provided for @recSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get recSelected;

  /// No description provided for @recSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import Successful'**
  String get recSuccess;

  /// No description provided for @recFailed.
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get recFailed;

  /// No description provided for @recCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get recCancelled;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get historyEmpty;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this recording?'**
  String get historyDeleteConfirm;

  /// No description provided for @historyDeleteConfirmMsg.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get historyDeleteConfirmMsg;

  /// No description provided for @upgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Plan'**
  String get upgradeTitle;

  /// No description provided for @upgradeFreeForever.
  ///
  /// In en, this message translates to:
  /// **'Free Forever'**
  String get upgradeFreeForever;

  /// No description provided for @upgradePerMonth.
  ///
  /// In en, this message translates to:
  /// **'/month'**
  String get upgradePerMonth;

  /// No description provided for @upgradeRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get upgradeRecommended;

  /// No description provided for @upgradeCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current Plan'**
  String get upgradeCurrentPlan;

  /// No description provided for @upgradeSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe Now'**
  String get upgradeSubscribe;

  /// No description provided for @upgradeFeatureSwingRecording.
  ///
  /// In en, this message translates to:
  /// **'Swing Recording'**
  String get upgradeFeatureSwingRecording;

  /// No description provided for @upgradeFeatureVideoAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Video Clip Analysis'**
  String get upgradeFeatureVideoAnalysis;

  /// No description provided for @upgradeFeatureVoice.
  ///
  /// In en, this message translates to:
  /// **'Real-time Voice'**
  String get upgradeFeatureVoice;

  /// No description provided for @upgradeFeatureBallTrack.
  ///
  /// In en, this message translates to:
  /// **'Ball Trajectory'**
  String get upgradeFeatureBallTrack;

  /// No description provided for @upgradeFeatureOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay Analysis'**
  String get upgradeFeatureOverlay;

  /// No description provided for @upgradeFeatureClubTrack.
  ///
  /// In en, this message translates to:
  /// **'Club Head Tracking'**
  String get upgradeFeatureClubTrack;

  /// No description provided for @upgradeFeaturePose.
  ///
  /// In en, this message translates to:
  /// **'Pose Skeleton Analysis'**
  String get upgradeFeaturePose;

  /// No description provided for @upgradeFeatureRhythm.
  ///
  /// In en, this message translates to:
  /// **'Rhythm / Speed Analysis'**
  String get upgradeFeatureRhythm;

  /// No description provided for @upgradeFeatureScore.
  ///
  /// In en, this message translates to:
  /// **'Swing Score'**
  String get upgradeFeatureScore;

  /// No description provided for @upgradeFeatureAiCoach.
  ///
  /// In en, this message translates to:
  /// **'AI Posture Advice'**
  String get upgradeFeatureAiCoach;

  /// No description provided for @upgradeFeatureTraining.
  ///
  /// In en, this message translates to:
  /// **'Training Suggestions'**
  String get upgradeFeatureTraining;

  /// No description provided for @upgradeFeatureCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction Tracking'**
  String get upgradeFeatureCorrection;

  /// No description provided for @upgradeFeatureReport.
  ///
  /// In en, this message translates to:
  /// **'Daily / Monthly Reports'**
  String get upgradeFeatureReport;

  /// No description provided for @upgradeFeatureCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare with Others'**
  String get upgradeFeatureCompare;

  /// No description provided for @upgradeFeatureAds.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get upgradeFeatureAds;

  /// No description provided for @upgradeUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get upgradeUnlimited;

  /// No description provided for @upgradeHighQuality.
  ///
  /// In en, this message translates to:
  /// **'High Quality'**
  String get upgradeHighQuality;

  /// No description provided for @upgradeHistoryCompare.
  ///
  /// In en, this message translates to:
  /// **'History Compare'**
  String get upgradeHistoryCompare;

  /// No description provided for @upgradeNoAds.
  ///
  /// In en, this message translates to:
  /// **'Ad-free'**
  String get upgradeNoAds;

  /// No description provided for @upgradeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get upgradeAdvanced;

  /// No description provided for @todayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayTitle;

  /// No description provided for @todaySwingCount.
  ///
  /// In en, this message translates to:
  /// **'Swing Count'**
  String get todaySwingCount;

  /// No description provided for @todayGoodRate.
  ///
  /// In en, this message translates to:
  /// **'Good Rate'**
  String get todayGoodRate;

  /// No description provided for @todayAvgSpeed.
  ///
  /// In en, this message translates to:
  /// **'Avg Speed'**
  String get todayAvgSpeed;

  /// No description provided for @aiCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Coach Analysis'**
  String get aiCoachTitle;

  /// No description provided for @aiCoachAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing... usually 10–30 seconds'**
  String get aiCoachAnalyzing;

  /// No description provided for @aiCoachNoData.
  ///
  /// In en, this message translates to:
  /// **'No analysis data'**
  String get aiCoachNoData;

  /// No description provided for @aiCoachBasis.
  ///
  /// In en, this message translates to:
  /// **'Basis'**
  String get aiCoachBasis;

  /// No description provided for @aiCoachSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get aiCoachSuggestion;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileTitle;

  /// No description provided for @profileAvatar.
  ///
  /// In en, this message translates to:
  /// **'Set an avatar so coaches can identify you more easily'**
  String get profileAvatar;

  /// No description provided for @profileRemoveAvatar.
  ///
  /// In en, this message translates to:
  /// **'Remove Avatar'**
  String get profileRemoveAvatar;

  /// No description provided for @profilePersonalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get profilePersonalInfo;

  /// No description provided for @profileDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get profileDisplayName;

  /// No description provided for @profileSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get profileSaveChanges;

  /// No description provided for @langTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get langTitle;

  /// No description provided for @langZhTW.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get langZhTW;

  /// No description provided for @langZhCN.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get langZhCN;

  /// No description provided for @langEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEn;

  /// No description provided for @langSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get langSelectTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
