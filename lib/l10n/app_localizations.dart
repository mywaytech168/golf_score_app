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
  /// **'ORVIA'**
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
  /// **'Login to ORVIA to sync swing data and explore the latest analysis reports.'**
  String get authLoginSubtitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill in the details below to start using ORVIA.'**
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
  /// **'Login to ORVIA'**
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

  /// No description provided for @authLoginWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authLoginWithApple;

  /// No description provided for @authAppleSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in with Apple...'**
  String get authAppleSigningIn;

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
  /// **'Password must be 8+ characters with uppercase, lowercase and a digit'**
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

  /// No description provided for @msgAppleLoginCancelled.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in cancelled'**
  String get msgAppleLoginCancelled;

  /// No description provided for @msgAppleLoginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in successful, welcome back!'**
  String get msgAppleLoginSuccess;

  /// No description provided for @msgAppleLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in failed: {error}'**
  String msgAppleLoginFailed(Object error);

  /// No description provided for @msgAppleLoginNoToken.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in failed: server did not return an auth token'**
  String get msgAppleLoginNoToken;

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
  /// **'Please allow the following permissions in system settings:\n1. Go to \"Apps & Notifications\"\n2. Select ORVIA → Permissions\n3. Enable \"Nearby Devices, Bluetooth\" and \"Location\"'**
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
  /// **'Subscription'**
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

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// No description provided for @settingsChangeName.
  ///
  /// In en, this message translates to:
  /// **'Change Name'**
  String get settingsChangeName;

  /// No description provided for @settingsChangeNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter display name'**
  String get settingsChangeNameHint;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get settingsChangePassword;

  /// No description provided for @settingsCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get settingsCurrentPassword;

  /// No description provided for @settingsNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get settingsNewPassword;

  /// No description provided for @settingsConfirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get settingsConfirmNewPassword;

  /// No description provided for @settingsCurrentPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter current password'**
  String get settingsCurrentPasswordRequired;

  /// No description provided for @settingsConfirmChange.
  ///
  /// In en, this message translates to:
  /// **'Confirm Change'**
  String get settingsConfirmChange;

  /// No description provided for @settingsPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get settingsPasswordChanged;

  /// No description provided for @settingsSetPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get settingsSetPassword;

  /// No description provided for @settingsSetPasswordDesc.
  ///
  /// In en, this message translates to:
  /// **'Set a password to also sign in with email'**
  String get settingsSetPasswordDesc;

  /// No description provided for @settingsPasswordSet.
  ///
  /// In en, this message translates to:
  /// **'Password set'**
  String get settingsPasswordSet;

  /// No description provided for @settingsGoogleLogin.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In'**
  String get settingsGoogleLogin;

  /// No description provided for @settingsGoogleLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get settingsGoogleLinked;

  /// No description provided for @settingsGoogleNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked. Tap to link Google account'**
  String get settingsGoogleNotLinked;

  /// No description provided for @settingsAppleLogin.
  ///
  /// In en, this message translates to:
  /// **'Apple Sign-In'**
  String get settingsAppleLogin;

  /// No description provided for @settingsAppleLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get settingsAppleLinked;

  /// No description provided for @settingsAppleNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked. Tap to link Apple account'**
  String get settingsAppleNotLinked;

  /// No description provided for @settingsAppleCredentialFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to retrieve Apple credentials, please try again'**
  String get settingsAppleCredentialFailed;

  /// No description provided for @settingsAppleLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple account linking failed, please try again later'**
  String get settingsAppleLinkFailed;

  /// No description provided for @settingsSectionAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis Preferences'**
  String get settingsSectionAnalysis;

  /// No description provided for @settingsAnalysisQuality.
  ///
  /// In en, this message translates to:
  /// **'Analysis Output Quality'**
  String get settingsAnalysisQuality;

  /// No description provided for @settingsQualityHint.
  ///
  /// In en, this message translates to:
  /// **'Saved as default for future analyses'**
  String get settingsQualityHint;

  /// No description provided for @settingsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get settingsApply;

  /// No description provided for @settingsQualityUpdated.
  ///
  /// In en, this message translates to:
  /// **'Output quality updated to \"{quality}\"'**
  String settingsQualityUpdated(String quality);

  /// No description provided for @settingsSectionSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get settingsSectionSubscription;

  /// No description provided for @settingsViewSubscription.
  ///
  /// In en, this message translates to:
  /// **'View Subscription Plans'**
  String get settingsViewSubscription;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get settingsCheckUpdate;

  /// No description provided for @settingsAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Usage Analytics'**
  String get settingsAnalytics;

  /// No description provided for @settingsAnalyticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Anonymous usage statistics to help improve the app'**
  String get settingsAnalyticsDesc;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get settingsTermsOfService;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsPrivacyOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the privacy policy page, please try again later'**
  String get settingsPrivacyOpenFailed;

  /// No description provided for @settingsVersionCopied.
  ///
  /// In en, this message translates to:
  /// **'Version copied'**
  String get settingsVersionCopied;

  /// No description provided for @settingsAlreadyLatest.
  ///
  /// In en, this message translates to:
  /// **'Already on latest version v{version}'**
  String settingsAlreadyLatest(String version);

  /// No description provided for @settingsUpdateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed, please try again later'**
  String get settingsUpdateCheckFailed;

  /// No description provided for @settingsConfirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Confirm Logout?'**
  String get settingsConfirmLogout;

  /// No description provided for @settingsLogoutWarning.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to sign in again to use cloud features.'**
  String get settingsLogoutWarning;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account permanently removes your profile, subscription and analysis history. This cannot be undone. It does not automatically refund any purchase — please cancel subscriptions separately in the App Store / Google Play. Continue?'**
  String get settingsDeleteAccountWarning;

  /// No description provided for @settingsDeleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Final Confirmation'**
  String get settingsDeleteAccountConfirmTitle;

  /// No description provided for @settingsDeleteAccountConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Type \"DELETE\" to confirm permanent account deletion.'**
  String get settingsDeleteAccountConfirmHint;

  /// No description provided for @settingsDeleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account. Please try again later or contact support.'**
  String get settingsDeleteAccountFailed;

  /// No description provided for @settingsNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get settingsNameUpdated;

  /// No description provided for @settingsPickFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get settingsPickFromGallery;

  /// No description provided for @settingsRemoveAvatar.
  ///
  /// In en, this message translates to:
  /// **'Remove Avatar'**
  String get settingsRemoveAvatar;

  /// No description provided for @homeTodayOverview.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Overview'**
  String get homeTodayOverview;

  /// No description provided for @homeHi.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name} 👋'**
  String homeHi(String name);

  /// No description provided for @homeRounds.
  ///
  /// In en, this message translates to:
  /// **'Rounds'**
  String get homeRounds;

  /// No description provided for @homePractices.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get homePractices;

  /// No description provided for @homeTodayGoodRate.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Good Rate'**
  String get homeTodayGoodRate;

  /// No description provided for @homeGoodTimes.
  ///
  /// In en, this message translates to:
  /// **'Good {count}'**
  String homeGoodTimes(int count);

  /// No description provided for @homeBadTimes.
  ///
  /// In en, this message translates to:
  /// **'Bad {count}'**
  String homeBadTimes(int count);

  /// No description provided for @homeTodayPosture.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Posture'**
  String get homeTodayPosture;

  /// No description provided for @homeTopSpeed.
  ///
  /// In en, this message translates to:
  /// **'Peak Speed'**
  String get homeTopSpeed;

  /// No description provided for @homeSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot'**
  String get homeSweetSpot;

  /// No description provided for @homeCrispness.
  ///
  /// In en, this message translates to:
  /// **'Crispness'**
  String get homeCrispness;

  /// No description provided for @homeAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get homeAnnouncements;

  /// No description provided for @homeRewardBalls.
  ///
  /// In en, this message translates to:
  /// **'Reward Balls'**
  String get homeRewardBalls;

  /// No description provided for @homeGreetingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Ready to start today\'s swing goals?'**
  String get homeGreetingQuestion;

  /// No description provided for @homeTodayQuota.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Usage'**
  String get homeTodayQuota;

  /// No description provided for @homeQuotaBalls.
  ///
  /// In en, this message translates to:
  /// **'{used} / {total} balls'**
  String homeQuotaBalls(int used, int total);

  /// No description provided for @homeBallsUnit.
  ///
  /// In en, this message translates to:
  /// **'{balls} balls'**
  String homeBallsUnit(int balls);

  /// No description provided for @homeHitAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Shot Analysis'**
  String get homeHitAnalysis;

  /// No description provided for @homeHitRecordsLabel.
  ///
  /// In en, this message translates to:
  /// **'shots recorded'**
  String get homeHitRecordsLabel;

  /// No description provided for @homeImprovedVsAvg.
  ///
  /// In en, this message translates to:
  /// **'Keep it up! Today is {pct}% above your average.'**
  String homeImprovedVsAvg(String pct);

  /// No description provided for @homeTrainingFocus.
  ///
  /// In en, this message translates to:
  /// **'Training Focus'**
  String get homeTrainingFocus;

  /// No description provided for @homeViewNow.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get homeViewNow;

  /// No description provided for @homeNoShotsToday.
  ///
  /// In en, this message translates to:
  /// **'No shots recorded today — go record a swing!'**
  String get homeNoShotsToday;

  /// No description provided for @homeEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Record your first swing to start building your stats'**
  String get homeEmptyHint;

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @todayTitleToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Summary'**
  String get todayTitleToday;

  /// No description provided for @todayTitleHistory.
  ///
  /// In en, this message translates to:
  /// **'History Summary'**
  String get todayTitleHistory;

  /// No description provided for @todayLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load, pull down to refresh'**
  String get todayLoadFailed;

  /// No description provided for @todaySweetSpotHit.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot Hit'**
  String get todaySweetSpotHit;

  /// No description provided for @todayCrispness.
  ///
  /// In en, this message translates to:
  /// **'Sound Crispness'**
  String get todayCrispness;

  /// No description provided for @todayTopSpeed.
  ///
  /// In en, this message translates to:
  /// **'Peak Speed'**
  String get todayTopSpeed;

  /// No description provided for @todayNoRecord.
  ///
  /// In en, this message translates to:
  /// **'No practice records today'**
  String get todayNoRecord;

  /// No description provided for @todayNoRecordDate.
  ///
  /// In en, this message translates to:
  /// **'No practice records on this day'**
  String get todayNoRecordDate;

  /// No description provided for @todayGoRecord.
  ///
  /// In en, this message translates to:
  /// **'Go record a swing!'**
  String get todayGoRecord;

  /// No description provided for @todayPostureToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Posture Analysis'**
  String get todayPostureToday;

  /// No description provided for @todayPosture.
  ///
  /// In en, this message translates to:
  /// **'Posture Analysis'**
  String get todayPosture;

  /// No description provided for @annBoardTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get annBoardTitle;

  /// No description provided for @annUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String annUnreadCount(int count);

  /// No description provided for @annAllAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'All Announcements'**
  String get annAllAnnouncements;

  /// No description provided for @annMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark All Read'**
  String get annMarkAllRead;

  /// No description provided for @annRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get annRefresh;

  /// No description provided for @annLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load, pull down to retry'**
  String get annLoadFailed;

  /// No description provided for @annMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String annMinutesAgo(int count);

  /// No description provided for @annHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String annHoursAgo(int count);

  /// No description provided for @annDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String annDaysAgo(int count);

  /// No description provided for @annDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcement Detail'**
  String get annDetailTitle;

  /// No description provided for @annExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String annExpiresAt(String date);

  /// No description provided for @annEmpty.
  ///
  /// In en, this message translates to:
  /// **'No announcements'**
  String get annEmpty;

  /// No description provided for @annEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'New announcements will appear here'**
  String get annEmptySubtitle;

  /// No description provided for @updateNotes.
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get updateNotes;

  /// No description provided for @updateForcedWarning.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Please update to continue.'**
  String get updateForcedWarning;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @updateRemindLater.
  ///
  /// In en, this message translates to:
  /// **'Remind Me Later'**
  String get updateRemindLater;

  /// No description provided for @updateDontRemind.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Remind'**
  String get updateDontRemind;

  /// No description provided for @updateCannotOpenStore.
  ///
  /// In en, this message translates to:
  /// **'Cannot open store. Please update manually.'**
  String get updateCannotOpenStore;

  /// No description provided for @updateDownloadedReady.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded. Restart to apply.'**
  String get updateDownloadedReady;

  /// No description provided for @updateRestartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get updateRestartNow;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Required Update'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please update to continue using ORVIA'**
  String get updateRequiredSubtitle;

  /// No description provided for @updateFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'New Version Available'**
  String get updateFoundTitle;

  /// No description provided for @updateFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update recommended for the best experience'**
  String get updateFoundSubtitle;

  /// No description provided for @updateCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current Version'**
  String get updateCurrentVersion;

  /// No description provided for @updateLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest Version'**
  String get updateLatestVersion;

  /// No description provided for @upgradePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Your Plan'**
  String get upgradePageTitle;

  /// No description provided for @upgradePageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock more swing analysis features and sharpen your game'**
  String get upgradePageSubtitle;

  /// No description provided for @upgradeFullComparison.
  ///
  /// In en, this message translates to:
  /// **'Full Feature Comparison'**
  String get upgradeFullComparison;

  /// No description provided for @upgradeFeatureColumn.
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get upgradeFeatureColumn;

  /// No description provided for @upgradeSubscribePlan.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to {plan}'**
  String upgradeSubscribePlan(String plan);

  /// No description provided for @upgradeSelectPayment.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get upgradeSelectPayment;

  /// No description provided for @upgradeApplePayFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple Pay configuration failed to load'**
  String get upgradeApplePayFailed;

  /// No description provided for @upgradeGooglePayFailed.
  ///
  /// In en, this message translates to:
  /// **'Google Pay configuration failed to load'**
  String get upgradeGooglePayFailed;

  /// No description provided for @upgradePaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment verification failed, please try again'**
  String get upgradePaymentFailed;

  /// No description provided for @upgradeSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Upgrade successful'**
  String get upgradeSuccessMsg;

  /// No description provided for @upgradeAlreadyFree.
  ///
  /// In en, this message translates to:
  /// **'You are already on the free plan'**
  String get upgradeAlreadyFree;

  /// No description provided for @learningTitle.
  ///
  /// In en, this message translates to:
  /// **'Swing Learning'**
  String get learningTitle;

  /// No description provided for @learningMoreComing.
  ///
  /// In en, this message translates to:
  /// **'More courses coming soon'**
  String get learningMoreComing;

  /// No description provided for @learningVideoComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Demo video coming soon. Key points and markers available for reference.'**
  String get learningVideoComingSoon;

  /// No description provided for @learningKeyMarkers.
  ///
  /// In en, this message translates to:
  /// **'Key Markers'**
  String get learningKeyMarkers;

  /// No description provided for @myFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'My Feedback'**
  String get myFeedbackTitle;

  /// No description provided for @myFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Submitted feedback & official replies'**
  String get myFeedbackSubtitle;

  /// No description provided for @myFeedbackEntry.
  ///
  /// In en, this message translates to:
  /// **'View My Feedback'**
  String get myFeedbackEntry;

  /// No description provided for @myFeedbackEmpty.
  ///
  /// In en, this message translates to:
  /// **'No feedback yet'**
  String get myFeedbackEmpty;

  /// No description provided for @myFeedbackLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load. Pull down to retry.'**
  String get myFeedbackLoadFailed;

  /// No description provided for @myFeedbackAllLoaded.
  ///
  /// In en, this message translates to:
  /// **'All feedback loaded'**
  String get myFeedbackAllLoaded;

  /// No description provided for @myFeedbackTypeBug.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get myFeedbackTypeBug;

  /// No description provided for @myFeedbackTypeFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get myFeedbackTypeFeature;

  /// No description provided for @myFeedbackTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get myFeedbackTypeOther;

  /// No description provided for @myFeedbackAdminReply.
  ///
  /// In en, this message translates to:
  /// **'Official Reply'**
  String get myFeedbackAdminReply;

  /// No description provided for @myFeedbackNoReply.
  ///
  /// In en, this message translates to:
  /// **'Awaiting reply'**
  String get myFeedbackNoReply;

  /// No description provided for @myFeedbackAttachedVideo.
  ///
  /// In en, this message translates to:
  /// **'Video attached'**
  String get myFeedbackAttachedVideo;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingStart.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingStart;

  /// No description provided for @onboardingRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Your Swing'**
  String get onboardingRecordTitle;

  /// No description provided for @onboardingRecordDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the record button at the bottom center to start filming. ORVIA detects each ball strike while you record.'**
  String get onboardingRecordDesc;

  /// No description provided for @onboardingClipTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic Clipping'**
  String get onboardingClipTitle;

  /// No description provided for @onboardingClipDesc.
  ///
  /// In en, this message translates to:
  /// **'After recording, each swing is automatically cut into a 5-second clip. Review every clip on the history page.'**
  String get onboardingClipDesc;

  /// No description provided for @onboardingAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get onboardingAiTitle;

  /// No description provided for @onboardingAiDesc.
  ///
  /// In en, this message translates to:
  /// **'Send a clip to the AI coach to analyze your posture, the 8 swing phases, and the ball trajectory.'**
  String get onboardingAiDesc;

  /// No description provided for @onboardingBallsTitle.
  ///
  /// In en, this message translates to:
  /// **'Balls & Rewards'**
  String get onboardingBallsTitle;

  /// No description provided for @onboardingBallsDesc.
  ///
  /// In en, this message translates to:
  /// **'Analysis costs balls. Get a free daily quota, and earn more by watching ads, sending feedback, or inviting friends.'**
  String get onboardingBallsDesc;

  /// No description provided for @settingsReplayTutorial.
  ///
  /// In en, this message translates to:
  /// **'Replay Tutorial'**
  String get settingsReplayTutorial;

  /// No description provided for @recFrameCount.
  ///
  /// In en, this message translates to:
  /// **'{count} frames'**
  String recFrameCount(int count);

  /// No description provided for @recDetectedShots.
  ///
  /// In en, this message translates to:
  /// **'{count} detected'**
  String recDetectedShots(int count);

  /// No description provided for @recImpactShot.
  ///
  /// In en, this message translates to:
  /// **'Shot {number}'**
  String recImpactShot(int number);

  /// No description provided for @privacySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Analytics'**
  String get privacySettingsTitle;

  /// No description provided for @privacySectionDataCollection.
  ///
  /// In en, this message translates to:
  /// **'DATA COLLECTION'**
  String get privacySectionDataCollection;

  /// No description provided for @privacyDataCollectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Your videos and analysis data are uploaded only when you take an action yourself — AI analysis, sharing, reward uploads, or feedback attachments. ORVIA performs no background uploads and no hidden telemetry.'**
  String get privacyDataCollectionDesc;

  /// No description provided for @privacySectionPolicies.
  ///
  /// In en, this message translates to:
  /// **'POLICIES'**
  String get privacySectionPolicies;

  /// No description provided for @privacySectionUpload.
  ///
  /// In en, this message translates to:
  /// **'ANALYSIS DATA UPLOAD'**
  String get privacySectionUpload;

  /// No description provided for @privacyUploadDesc.
  ///
  /// In en, this message translates to:
  /// **'You may voluntarily submit swing videos and sensor CSV data to help improve the swing detection model. Each submission is reviewed manually; approved uploads earn bonus balls.'**
  String get privacyUploadDesc;

  /// No description provided for @privacyUploadStatusEntry.
  ///
  /// In en, this message translates to:
  /// **'View My Upload Review Status'**
  String get privacyUploadStatusEntry;

  /// No description provided for @privacySectionAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get privacySectionAccount;

  /// No description provided for @privacyDeleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Soft delete: you can no longer sign in and your data is anonymized'**
  String get privacyDeleteAccountSubtitle;

  /// No description provided for @rewardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Complete tasks to earn balls and redeem analyses'**
  String get rewardSubtitle;

  /// No description provided for @historyFilterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get historyFilterReset;

  /// No description provided for @aiCoachUpgradeFailed.
  ///
  /// In en, this message translates to:
  /// **'Upgrade failed: {error}'**
  String aiCoachUpgradeFailed(String error);

  /// No description provided for @aiCoachQuotaExhaustedTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily ball quota used up'**
  String get aiCoachQuotaExhaustedTitle;

  /// No description provided for @aiCoachQuotaExhaustedBody.
  ///
  /// In en, this message translates to:
  /// **'You have used {todayUsed} analyses today, reaching the limit of {totalLimit}.\n\nYou can continue tomorrow, or upgrade your plan for more analyses.'**
  String aiCoachQuotaExhaustedBody(int todayUsed, int totalLimit);

  /// No description provided for @aiCoachGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get aiCoachGotIt;

  /// No description provided for @aiCoachAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed, please retry'**
  String get aiCoachAnalysisFailed;

  /// No description provided for @aiCoachStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get aiCoachStatusPending;

  /// No description provided for @aiCoachStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting in analysis queue...'**
  String get aiCoachStatusQueued;

  /// No description provided for @aiCoachStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'AI Coach is analyzing the video...'**
  String get aiCoachStatusProcessing;

  /// No description provided for @aiCoachStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for AI Coach analysis...'**
  String get aiCoachStatusIdle;

  /// No description provided for @aiCoachStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get aiCoachStatusConnecting;

  /// No description provided for @aiCoachLoadingHint.
  ///
  /// In en, this message translates to:
  /// **'Usually takes 10–30 seconds'**
  String get aiCoachLoadingHint;

  /// No description provided for @aiCoachPostureAnalysisDone.
  ///
  /// In en, this message translates to:
  /// **'Posture error analysis complete'**
  String get aiCoachPostureAnalysisDone;

  /// No description provided for @aiCoachSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get aiCoachSubmitting;

  /// No description provided for @aiCoachStartAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start AI Coach Analysis'**
  String get aiCoachStartAnalysis;

  /// No description provided for @aiCoachAnalysisHint.
  ///
  /// In en, this message translates to:
  /// **'* AI Coach will provide detailed feedback and training suggestions based on posture analysis results'**
  String get aiCoachAnalysisHint;

  /// No description provided for @aiCoachEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get aiCoachEvidence;

  /// No description provided for @aiCoachSeverityHigh.
  ///
  /// In en, this message translates to:
  /// **'Severe'**
  String get aiCoachSeverityHigh;

  /// No description provided for @aiCoachSeverityMedium.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get aiCoachSeverityMedium;

  /// No description provided for @aiCoachSeverityLow.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get aiCoachSeverityLow;

  /// No description provided for @aiCoachImpactPremiumSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Premium Sweet Spot'**
  String get aiCoachImpactPremiumSweetSpot;

  /// No description provided for @aiCoachImpactSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot'**
  String get aiCoachImpactSweetSpot;

  /// No description provided for @aiCoachImpactNearSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Near Sweet Spot'**
  String get aiCoachImpactNearSweetSpot;

  /// No description provided for @aiCoachImpactFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get aiCoachImpactFair;

  /// No description provided for @aiCoachImpactPoor.
  ///
  /// In en, this message translates to:
  /// **'Off-center Hit'**
  String get aiCoachImpactPoor;

  /// No description provided for @aiCoachImpactQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Impact Quality (Audio)'**
  String get aiCoachImpactQualityTitle;

  /// No description provided for @aiCoachImpactFeatureCount.
  ///
  /// In en, this message translates to:
  /// **'{passCount} / {totalFeatures} features match the sweet spot range'**
  String aiCoachImpactFeatureCount(int passCount, int totalFeatures);

  /// No description provided for @aiCoachFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Coach Feedback'**
  String get aiCoachFeedbackTitle;

  /// No description provided for @aiCoachPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Training Suggestions'**
  String get aiCoachPracticeTitle;

  /// No description provided for @aiCoachNextGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Next Practice Goal'**
  String get aiCoachNextGoalTitle;

  /// No description provided for @aiCoachReanalyzeSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting re-analysis...'**
  String get aiCoachReanalyzeSubmitting;

  /// No description provided for @aiCoachReanalyzeFailed.
  ///
  /// In en, this message translates to:
  /// **'Re-analysis failed: {error}'**
  String aiCoachReanalyzeFailed(String error);

  /// No description provided for @ballTuneTitle.
  ///
  /// In en, this message translates to:
  /// **'Ball Trajectory Tuning'**
  String get ballTuneTitle;

  /// No description provided for @ballTuneHudInit.
  ///
  /// In en, this message translates to:
  /// **'Initializing…'**
  String get ballTuneHudInit;

  /// No description provided for @ballTuneHudDetecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get ballTuneHudDetecting;

  /// No description provided for @ballTuneHudBlobFailed.
  ///
  /// In en, this message translates to:
  /// **'Blob extraction failed'**
  String get ballTuneHudBlobFailed;

  /// No description provided for @ballTuneRoiBadge.
  ///
  /// In en, this message translates to:
  /// **'ROI r={r}px  margin={margin}'**
  String ballTuneRoiBadge(String r, String margin);

  /// No description provided for @ballTuneRoiToggleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Toggle ROI overlay'**
  String get ballTuneRoiToggleTooltip;

  /// No description provided for @ballTuneSectionRealtime.
  ///
  /// In en, this message translates to:
  /// **'Realtime (applies immediately)'**
  String get ballTuneSectionRealtime;

  /// No description provided for @ballTuneSliderResidual.
  ///
  /// In en, this message translates to:
  /// **'Quality gate — residual limit'**
  String get ballTuneSliderResidual;

  /// No description provided for @ballTuneSliderP1MaxDist.
  ///
  /// In en, this message translates to:
  /// **'P1 max distance'**
  String get ballTuneSliderP1MaxDist;

  /// No description provided for @ballTuneRoiMaskSection.
  ///
  /// In en, this message translates to:
  /// **'ROI / Mask (drag on preview to adjust)'**
  String get ballTuneRoiMaskSection;

  /// No description provided for @ballTuneSliderRoiRadius.
  ///
  /// In en, this message translates to:
  /// **'ROI radius'**
  String get ballTuneSliderRoiRadius;

  /// No description provided for @ballTuneSliderGolferMargin.
  ///
  /// In en, this message translates to:
  /// **'Golfer mask margin'**
  String get ballTuneSliderGolferMargin;

  /// No description provided for @ballTuneSliderRoiMissScale.
  ///
  /// In en, this message translates to:
  /// **'ROI miss large expand ×'**
  String get ballTuneSliderRoiMissScale;

  /// No description provided for @ballTuneSliderRoiRadiusMax.
  ///
  /// In en, this message translates to:
  /// **'ROI radius max'**
  String get ballTuneSliderRoiRadiusMax;

  /// No description provided for @ballTuneSliderStepMaxPost.
  ///
  /// In en, this message translates to:
  /// **'Post-impact step max'**
  String get ballTuneSliderStepMaxPost;

  /// No description provided for @ballTuneSliderPredMaxPost.
  ///
  /// In en, this message translates to:
  /// **'Post-impact pred max'**
  String get ballTuneSliderPredMaxPost;

  /// No description provided for @ballTuneSliderMissPatiencePost.
  ///
  /// In en, this message translates to:
  /// **'Post-impact miss tolerance'**
  String get ballTuneSliderMissPatiencePost;

  /// No description provided for @ballTuneSectionReextract.
  ///
  /// In en, this message translates to:
  /// **'Re-extract (press button below to apply)'**
  String get ballTuneSectionReextract;

  /// No description provided for @ballTuneSliderDiffThresh.
  ///
  /// In en, this message translates to:
  /// **'diffThresh frame-diff threshold'**
  String get ballTuneSliderDiffThresh;

  /// No description provided for @ballTuneRedetectButton.
  ///
  /// In en, this message translates to:
  /// **'Re-detect (apply diffThresh)'**
  String get ballTuneRedetectButton;

  /// No description provided for @clipCandTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm shots ({count} candidates)'**
  String clipCandTitle(int count);

  /// No description provided for @clipCandTapToPreview.
  ///
  /// In en, this message translates to:
  /// **'Tap to preview'**
  String get clipCandTapToPreview;

  /// No description provided for @clipCandRangeTooShort.
  ///
  /// In en, this message translates to:
  /// **'Clip range must be at least 0.5 s (end must be after start)'**
  String get clipCandRangeTooShort;

  /// No description provided for @clipCandConfirmClip.
  ///
  /// In en, this message translates to:
  /// **'Clip {count} segment(s)'**
  String clipCandConfirmClip(int count);

  /// No description provided for @clipCandManualHint.
  ///
  /// In en, this message translates to:
  /// **'Start {start} → drag to end then tap \"Add range\"'**
  String clipCandManualHint(String start);

  /// No description provided for @clipCandManualPrompt.
  ///
  /// In en, this message translates to:
  /// **'Free clip: drag timeline to start point'**
  String get clipCandManualPrompt;

  /// No description provided for @clipCandSetStart.
  ///
  /// In en, this message translates to:
  /// **'Set start'**
  String get clipCandSetStart;

  /// No description provided for @clipCandReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get clipCandReset;

  /// No description provided for @clipCandAddRange.
  ///
  /// In en, this message translates to:
  /// **'Add range'**
  String get clipCandAddRange;

  /// No description provided for @clipCandCandidateLabel.
  ///
  /// In en, this message translates to:
  /// **'Candidate {index} · {time}'**
  String clipCandCandidateLabel(int index, String time);

  /// No description provided for @clipCandFromAudio.
  ///
  /// In en, this message translates to:
  /// **'Detected by impact sound'**
  String get clipCandFromAudio;

  /// No description provided for @clipCandFromMotion.
  ///
  /// In en, this message translates to:
  /// **'Detected by motion during recording'**
  String get clipCandFromMotion;

  /// No description provided for @clipCandManualRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom range · {start} - {end}'**
  String clipCandManualRangeLabel(String start, String end);

  /// No description provided for @clipCandRangeDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration {seconds} s'**
  String clipCandRangeDuration(String seconds);

  /// No description provided for @compareLoadingVideos.
  ///
  /// In en, this message translates to:
  /// **'Loading videos…'**
  String get compareLoadingVideos;

  /// No description provided for @highlightTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight Preview'**
  String get highlightTitle;

  /// No description provided for @highlightShareSystem.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get highlightShareSystem;

  /// No description provided for @highlightExportDebug.
  ///
  /// In en, this message translates to:
  /// **'Export debug'**
  String get highlightExportDebug;

  /// No description provided for @highlightShareDebug.
  ///
  /// In en, this message translates to:
  /// **'Share debug'**
  String get highlightShareDebug;

  /// No description provided for @highlightShareText.
  ///
  /// In en, this message translates to:
  /// **'My swing highlight'**
  String get highlightShareText;

  /// No description provided for @highlightDebugFileError.
  ///
  /// In en, this message translates to:
  /// **'Failed to create debug file'**
  String get highlightDebugFileError;

  /// No description provided for @highlightStoragePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission is required to export to the Downloads folder'**
  String get highlightStoragePermissionRequired;

  /// No description provided for @highlightDownloadsDirNotFound.
  ///
  /// In en, this message translates to:
  /// **'Downloads folder not found'**
  String get highlightDownloadsDirNotFound;

  /// No description provided for @highlightSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to: {path}'**
  String highlightSavedTo(String path);

  /// No description provided for @highlightExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String highlightExportFailed(String error);

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'{total} total · {good} good · {bad} bad'**
  String historySubtitle(int total, int good, int bad);

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search recordings…'**
  String get historySearchHint;

  /// No description provided for @historySearchResult.
  ///
  /// In en, this message translates to:
  /// **'Search results {count} / {total}'**
  String historySearchResult(int count, int total);

  /// No description provided for @historySearchNoResult.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get historySearchNoResult;

  /// No description provided for @historySearchNoResultHint.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String historySearchNoResultHint(Object query);

  /// No description provided for @historySearchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get historySearchClear;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start recording your swings to see them here'**
  String get historyEmptySubtitle;

  /// No description provided for @historyFilterLabelSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get historyFilterLabelSort;

  /// No description provided for @historyFilterLabelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get historyFilterLabelDate;

  /// No description provided for @historyFilterLabelVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get historyFilterLabelVideo;

  /// No description provided for @historyFilterLabelGoodBad.
  ///
  /// In en, this message translates to:
  /// **'Shot'**
  String get historyFilterLabelGoodBad;

  /// No description provided for @historyFilterLabelAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get historyFilterLabelAnalysis;

  /// No description provided for @historyFilterLabelClip.
  ///
  /// In en, this message translates to:
  /// **'Clip'**
  String get historyFilterLabelClip;

  /// No description provided for @historyFilterLabelAI.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get historyFilterLabelAI;

  /// No description provided for @historyFilterLabelPosture.
  ///
  /// In en, this message translates to:
  /// **'Posture'**
  String get historyFilterLabelPosture;

  /// No description provided for @historyFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyFilterAll;

  /// No description provided for @historyFilterToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyFilterToday;

  /// No description provided for @historyFilterWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get historyFilterWeek;

  /// No description provided for @historyFilterMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get historyFilterMonth;

  /// No description provided for @historyFilterCustomDate.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get historyFilterCustomDate;

  /// No description provided for @historyFilterSort.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get historyFilterSort;

  /// No description provided for @historyFilterGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get historyFilterGood;

  /// No description provided for @historyFilterBad.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get historyFilterBad;

  /// No description provided for @historyFilterAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Analyzed'**
  String get historyFilterAnalyzed;

  /// No description provided for @historyFilterNotAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Not analyzed'**
  String get historyFilterNotAnalyzed;

  /// No description provided for @historyFilterAiAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'AI analyzed'**
  String get historyFilterAiAnalyzed;

  /// No description provided for @historyFilterAiNotAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'AI not analyzed'**
  String get historyFilterAiNotAnalyzed;

  /// No description provided for @historyFilterClipped.
  ///
  /// In en, this message translates to:
  /// **'Clipped'**
  String get historyFilterClipped;

  /// No description provided for @historyFilterNotClipped.
  ///
  /// In en, this message translates to:
  /// **'Not clipped'**
  String get historyFilterNotClipped;

  /// No description provided for @historyFilterLongVideo.
  ///
  /// In en, this message translates to:
  /// **'Long video'**
  String get historyFilterLongVideo;

  /// No description provided for @historyFilterShortVideo.
  ///
  /// In en, this message translates to:
  /// **'Short video'**
  String get historyFilterShortVideo;

  /// No description provided for @historySortDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get historySortDate;

  /// No description provided for @historySortPeakSpeed.
  ///
  /// In en, this message translates to:
  /// **'Peak speed'**
  String get historySortPeakSpeed;

  /// No description provided for @historySortClipTime.
  ///
  /// In en, this message translates to:
  /// **'Clip time'**
  String get historySortClipTime;

  /// No description provided for @historyDateRangeHelp.
  ///
  /// In en, this message translates to:
  /// **'Select date range'**
  String get historyDateRangeHelp;

  /// No description provided for @historyDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get historyDeleteTitle;

  /// No description provided for @historyDeleteClipConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete clip \"{title}\"?'**
  String historyDeleteClipConfirm(Object title);

  /// No description provided for @historyDeleteVideoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete recording \"{title}\"?'**
  String historyDeleteVideoConfirm(Object title);

  /// No description provided for @historyDeleteVideoWithClipsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and its {count} clips?'**
  String historyDeleteVideoWithClipsConfirm(Object title, Object count);

  /// No description provided for @historyDeletedSnack.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String historyDeletedSnack(Object name);

  /// No description provided for @historyDeletedWithClipsSnack.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name} and {count} clips'**
  String historyDeletedWithClipsSnack(Object name, Object count);

  /// No description provided for @historyRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename recording'**
  String get historyRenameTitle;

  /// No description provided for @historyRenameClipTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename clip'**
  String get historyRenameClipTitle;

  /// No description provided for @historyRenameLabel.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get historyRenameLabel;

  /// No description provided for @historyRenameHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to reset to default name'**
  String get historyRenameHelper;

  /// No description provided for @historyRenameValidation.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be blank'**
  String get historyRenameValidation;

  /// No description provided for @historyRenamedSnack.
  ///
  /// In en, this message translates to:
  /// **'Renamed to {name}'**
  String historyRenamedSnack(Object name);

  /// No description provided for @historyRenameResetSnack.
  ///
  /// In en, this message translates to:
  /// **'Reset to default name \"{name}\"'**
  String historyRenameResetSnack(Object name);

  /// No description provided for @historyFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found: {name}'**
  String historyFileNotFound(Object name);

  /// No description provided for @historyClipFileNotExist.
  ///
  /// In en, this message translates to:
  /// **'Clip file does not exist, please re-detect'**
  String get historyClipFileNotExist;

  /// No description provided for @historyAlreadyClipped.
  ///
  /// In en, this message translates to:
  /// **'This video already has clips. Re-detect to replace them.'**
  String get historyAlreadyClipped;

  /// No description provided for @historyProgressPreparingSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Preparing skeleton analysis…'**
  String get historyProgressPreparingSkeleton;

  /// No description provided for @historyProgressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get historyProgressPreparing;

  /// No description provided for @historyDetectingShots.
  ///
  /// In en, this message translates to:
  /// **'Detecting shots'**
  String get historyDetectingShots;

  /// No description provided for @historyCancelledDetection.
  ///
  /// In en, this message translates to:
  /// **'Detection cancelled'**
  String get historyCancelledDetection;

  /// No description provided for @historyCancelledAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis cancelled'**
  String get historyCancelledAnalysis;

  /// No description provided for @historyV2NoAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio track found, cannot use audio-based detection'**
  String get historyV2NoAudio;

  /// No description provided for @historyV3NoShot.
  ///
  /// In en, this message translates to:
  /// **'No shot detected in skeleton analysis'**
  String get historyV3NoShot;

  /// No description provided for @historyV3NoValidHit.
  ///
  /// In en, this message translates to:
  /// **'No valid impact found after filtering'**
  String get historyV3NoValidHit;

  /// No description provided for @historyNoShotDetected.
  ///
  /// In en, this message translates to:
  /// **'No shots detected'**
  String get historyNoShotDetected;

  /// No description provided for @historyClipFailed.
  ///
  /// In en, this message translates to:
  /// **'Clip generation failed'**
  String get historyClipFailed;

  /// No description provided for @historyClipsGenerated.
  ///
  /// In en, this message translates to:
  /// **'{count} clips generated'**
  String historyClipsGenerated(Object count);

  /// No description provided for @historyClipsGeneratedBg.
  ///
  /// In en, this message translates to:
  /// **'{count} clips saved to history'**
  String historyClipsGeneratedBg(Object count);

  /// No description provided for @historyDetectFailed.
  ///
  /// In en, this message translates to:
  /// **'Detection failed: {error}'**
  String historyDetectFailed(Object error);

  /// No description provided for @historyLongVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Long video warning'**
  String get historyLongVideoTitle;

  /// No description provided for @historyLongVideoContent.
  ///
  /// In en, this message translates to:
  /// **'This video is {seconds}s long. Full analysis may take a while.'**
  String historyLongVideoContent(Object seconds);

  /// No description provided for @historyContinueAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get historyContinueAnalysis;

  /// No description provided for @historyFullAnalysisTitle.
  ///
  /// In en, this message translates to:
  /// **'Analyzing'**
  String get historyFullAnalysisTitle;

  /// No description provided for @historyInvalidDuration.
  ///
  /// In en, this message translates to:
  /// **'Invalid video duration: {seconds}s'**
  String historyInvalidDuration(Object seconds);

  /// No description provided for @historyAnalysisComplete.
  ///
  /// In en, this message translates to:
  /// **'Analysis complete{audio}'**
  String historyAnalysisComplete(Object audio);

  /// No description provided for @historyAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed: {error}'**
  String historyAnalysisFailed(Object error);

  /// No description provided for @historyQuotaExhaustedTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily quota reached'**
  String get historyQuotaExhaustedTitle;

  /// No description provided for @historyQuotaExhaustedContent.
  ///
  /// In en, this message translates to:
  /// **'Used {used}/{total} today. Upgrade to continue.'**
  String historyQuotaExhaustedContent(Object used, Object total);

  /// No description provided for @historyGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get historyGotIt;

  /// No description provided for @historyAiAnalysisConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get historyAiAnalysisConfirmTitle;

  /// No description provided for @historyAiAnalysisConfirmDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit this swing for AI analysis. This will use 1 ball.'**
  String get historyAiAnalysisConfirmDesc;

  /// No description provided for @historyAiAnalysisConfirmBtn.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get historyAiAnalysisConfirmBtn;

  /// No description provided for @historyAiSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed: {error}'**
  String historyAiSubmitFailed(Object error);

  /// No description provided for @historyNoOtherVideoToCompare.
  ///
  /// In en, this message translates to:
  /// **'No other videos available to compare'**
  String get historyNoOtherVideoToCompare;

  /// No description provided for @historyCompareTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare swings'**
  String get historyCompareTitle;

  /// No description provided for @historyCompareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a video to compare with \"{title}\"'**
  String historyCompareSubtitle(Object title);

  /// No description provided for @historyPhasesJsonMissing.
  ///
  /// In en, this message translates to:
  /// **'phases.json not found, please re-analyze'**
  String get historyPhasesJsonMissing;

  /// No description provided for @historyPhasesJsonInvalid.
  ///
  /// In en, this message translates to:
  /// **'phases.json is invalid, please re-analyze'**
  String get historyPhasesJsonInvalid;

  /// No description provided for @historySelectAiModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select AI mode'**
  String get historySelectAiModeTitle;

  /// No description provided for @historyAiModeV1Title.
  ///
  /// In en, this message translates to:
  /// **'Basic (V1)'**
  String get historyAiModeV1Title;

  /// No description provided for @historyAiModeV1Desc.
  ///
  /// In en, this message translates to:
  /// **'Audio peak detection'**
  String get historyAiModeV1Desc;

  /// No description provided for @historyAiModeV2Title.
  ///
  /// In en, this message translates to:
  /// **'Standard (V2)'**
  String get historyAiModeV2Title;

  /// No description provided for @historyAiModeV2Desc.
  ///
  /// In en, this message translates to:
  /// **'Audio + skeleton hybrid'**
  String get historyAiModeV2Desc;

  /// No description provided for @historyAiModeV3Title.
  ///
  /// In en, this message translates to:
  /// **'Advanced (V3)'**
  String get historyAiModeV3Title;

  /// No description provided for @historyAiModeV3Desc.
  ///
  /// In en, this message translates to:
  /// **'Skeleton-first with audio refinement'**
  String get historyAiModeV3Desc;

  /// No description provided for @historySelectDetectModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select detection mode'**
  String get historySelectDetectModeTitle;

  /// No description provided for @historyDetectV1Title.
  ///
  /// In en, this message translates to:
  /// **'Skeleton (V1)'**
  String get historyDetectV1Title;

  /// No description provided for @historyDetectV1Desc.
  ///
  /// In en, this message translates to:
  /// **'MediaPipe pose estimation'**
  String get historyDetectV1Desc;

  /// No description provided for @historyDetectBadgePrecise.
  ///
  /// In en, this message translates to:
  /// **'Precise'**
  String get historyDetectBadgePrecise;

  /// No description provided for @historyDetectV1Time.
  ///
  /// In en, this message translates to:
  /// **'~10s'**
  String get historyDetectV1Time;

  /// No description provided for @historyDetectV2Title.
  ///
  /// In en, this message translates to:
  /// **'Audio (V2)'**
  String get historyDetectV2Title;

  /// No description provided for @historyDetectV2Desc.
  ///
  /// In en, this message translates to:
  /// **'Fast audio peak detection'**
  String get historyDetectV2Desc;

  /// No description provided for @historyDetectBadgeFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get historyDetectBadgeFast;

  /// No description provided for @historyDetectV2Time.
  ///
  /// In en, this message translates to:
  /// **'~30s'**
  String get historyDetectV2Time;

  /// No description provided for @historyDetectV3Title.
  ///
  /// In en, this message translates to:
  /// **'Hybrid (V3)'**
  String get historyDetectV3Title;

  /// No description provided for @historyDetectV3Desc.
  ///
  /// In en, this message translates to:
  /// **'Skeleton-first + audio refinement'**
  String get historyDetectV3Desc;

  /// No description provided for @historyDetectBadgeBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get historyDetectBadgeBalanced;

  /// No description provided for @historyDetectV4Title.
  ///
  /// In en, this message translates to:
  /// **'Anchor (V4)'**
  String get historyDetectV4Title;

  /// No description provided for @historyDetectV4Desc.
  ///
  /// In en, this message translates to:
  /// **'Uses the ball/grip spot tapped while recording; impact = dominant wrist closest to the anchor.'**
  String get historyDetectV4Desc;

  /// No description provided for @historyDetectBadgeAnchor.
  ///
  /// In en, this message translates to:
  /// **'Anchor'**
  String get historyDetectBadgeAnchor;

  /// No description provided for @historyDetectV3Time.
  ///
  /// In en, this message translates to:
  /// **'~45s'**
  String get historyDetectV3Time;

  /// No description provided for @historySkipToday.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show today'**
  String get historySkipToday;

  /// No description provided for @historyStartDetect.
  ///
  /// In en, this message translates to:
  /// **'Start detection'**
  String get historyStartDetect;

  /// No description provided for @historySelectQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Select export quality'**
  String get historySelectQualityTitle;

  /// No description provided for @historyStartAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start analysis'**
  String get historyStartAnalysis;

  /// No description provided for @historyMenuAddClip.
  ///
  /// In en, this message translates to:
  /// **'Add clip'**
  String get historyMenuAddClip;

  /// No description provided for @historyActionDetect.
  ///
  /// In en, this message translates to:
  /// **'Detect swings'**
  String get historyActionDetect;

  /// No description provided for @historyActionAiAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI analysis'**
  String get historyActionAiAnalysis;

  /// No description provided for @historyActionFullAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Full analysis'**
  String get historyActionFullAnalysis;

  /// No description provided for @historyActionChart.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get historyActionChart;

  /// No description provided for @historyActionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get historyActionPlay;

  /// No description provided for @historyActionExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand clips'**
  String get historyActionExpand;

  /// No description provided for @historyActionCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse clips'**
  String get historyActionCollapse;

  /// No description provided for @historyMenuRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get historyMenuRename;

  /// No description provided for @historyMenuAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get historyMenuAddNote;

  /// No description provided for @historyMenuEditNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get historyMenuEditNote;

  /// No description provided for @historyMenuShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get historyMenuShare;

  /// No description provided for @historyMenuDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get historyMenuDownload;

  /// No description provided for @historyMenuDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get historyMenuDownloading;

  /// No description provided for @historyMenuCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get historyMenuCompare;

  /// No description provided for @historyMenuUploadReward.
  ///
  /// In en, this message translates to:
  /// **'Upload for +{balls} balls'**
  String historyMenuUploadReward(int balls);

  /// No description provided for @historyMenuUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get historyMenuUploaded;

  /// No description provided for @historyMenuAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get historyMenuAnalyzing;

  /// No description provided for @historyMenuDeleteVideo.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get historyMenuDeleteVideo;

  /// No description provided for @historyMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get historyMoreActions;

  /// No description provided for @historyBadgeNoAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio'**
  String get historyBadgeNoAudio;

  /// No description provided for @historyBadgeAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Analyzed'**
  String get historyBadgeAnalyzed;

  /// No description provided for @historySweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet spot'**
  String get historySweetSpot;

  /// No description provided for @historySweetSpotHit.
  ///
  /// In en, this message translates to:
  /// **'Hit'**
  String get historySweetSpotHit;

  /// No description provided for @historySweetSpotMiss.
  ///
  /// In en, this message translates to:
  /// **'Miss'**
  String get historySweetSpotMiss;

  /// No description provided for @historyHitSummary.
  ///
  /// In en, this message translates to:
  /// **'Shot summary'**
  String get historyHitSummary;

  /// No description provided for @historyClipDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Shot {index}'**
  String historyClipDefaultName(Object index);

  /// No description provided for @historyClipHitAt.
  ///
  /// In en, this message translates to:
  /// **'Impact @ {time}'**
  String historyClipHitAt(Object time);

  /// No description provided for @historyClipRange.
  ///
  /// In en, this message translates to:
  /// **'Clip {start}–{end}s'**
  String historyClipRange(Object start, Object end);

  /// No description provided for @historyRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Round {index}'**
  String historyRoundLabel(Object index);

  /// No description provided for @historyDurationLine.
  ///
  /// In en, this message translates to:
  /// **'{time} · {seconds}s'**
  String historyDurationLine(Object time, Object seconds);

  /// No description provided for @historyImportedFrom.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String historyImportedFrom(Object name);

  /// No description provided for @historyNoteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Video note'**
  String get historyNoteDialogTitle;

  /// No description provided for @historyNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Practice notes, location, club used…'**
  String get historyNoteHint;

  /// No description provided for @historyNoteHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to clear note'**
  String get historyNoteHelper;

  /// No description provided for @historySaveLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Save location'**
  String get historySaveLocationTitle;

  /// No description provided for @historySaveLocationDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads folder'**
  String get historySaveLocationDownloads;

  /// No description provided for @historySaveLocationDownloadsSub.
  ///
  /// In en, this message translates to:
  /// **'Save to system Downloads'**
  String get historySaveLocationDownloadsSub;

  /// No description provided for @historySaveLocationPick.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get historySaveLocationPick;

  /// No description provided for @historySaveLocationPickSub.
  ///
  /// In en, this message translates to:
  /// **'Custom save location'**
  String get historySaveLocationPickSub;

  /// No description provided for @historyDownloadVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select version'**
  String get historyDownloadVersionTitle;

  /// No description provided for @historyExportSaved.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" saved ✅'**
  String historyExportSaved(Object label);

  /// No description provided for @historyExportSavedPhotos.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" saved to Camera Roll ✅'**
  String historyExportSavedPhotos(Object label);

  /// No description provided for @historyExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {detail}'**
  String historyExportFailed(Object detail);

  /// No description provided for @historyUploadRewardTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload for reward'**
  String get historyUploadRewardTitle;

  /// No description provided for @historyUploadRewardContent.
  ///
  /// In en, this message translates to:
  /// **'Upload analysis data for \"{title}\" to improve swing detection. After review, you\'ll receive +{balls} balls.'**
  String historyUploadRewardContent(Object title, Object balls);

  /// No description provided for @historyUploadSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get historyUploadSubmit;

  /// No description provided for @historyUploadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Uploading video and analysis data…'**
  String get historyUploadingProgress;

  /// No description provided for @historyUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String historyUploadFailed(Object error);

  /// No description provided for @historyUploadSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed: this video may have already been submitted (including rejected ones), or please retry later'**
  String get historyUploadSubmitFailed;

  /// No description provided for @historyUploadReviewPending.
  ///
  /// In en, this message translates to:
  /// **'Submitted for review. +{balls} balls will be awarded upon approval.'**
  String historyUploadReviewPending(Object balls);

  /// No description provided for @hitsSummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No shots detected yet'**
  String get hitsSummaryEmpty;

  /// No description provided for @hitsSummaryHitIndex.
  ///
  /// In en, this message translates to:
  /// **'Shot #{index}'**
  String hitsSummaryHitIndex(int index);

  /// No description provided for @hitsSummaryPeak.
  ///
  /// In en, this message translates to:
  /// **'Peak'**
  String get hitsSummaryPeak;

  /// No description provided for @hitsSummaryDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get hitsSummaryDuration;

  /// No description provided for @hitsSummaryStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get hitsSummaryStart;

  /// No description provided for @hitsSummaryEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get hitsSummaryEnd;

  /// No description provided for @hitsSummaryDetectFrom.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String hitsSummaryDetectFrom(String source);

  /// No description provided for @hitsSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Shot Summary'**
  String get hitsSummaryTitle;

  /// No description provided for @hitsSummaryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shots total'**
  String hitsSummaryCount(int count);

  /// No description provided for @homeCurrentSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Current Practice Plan'**
  String get homeCurrentSuggestions;

  /// No description provided for @homeNextGoal.
  ///
  /// In en, this message translates to:
  /// **'Next goal: {goal}'**
  String homeNextGoal(String goal);

  /// No description provided for @authInviteCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get authInviteCodeOptional;

  /// No description provided for @authInviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite Code'**
  String get authInviteCodeLabel;

  /// No description provided for @authInviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a friend\'s invite code if you have one'**
  String get authInviteCodeHint;

  /// No description provided for @authInviteCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Enter an invite code — both of you get +5 ball rewards'**
  String get authInviteCodeHelper;

  /// No description provided for @devTestAccounts.
  ///
  /// In en, this message translates to:
  /// **'Test Accounts'**
  String get devTestAccounts;

  /// No description provided for @devTestPassword.
  ///
  /// In en, this message translates to:
  /// **'Password: Test1234!'**
  String get devTestPassword;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotTitle;

  /// No description provided for @forgotEnterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Verification Code'**
  String get forgotEnterCodeTitle;

  /// No description provided for @forgotEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your Email — we\'ll send you a 6-digit verification code'**
  String get forgotEmailSubtitle;

  /// No description provided for @forgotCodeSentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to {email}'**
  String forgotCodeSentSubtitle(String email);

  /// No description provided for @forgotSixDigitCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit Code'**
  String get forgotSixDigitCodeLabel;

  /// No description provided for @forgotNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get forgotNewPasswordLabel;

  /// No description provided for @forgotNewPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters with uppercase, lowercase, and digits'**
  String get forgotNewPasswordHint;

  /// No description provided for @forgotConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get forgotConfirmPasswordLabel;

  /// No description provided for @forgotSendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Send Verification Code'**
  String get forgotSendCodeButton;

  /// No description provided for @forgotConfirmResetButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password Reset'**
  String get forgotConfirmResetButton;

  /// No description provided for @forgotReEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Re-enter Email'**
  String get forgotReEnterEmail;

  /// No description provided for @forgotEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid Email'**
  String get forgotEnterValidEmail;

  /// No description provided for @forgotSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send'**
  String get forgotSendFailed;

  /// No description provided for @forgotNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Network error, please try again later'**
  String get forgotNetworkError;

  /// No description provided for @forgotEnterSixDigitCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter the 6-digit verification code'**
  String get forgotEnterSixDigitCode;

  /// No description provided for @forgotPasswordComplexity.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters with uppercase, lowercase, and digits'**
  String get forgotPasswordComplexity;

  /// No description provided for @forgotPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get forgotPasswordMismatch;

  /// No description provided for @forgotResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password reset — please sign in with your new password'**
  String get forgotResetSuccess;

  /// No description provided for @forgotResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get forgotResetFailed;

  /// No description provided for @playerTitle.
  ///
  /// In en, this message translates to:
  /// **'Video Review'**
  String get playerTitle;

  /// No description provided for @playerNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get playerNote;

  /// No description provided for @playerNoteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get playerNoteAdd;

  /// No description provided for @playerNoteEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get playerNoteEdit;

  /// No description provided for @playerNoteCleared.
  ///
  /// In en, this message translates to:
  /// **'Note cleared'**
  String get playerNoteCleared;

  /// No description provided for @playerNoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get playerNoteSaved;

  /// No description provided for @playerVideoNotFound.
  ///
  /// In en, this message translates to:
  /// **'Video file not found'**
  String get playerVideoNotFound;

  /// No description provided for @playerVideoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load video'**
  String get playerVideoLoadFailed;

  /// No description provided for @playerSkeletonNotFound.
  ///
  /// In en, this message translates to:
  /// **'Skeleton data not available'**
  String get playerSkeletonNotFound;

  /// No description provided for @playerOverlaySync.
  ///
  /// In en, this message translates to:
  /// **'Overlay sync'**
  String get playerOverlaySync;

  /// No description provided for @playerOverlaySyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Time offset between skeleton/trajectory and video. Lagging behind → increase; ahead → decrease.'**
  String get playerOverlaySyncDesc;

  /// No description provided for @playerOverlaySkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton'**
  String get playerOverlaySkeleton;

  /// No description provided for @playerOverlayTrajectory.
  ///
  /// In en, this message translates to:
  /// **'Trajectory'**
  String get playerOverlayTrajectory;

  /// No description provided for @playerOverlayEffect.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get playerOverlayEffect;

  /// No description provided for @playerOverlayAnchor.
  ///
  /// In en, this message translates to:
  /// **'Anchor'**
  String get playerOverlayAnchor;

  /// No description provided for @playerTrajectoryTuning.
  ///
  /// In en, this message translates to:
  /// **'Trajectory Tuning'**
  String get playerTrajectoryTuning;

  /// No description provided for @playerShotLabel.
  ///
  /// In en, this message translates to:
  /// **'Shot {index} {time}'**
  String playerShotLabel(int index, String time);

  /// No description provided for @playerStatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No statistics yet (requires trajectory or phase analysis)'**
  String get playerStatsEmpty;

  /// No description provided for @playerStatLaunchAngle.
  ///
  /// In en, this message translates to:
  /// **'Launch Angle'**
  String get playerStatLaunchAngle;

  /// No description provided for @playerStatTempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo (Back:Down)'**
  String get playerStatTempo;

  /// No description provided for @playerStatBackDownswing.
  ///
  /// In en, this message translates to:
  /// **'Back / Downswing'**
  String get playerStatBackDownswing;

  /// No description provided for @playerStatFlightTime.
  ///
  /// In en, this message translates to:
  /// **'In-Frame Flight'**
  String get playerStatFlightTime;

  /// No description provided for @playerChartEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chart data. Please complete analysis first.'**
  String get playerChartEmpty;

  /// No description provided for @playerChartNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get playerChartNoData;

  /// No description provided for @playerChartAudioEmpty.
  ///
  /// In en, this message translates to:
  /// **'Audio peak — no data'**
  String get playerChartAudioEmpty;

  /// No description provided for @playerChartWristYEmpty.
  ///
  /// In en, this message translates to:
  /// **'Wrist Y — no data'**
  String get playerChartWristYEmpty;

  /// No description provided for @playerChartSpeedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Speed — no data'**
  String get playerChartSpeedEmpty;

  /// No description provided for @playerChartTabAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio Peak'**
  String get playerChartTabAudio;

  /// No description provided for @playerChartTabWristY.
  ///
  /// In en, this message translates to:
  /// **'Wrist Y'**
  String get playerChartTabWristY;

  /// No description provided for @playerChartTabSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get playerChartTabSpeed;

  /// No description provided for @playerChartTabPosture.
  ///
  /// In en, this message translates to:
  /// **'Posture'**
  String get playerChartTabPosture;

  /// No description provided for @playerChartTabAudioFeature.
  ///
  /// In en, this message translates to:
  /// **'Audio Features'**
  String get playerChartTabAudioFeature;

  /// No description provided for @playerLoadDetailScore.
  ///
  /// In en, this message translates to:
  /// **'Load Detailed Scores'**
  String get playerLoadDetailScore;

  /// No description provided for @playerPostureEmpty.
  ///
  /// In en, this message translates to:
  /// **'No posture analysis yet. Please complete analysis first.'**
  String get playerPostureEmpty;

  /// No description provided for @playerAudioPassCount.
  ///
  /// In en, this message translates to:
  /// **'{count} / 5 features passed'**
  String playerAudioPassCount(int count);

  /// No description provided for @playerAudioEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audio analysis yet'**
  String get playerAudioEmpty;

  /// No description provided for @playerAiAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'AI analysis failed: {error}'**
  String playerAiAnalysisFailed(String error);

  /// No description provided for @playerAiNotStarted.
  ///
  /// In en, this message translates to:
  /// **'AI coach analysis not yet started'**
  String get playerAiNotStarted;

  /// No description provided for @playerAiStartAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start Analysis'**
  String get playerAiStartAnalysis;

  /// No description provided for @playerAiViewProgress.
  ///
  /// In en, this message translates to:
  /// **'View Progress'**
  String get playerAiViewProgress;

  /// No description provided for @playerAiCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Coach Analysis'**
  String get playerAiCoachTitle;

  /// No description provided for @playerAiPrimaryIssue.
  ///
  /// In en, this message translates to:
  /// **'Primary Issue'**
  String get playerAiPrimaryIssue;

  /// No description provided for @playerAiCoachFeedback.
  ///
  /// In en, this message translates to:
  /// **'Coach Feedback'**
  String get playerAiCoachFeedback;

  /// No description provided for @playerAiPracticeSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Practice Suggestions'**
  String get playerAiPracticeSuggestions;

  /// No description provided for @playerAiNextGoal.
  ///
  /// In en, this message translates to:
  /// **'Next Goal'**
  String get playerAiNextGoal;

  /// No description provided for @playerAiReanalyze.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get playerAiReanalyze;

  /// No description provided for @playerAiViewDetail.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get playerAiViewDetail;

  /// No description provided for @playerAiStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get playerAiStatusPending;

  /// No description provided for @playerAiStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting in analysis queue...'**
  String get playerAiStatusQueued;

  /// No description provided for @playerAiStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'AI coach analyzing...'**
  String get playerAiStatusProcessing;

  /// No description provided for @playerAiStatusAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing...'**
  String get playerAiStatusAnalyzing;

  /// No description provided for @playerSeverityHigh.
  ///
  /// In en, this message translates to:
  /// **'Severe'**
  String get playerSeverityHigh;

  /// No description provided for @playerSeverityMedium.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get playerSeverityMedium;

  /// No description provided for @playerSeverityLow.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get playerSeverityLow;

  /// No description provided for @playerHighlightPreview.
  ///
  /// In en, this message translates to:
  /// **'Highlight Preview'**
  String get playerHighlightPreview;

  /// No description provided for @playerSweetSpotHit.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot Hit'**
  String get playerSweetSpotHit;

  /// No description provided for @playerSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot'**
  String get playerSweetSpot;

  /// No description provided for @playerThinShot.
  ///
  /// In en, this message translates to:
  /// **'Thin Shot'**
  String get playerThinShot;

  /// No description provided for @playerAudioPassCountBadge.
  ///
  /// In en, this message translates to:
  /// **'{count}/5 features matched'**
  String playerAudioPassCountBadge(int count);

  /// No description provided for @playerNoteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Video Note'**
  String get playerNoteDialogTitle;

  /// No description provided for @playerNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Jot down practice thoughts, course, club used…'**
  String get playerNoteHint;

  /// No description provided for @playerNoteHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to clear the note'**
  String get playerNoteHelper;

  /// No description provided for @playerPhaseAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get playerPhaseAddress;

  /// No description provided for @playerPhaseTakeaway.
  ///
  /// In en, this message translates to:
  /// **'Takeaway'**
  String get playerPhaseTakeaway;

  /// No description provided for @playerPhaseBackswing.
  ///
  /// In en, this message translates to:
  /// **'Backswing'**
  String get playerPhaseBackswing;

  /// No description provided for @playerPhaseTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get playerPhaseTop;

  /// No description provided for @playerPhaseDownswing.
  ///
  /// In en, this message translates to:
  /// **'Downswing'**
  String get playerPhaseDownswing;

  /// No description provided for @playerPhaseImpact.
  ///
  /// In en, this message translates to:
  /// **'Impact'**
  String get playerPhaseImpact;

  /// No description provided for @clipLegendStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get clipLegendStart;

  /// No description provided for @clipLegendEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get clipLegendEnd;

  /// No description provided for @playerPhaseFollowthrough.
  ///
  /// In en, this message translates to:
  /// **'Follow-through'**
  String get playerPhaseFollowthrough;

  /// No description provided for @playerPhaseFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get playerPhaseFinish;

  /// No description provided for @pSystemTitle.
  ///
  /// In en, this message translates to:
  /// **'P-System'**
  String get pSystemTitle;

  /// No description provided for @pSystemViewpointWarn.
  ///
  /// In en, this message translates to:
  /// **'Rotation needs face-on view'**
  String get pSystemViewpointWarn;

  /// No description provided for @pSystemNoMetrics.
  ///
  /// In en, this message translates to:
  /// **'No measurable metrics here'**
  String get pSystemNoMetrics;

  /// No description provided for @metricSpineTilt.
  ///
  /// In en, this message translates to:
  /// **'Spine angle'**
  String get metricSpineTilt;

  /// No description provided for @metricHeadMove.
  ///
  /// In en, this message translates to:
  /// **'Head movement'**
  String get metricHeadMove;

  /// No description provided for @metricXFactor.
  ///
  /// In en, this message translates to:
  /// **'X-factor'**
  String get metricXFactor;

  /// No description provided for @metricWeightShift.
  ///
  /// In en, this message translates to:
  /// **'Weight shift'**
  String get metricWeightShift;

  /// No description provided for @metricOverall.
  ///
  /// In en, this message translates to:
  /// **'Overall'**
  String get metricOverall;

  /// No description provided for @trendTitle.
  ///
  /// In en, this message translates to:
  /// **'Correction tracking'**
  String get trendTitle;

  /// No description provided for @trendImproving.
  ///
  /// In en, this message translates to:
  /// **'Improving'**
  String get trendImproving;

  /// No description provided for @trendDeclining.
  ///
  /// In en, this message translates to:
  /// **'Declining'**
  String get trendDeclining;

  /// No description provided for @trendStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get trendStable;

  /// No description provided for @trendInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Not enough data'**
  String get trendInsufficient;

  /// No description provided for @pLabelP1.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get pLabelP1;

  /// No description provided for @pLabelP2.
  ///
  /// In en, this message translates to:
  /// **'Take'**
  String get pLabelP2;

  /// No description provided for @pLabelP3.
  ///
  /// In en, this message translates to:
  /// **'Bk½'**
  String get pLabelP3;

  /// No description provided for @pLabelP4.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get pLabelP4;

  /// No description provided for @pLabelP5.
  ///
  /// In en, this message translates to:
  /// **'Dn½'**
  String get pLabelP5;

  /// No description provided for @pLabelP6.
  ///
  /// In en, this message translates to:
  /// **'Pre'**
  String get pLabelP6;

  /// No description provided for @pLabelP7.
  ///
  /// In en, this message translates to:
  /// **'Impact'**
  String get pLabelP7;

  /// No description provided for @pLabelP8.
  ///
  /// In en, this message translates to:
  /// **'Foll'**
  String get pLabelP8;

  /// No description provided for @pLabelP9.
  ///
  /// In en, this message translates to:
  /// **'Fin½'**
  String get pLabelP9;

  /// No description provided for @pLabelP10.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get pLabelP10;

  /// No description provided for @chartTabStage.
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get chartTabStage;

  /// No description provided for @chartTabCharts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get chartTabCharts;

  /// No description provided for @chartTabAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get chartTabAudio;

  /// No description provided for @chartTabPosture.
  ///
  /// In en, this message translates to:
  /// **'Posture'**
  String get chartTabPosture;

  /// No description provided for @pSystemNoData.
  ///
  /// In en, this message translates to:
  /// **'No P-System data for this clip — re-run swing detection'**
  String get pSystemNoData;

  /// No description provided for @pSystemHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'P-System Guide'**
  String get pSystemHelpTitle;

  /// No description provided for @pSystemHelpIntro.
  ///
  /// In en, this message translates to:
  /// **'P1–P10 are 10 key positions of the swing from setup to finish. Each measures a few biomechanics angles and is scored, so you can see which part needs work.'**
  String get pSystemHelpIntro;

  /// No description provided for @pSystemHelpPositionsHeader.
  ///
  /// In en, this message translates to:
  /// **'The 10 positions'**
  String get pSystemHelpPositionsHeader;

  /// No description provided for @pSystemHelpReliable.
  ///
  /// In en, this message translates to:
  /// **'Reliable anchor'**
  String get pSystemHelpReliable;

  /// No description provided for @pSystemHelpProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy estimate (beta)'**
  String get pSystemHelpProxy;

  /// No description provided for @pSystemHelpScoringHeader.
  ///
  /// In en, this message translates to:
  /// **'How scoring works'**
  String get pSystemHelpScoringHeader;

  /// No description provided for @pSystemHelpScoringBody.
  ///
  /// In en, this message translates to:
  /// **'Each metric is scored by whether it falls in the ideal range: good=100, warn=60, off=20, not-measurable=excluded. Each position averages its metrics; the overall score averages the positions.'**
  String get pSystemHelpScoringBody;

  /// No description provided for @gradeGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get gradeGood;

  /// No description provided for @gradeWarn.
  ///
  /// In en, this message translates to:
  /// **'Warn'**
  String get gradeWarn;

  /// No description provided for @gradeBad.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get gradeBad;

  /// No description provided for @pSystemHelpMetricsHeader.
  ///
  /// In en, this message translates to:
  /// **'Motion metrics'**
  String get pSystemHelpMetricsHeader;

  /// No description provided for @metricSpineTiltDesc.
  ///
  /// In en, this message translates to:
  /// **'Spine forward-tilt vs the ground. Ideally kept close to your setup angle from backswing through impact (no lifting or collapsing).'**
  String get metricSpineTiltDesc;

  /// No description provided for @metricHeadMoveDesc.
  ///
  /// In en, this message translates to:
  /// **'Head displacement from the setup position. Steadier is better; large movement means your center/axis drifted.'**
  String get metricHeadMoveDesc;

  /// No description provided for @metricXFactorDesc.
  ///
  /// In en, this message translates to:
  /// **'Rotational separation between shoulders and hips — the power source. Only measurable when filmed face-on.'**
  String get metricXFactorDesc;

  /// No description provided for @metricWeightShiftDesc.
  ///
  /// In en, this message translates to:
  /// **'Whether the hips turn toward the lead foot at impact. Insufficient shift loses power and causes thin contact.'**
  String get metricWeightShiftDesc;

  /// No description provided for @pSystemHelpViewpoint.
  ///
  /// In en, this message translates to:
  /// **'X-factor (rotation) is estimated from a 2D projection and is accurate only when filmed face-on; it is hidden for down-the-line footage.'**
  String get pSystemHelpViewpoint;

  /// No description provided for @pSystemHelpBeta.
  ///
  /// In en, this message translates to:
  /// **'Club-related positions (P2/P6/P8) use the forearm as a proxy and rotation is a 2D estimate — all marked beta. Ideal ranges are generic placeholders for trend reference, not lab-grade measurement.'**
  String get pSystemHelpBeta;

  /// No description provided for @postureTitle.
  ///
  /// In en, this message translates to:
  /// **'Posture Analysis'**
  String get postureTitle;

  /// No description provided for @postureNoData.
  ///
  /// In en, this message translates to:
  /// **'No AI analysis data yet'**
  String get postureNoData;

  /// No description provided for @profileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your profile for more accurate swing analysis. Remember to save when done.'**
  String get profileSubtitle;

  /// No description provided for @profileAvatarHint.
  ///
  /// In en, this message translates to:
  /// **'Set a profile photo so your coach can identify you more easily'**
  String get profileAvatarHint;

  /// No description provided for @profileAvatarSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save photo. Please try again later.'**
  String get profileAvatarSaveFailed;

  /// No description provided for @profileDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get profileDisplayNameLabel;

  /// No description provided for @profileDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name shown on the home screen'**
  String get profileDisplayNameHint;

  /// No description provided for @profileDisplayNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a nickname'**
  String get profileDisplayNameRequired;

  /// No description provided for @profileEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmailLabel;

  /// No description provided for @profilePhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get profilePhoneLabel;

  /// No description provided for @profilePhoneHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0912-345-678'**
  String get profilePhoneHint;

  /// No description provided for @profileHandicapLabel.
  ///
  /// In en, this message translates to:
  /// **'Handicap'**
  String get profileHandicapLabel;

  /// No description provided for @profileHandicapHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your current handicap or target'**
  String get profileHandicapHint;

  /// No description provided for @purchaseTestPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'🧪 Purchase Test Panel'**
  String get purchaseTestPanelTitle;

  /// No description provided for @purchaseTestSimulateSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'✅ Simulated purchase successful! User set to premium.'**
  String get purchaseTestSimulateSuccessMsg;

  /// No description provided for @purchaseTestErrorMsg.
  ///
  /// In en, this message translates to:
  /// **'❌ Error: {error}'**
  String purchaseTestErrorMsg(String error);

  /// No description provided for @purchaseTestClearSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'🔄 Purchase record cleared! User is now a regular user.'**
  String get purchaseTestClearSuccessMsg;

  /// No description provided for @purchaseTestPremiumStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Premium status: '**
  String get purchaseTestPremiumStatusLabel;

  /// No description provided for @purchaseTestStatusPurchased.
  ///
  /// In en, this message translates to:
  /// **'✅ Subscribed'**
  String get purchaseTestStatusPurchased;

  /// No description provided for @purchaseTestStatusNotPurchased.
  ///
  /// In en, this message translates to:
  /// **'❌ Not subscribed'**
  String get purchaseTestStatusNotPurchased;

  /// No description provided for @purchaseTestPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method: {method}'**
  String purchaseTestPaymentMethod(String method);

  /// No description provided for @purchaseTestPaymentMethodNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get purchaseTestPaymentMethodNone;

  /// No description provided for @purchaseTestSimulateBtn.
  ///
  /// In en, this message translates to:
  /// **'Simulate Purchase'**
  String get purchaseTestSimulateBtn;

  /// No description provided for @purchaseTestClearBtn.
  ///
  /// In en, this message translates to:
  /// **'Clear Purchase'**
  String get purchaseTestClearBtn;

  /// No description provided for @purchaseTestRefreshBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get purchaseTestRefreshBtn;

  /// No description provided for @purchaseTestDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'🧪 Purchase Function Test'**
  String get purchaseTestDialogTitle;

  /// No description provided for @recDetailDownloadVideo.
  ///
  /// In en, this message translates to:
  /// **'Download video'**
  String get recDetailDownloadVideo;

  /// No description provided for @exportCustomTitle.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportCustomTitle;

  /// No description provided for @exportCustomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose elements to burn into the video'**
  String get exportCustomSubtitle;

  /// No description provided for @exportElementSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton'**
  String get exportElementSkeleton;

  /// No description provided for @exportElementSkeletonDesc.
  ///
  /// In en, this message translates to:
  /// **'Body pose skeleton'**
  String get exportElementSkeletonDesc;

  /// No description provided for @exportElementTrajectory.
  ///
  /// In en, this message translates to:
  /// **'Ball trajectory'**
  String get exportElementTrajectory;

  /// No description provided for @exportElementTrajectoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Ball flight path after impact'**
  String get exportElementTrajectoryDesc;

  /// No description provided for @exportElementGlow.
  ///
  /// In en, this message translates to:
  /// **'Impact glow'**
  String get exportElementGlow;

  /// No description provided for @exportElementGlowDesc.
  ///
  /// In en, this message translates to:
  /// **'Glowing ring at the moment of impact'**
  String get exportElementGlowDesc;

  /// No description provided for @exportElementSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet spot'**
  String get exportElementSweetSpot;

  /// No description provided for @exportElementSweetSpotDesc.
  ///
  /// In en, this message translates to:
  /// **'Quality ring at impact (gold / blue / gray)'**
  String get exportElementSweetSpotDesc;

  /// No description provided for @swingBothHands.
  ///
  /// In en, this message translates to:
  /// **'Two-hand detection'**
  String get swingBothHands;

  /// No description provided for @swingBothHandsDesc.
  ///
  /// In en, this message translates to:
  /// **'Count a swing only when both wrists move together; falls back to one hand if the other is occluded'**
  String get swingBothHandsDesc;

  /// No description provided for @exportNoOverlayMaterial.
  ///
  /// In en, this message translates to:
  /// **'This video has no overlay data; the original will be exported.'**
  String get exportNoOverlayMaterial;

  /// No description provided for @exportWatermarkFree.
  ///
  /// In en, this message translates to:
  /// **'Free exports include an ORVIA watermark — upgrade to remove'**
  String get exportWatermarkFree;

  /// No description provided for @exportWatermarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Subscribed: no watermark'**
  String get exportWatermarkPaid;

  /// No description provided for @exportComposeAndDownload.
  ///
  /// In en, this message translates to:
  /// **'Compose & download'**
  String get exportComposeAndDownload;

  /// No description provided for @recDetailNoVideoFound.
  ///
  /// In en, this message translates to:
  /// **'No downloadable video found'**
  String get recDetailNoVideoFound;

  /// No description provided for @recDetailBurning.
  ///
  /// In en, this message translates to:
  /// **'Rendering \"{label}\"…'**
  String recDetailBurning(String label);

  /// No description provided for @recDetailBurnFailed.
  ///
  /// In en, this message translates to:
  /// **'Rendering failed, please try again later'**
  String get recDetailBurnFailed;

  /// No description provided for @recDetailSavedToDownloads.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" saved to Downloads ✅'**
  String recDetailSavedToDownloads(String label);

  /// No description provided for @recDetailSavedToPhotos.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" saved to Camera Roll ✅'**
  String recDetailSavedToPhotos(String label);

  /// No description provided for @recDetailSharedViaSheet.
  ///
  /// In en, this message translates to:
  /// **'Share sheet opened ✅'**
  String get recDetailSharedViaSheet;

  /// No description provided for @recDetailDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {detail}'**
  String recDetailDownloadFailed(String detail);

  /// No description provided for @recDetailSkeletonPreview.
  ///
  /// In en, this message translates to:
  /// **'Skeleton Preview'**
  String get recDetailSkeletonPreview;

  /// No description provided for @recDetailSkeletonLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load skeleton preview'**
  String get recDetailSkeletonLoadFailed;

  /// No description provided for @recDetailAudioPeak.
  ///
  /// In en, this message translates to:
  /// **'Audio Peak'**
  String get recDetailAudioPeak;

  /// No description provided for @recDetailAudioPeakSubtitle.
  ///
  /// In en, this message translates to:
  /// **'RMS dBFS'**
  String get recDetailAudioPeakSubtitle;

  /// No description provided for @recDetailAudioPeakMissing.
  ///
  /// In en, this message translates to:
  /// **'Audio analysis required'**
  String get recDetailAudioPeakMissing;

  /// No description provided for @recDetailWristY.
  ///
  /// In en, this message translates to:
  /// **'Wrist Y'**
  String get recDetailWristY;

  /// No description provided for @recDetailWristYSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Right wrist Y position (px)'**
  String get recDetailWristYSubtitle;

  /// No description provided for @recDetailPoseMissing.
  ///
  /// In en, this message translates to:
  /// **'Pose analysis required'**
  String get recDetailPoseMissing;

  /// No description provided for @recDetailSpeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wrist movement speed (px/frame)'**
  String get recDetailSpeedSubtitle;

  /// No description provided for @recDetailSpeedMissing.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get recDetailSpeedMissing;

  /// No description provided for @recDetailSweetSpot.
  ///
  /// In en, this message translates to:
  /// **'Sweet Spot'**
  String get recDetailSweetSpot;

  /// No description provided for @recDetailOffCenter.
  ///
  /// In en, this message translates to:
  /// **'Off-Center'**
  String get recDetailOffCenter;

  /// No description provided for @recDetailAudioFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio Feature Analysis'**
  String get recDetailAudioFeaturesTitle;

  /// No description provided for @recDetailFeaturePassCount.
  ///
  /// In en, this message translates to:
  /// **'{count} / 5 features within sweet spot range'**
  String recDetailFeaturePassCount(int count);

  /// No description provided for @recDetailAutoAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Uploading pose analysis, please wait…'**
  String get recDetailAutoAnalyzing;

  /// No description provided for @recDetailOnnxTitle.
  ///
  /// In en, this message translates to:
  /// **'ONNX Posture Analysis'**
  String get recDetailOnnxTitle;

  /// No description provided for @recDetailOnnxLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String recDetailOnnxLoadFailed(String error);

  /// No description provided for @recDetailOnnxNoResult.
  ///
  /// In en, this message translates to:
  /// **'No ONNX result yet'**
  String get recDetailOnnxNoResult;

  /// No description provided for @recDetailOnnxNoScores.
  ///
  /// In en, this message translates to:
  /// **'No score data'**
  String get recDetailOnnxNoScores;

  /// No description provided for @recDetailSwingPhases.
  ///
  /// In en, this message translates to:
  /// **'Swing Phases'**
  String get recDetailSwingPhases;

  /// No description provided for @recDetailRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get recDetailRegenerate;

  /// No description provided for @recDetailGeneratePhases.
  ///
  /// In en, this message translates to:
  /// **'Generate phases'**
  String get recDetailGeneratePhases;

  /// No description provided for @recDetailNoChartData.
  ///
  /// In en, this message translates to:
  /// **'No chart data yet'**
  String get recDetailNoChartData;

  /// No description provided for @recDetailNoChartHint.
  ///
  /// In en, this message translates to:
  /// **'Complete audio analysis and pose analysis first'**
  String get recDetailNoChartHint;

  /// No description provided for @recDetailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed'**
  String get recDetailLoadFailed;

  /// No description provided for @recDetailSelectDownloadVersion.
  ///
  /// In en, this message translates to:
  /// **'Select download version'**
  String get recDetailSelectDownloadVersion;

  /// No description provided for @recDetailOptLabelFull.
  ///
  /// In en, this message translates to:
  /// **'Full Analysis'**
  String get recDetailOptLabelFull;

  /// No description provided for @recDetailOptDescFull.
  ///
  /// In en, this message translates to:
  /// **'Skeleton + ball trajectory'**
  String get recDetailOptDescFull;

  /// No description provided for @recDetailOptLabelSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton only'**
  String get recDetailOptLabelSkeleton;

  /// No description provided for @recDetailOptDescSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton overlay only'**
  String get recDetailOptDescSkeleton;

  /// No description provided for @recDetailOptLabelClip.
  ///
  /// In en, this message translates to:
  /// **'Raw clip'**
  String get recDetailOptLabelClip;

  /// No description provided for @recDetailOptDescNoOverlay.
  ///
  /// In en, this message translates to:
  /// **'No overlays'**
  String get recDetailOptDescNoOverlay;

  /// No description provided for @recDetailOptLabelRaw.
  ///
  /// In en, this message translates to:
  /// **'Original video'**
  String get recDetailOptLabelRaw;

  /// No description provided for @recDetailOptLabelRawMov.
  ///
  /// In en, this message translates to:
  /// **'Original video (MOV)'**
  String get recDetailOptLabelRawMov;

  /// No description provided for @recDetailOptDescRawMov.
  ///
  /// In en, this message translates to:
  /// **'Raw MOV file'**
  String get recDetailOptDescRawMov;

  /// No description provided for @recDetailPhaseAddress.
  ///
  /// In en, this message translates to:
  /// **'①Address'**
  String get recDetailPhaseAddress;

  /// No description provided for @recDetailPhaseTakeaway.
  ///
  /// In en, this message translates to:
  /// **'②Takeaway'**
  String get recDetailPhaseTakeaway;

  /// No description provided for @recDetailPhaseBackswing.
  ///
  /// In en, this message translates to:
  /// **'③Backswing'**
  String get recDetailPhaseBackswing;

  /// No description provided for @recDetailPhaseTop.
  ///
  /// In en, this message translates to:
  /// **'④Top'**
  String get recDetailPhaseTop;

  /// No description provided for @recDetailPhaseDownswing.
  ///
  /// In en, this message translates to:
  /// **'⑤Downswing'**
  String get recDetailPhaseDownswing;

  /// No description provided for @recDetailPhaseImpact.
  ///
  /// In en, this message translates to:
  /// **'⑥Impact'**
  String get recDetailPhaseImpact;

  /// No description provided for @recDetailPhaseFollowthrough.
  ///
  /// In en, this message translates to:
  /// **'⑦Release'**
  String get recDetailPhaseFollowthrough;

  /// No description provided for @recDetailPhaseFinish.
  ///
  /// In en, this message translates to:
  /// **'⑧Finish'**
  String get recDetailPhaseFinish;

  /// No description provided for @recHistSheetEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet. Recordings will appear here automatically after you finish recording.'**
  String get recHistSheetEmptyHint;

  /// No description provided for @recHistSheetPickFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Pick a video from files'**
  String get recHistSheetPickFromFolder;

  /// No description provided for @recHistSheetDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} sec'**
  String recHistSheetDurationSeconds(int count);

  /// No description provided for @recSelPreparingProgress.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get recSelPreparingProgress;

  /// No description provided for @recSelAnalyzingDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Analyzing Video'**
  String get recSelAnalyzingDialogTitle;

  /// No description provided for @recSelNoFileSelected.
  ///
  /// In en, this message translates to:
  /// **'❌ No file selected'**
  String get recSelNoFileSelected;

  /// No description provided for @recSelVideoTooLong.
  ///
  /// In en, this message translates to:
  /// **'❌ Video exceeds 10-minute limit ({durationSec} seconds)\nPlease select a video under 600 seconds'**
  String recSelVideoTooLong(int durationSec);

  /// No description provided for @recSelVideoDurationOk.
  ///
  /// In en, this message translates to:
  /// **'✅ Video duration {durationSec} seconds, within the 10-minute limit'**
  String recSelVideoDurationOk(int durationSec);

  /// No description provided for @recSelImportFailed.
  ///
  /// In en, this message translates to:
  /// **'❌ Import failed\nFile may not exist or format is unsupported'**
  String get recSelImportFailed;

  /// No description provided for @recSelImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'✅ Import successful!\n{name}\nDuration: {duration}'**
  String recSelImportSuccess(String name, String duration);

  /// No description provided for @recSelImportError.
  ///
  /// In en, this message translates to:
  /// **'❌ Import error\n{error}'**
  String recSelImportError(String error);

  /// No description provided for @recSelImportingVideo.
  ///
  /// In en, this message translates to:
  /// **'Importing video...'**
  String get recSelImportingVideo;

  /// No description provided for @recSelDoNotClose.
  ///
  /// In en, this message translates to:
  /// **'Do not close the app'**
  String get recSelDoNotClose;

  /// No description provided for @recSelShotModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Swing Mode'**
  String get recSelShotModeTitle;

  /// No description provided for @recSelShotModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-detects and clips each swing — no long recordings needed'**
  String get recSelShotModeSubtitle;

  /// No description provided for @recSelNewFeatureBadge.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get recSelNewFeatureBadge;

  /// No description provided for @recSelRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get recSelRecordTitle;

  /// No description provided for @recSelRecordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record live and analyze your swing'**
  String get recSelRecordSubtitle;

  /// No description provided for @recSelLocalVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Local Video'**
  String get recSelLocalVideoTitle;

  /// No description provided for @recSelLocalVideoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an existing video from your device (max 10 minutes)'**
  String get recSelLocalVideoSubtitle;

  /// No description provided for @recSelShareLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Get from Share Link'**
  String get recSelShareLinkTitle;

  /// No description provided for @recSelShareLinkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a 16-digit share code to download the video'**
  String get recSelShareLinkSubtitle;

  /// No description provided for @recSelHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Recording Mode'**
  String get recSelHeaderTitle;

  /// No description provided for @recSelHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record live, import a local video, or get one via share code'**
  String get recSelHeaderSubtitle;

  /// No description provided for @recSelIOSSourceSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Video Source'**
  String get recSelIOSSourceSheetTitle;

  /// No description provided for @recSelPhotoLibrary.
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get recSelPhotoLibrary;

  /// No description provided for @recSelFilesApp.
  ///
  /// In en, this message translates to:
  /// **'Files App (Folder)'**
  String get recSelFilesApp;

  /// No description provided for @recTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording History ({count})'**
  String recTabsTitle(int count);

  /// No description provided for @recTabsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recordings'**
  String get recTabsEmpty;

  /// No description provided for @recTabsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Recordings will appear here after you complete a new session'**
  String get recTabsEmptyHint;

  /// No description provided for @recTabsMode.
  ///
  /// In en, this message translates to:
  /// **'Mode: {label}'**
  String recTabsMode(String label);

  /// No description provided for @recTabsDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration: {seconds}s'**
  String recTabsDuration(int seconds);

  /// No description provided for @recordTitle.
  ///
  /// In en, this message translates to:
  /// **'Golf Swing Recording'**
  String get recordTitle;

  /// No description provided for @recordOverlayToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle outline overlay'**
  String get recordOverlayToggle;

  /// No description provided for @recTapSetImpactPoint.
  ///
  /// In en, this message translates to:
  /// **'Tap to set impact point'**
  String get recTapSetImpactPoint;

  /// No description provided for @recSwingSpeed.
  ///
  /// In en, this message translates to:
  /// **'Swing speed threshold'**
  String get recSwingSpeed;

  /// No description provided for @recShowTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Show wrist values (debug)'**
  String get recShowTelemetry;

  /// No description provided for @recAnchorRadius.
  ///
  /// In en, this message translates to:
  /// **'Anchor hit radius (smaller = stricter)'**
  String get recAnchorRadius;

  /// No description provided for @recAnchorGate.
  ///
  /// In en, this message translates to:
  /// **'Anchor detection gate'**
  String get recAnchorGate;

  /// No description provided for @recAnchorGateDesc.
  ///
  /// In en, this message translates to:
  /// **'Only count a swing if the wrist passes within the anchor radius; random/off-target swings are ignored.'**
  String get recAnchorGateDesc;

  /// No description provided for @recUseAnchor.
  ///
  /// In en, this message translates to:
  /// **'Anchor impact (V4)'**
  String get recUseAnchor;

  /// No description provided for @recUseAnchorDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the tapped ball spot as the impact point; off keeps the spot but falls back to wrist arc-bottom'**
  String get recUseAnchorDesc;

  /// No description provided for @recGlowDelay.
  ///
  /// In en, this message translates to:
  /// **'Impact glow delay'**
  String get recGlowDelay;

  /// No description provided for @recordSettings.
  ///
  /// In en, this message translates to:
  /// **'Recording settings'**
  String get recordSettings;

  /// No description provided for @recordPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera & Microphone Permission Required'**
  String get recordPermissionTitle;

  /// No description provided for @recordPermissionMicOnly.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to record impact sounds. Please grant access and try again.'**
  String get recordPermissionMicOnly;

  /// No description provided for @recordPermissionCameraAndMic.
  ///
  /// In en, this message translates to:
  /// **'Camera and microphone permissions are required for swing recording. Please grant access and try again.'**
  String get recordPermissionCameraAndMic;

  /// No description provided for @recordGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get recordGoToSettings;

  /// No description provided for @recordGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get recordGotIt;

  /// No description provided for @recordLowEndDeviceWarning.
  ///
  /// In en, this message translates to:
  /// **'This device does not support real-time skeleton detection during recording. Detection will resume after recording stops.'**
  String get recordLowEndDeviceWarning;

  /// No description provided for @recordFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording failed (no valid frames captured). Please try again.'**
  String get recordFailed;

  /// No description provided for @recordVideoQuality.
  ///
  /// In en, this message translates to:
  /// **'Video Quality'**
  String get recordVideoQuality;

  /// No description provided for @recordFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame Rate'**
  String get recordFrameRate;

  /// No description provided for @recordAudio.
  ///
  /// In en, this message translates to:
  /// **'Record Audio'**
  String get recordAudio;

  /// No description provided for @recordApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get recordApply;

  /// No description provided for @rewardTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward Balls'**
  String get rewardTitle;

  /// No description provided for @rewardUsageHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Usage History'**
  String get rewardUsageHistoryTooltip;

  /// No description provided for @rewardEarnedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Earned +{balls} balls via \"{source}\"!'**
  String rewardEarnedSnackbar(String source, int balls);

  /// No description provided for @rewardUploadSubmittedPending.
  ///
  /// In en, this message translates to:
  /// **'Submitted {pending} item(s) for review. Balls will be awarded after approval.'**
  String rewardUploadSubmittedPending(int pending);

  /// No description provided for @rewardUploadSubmittedDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Data submitted (duplicate data will not be re-reviewed).'**
  String get rewardUploadSubmittedDuplicate;

  /// No description provided for @rewardStatBonusBalls.
  ///
  /// In en, this message translates to:
  /// **'Total Rewards'**
  String get rewardStatBonusBalls;

  /// No description provided for @rewardUnitBall.
  ///
  /// In en, this message translates to:
  /// **'balls'**
  String get rewardUnitBall;

  /// No description provided for @rewardStatAdToday.
  ///
  /// In en, this message translates to:
  /// **'Ads Today'**
  String get rewardStatAdToday;

  /// No description provided for @rewardAdDailyUnit.
  ///
  /// In en, this message translates to:
  /// **'/ 5 times'**
  String get rewardAdDailyUnit;

  /// No description provided for @rewardStatInvites.
  ///
  /// In en, this message translates to:
  /// **'Friends Invited'**
  String get rewardStatInvites;

  /// No description provided for @rewardUnitPerson.
  ///
  /// In en, this message translates to:
  /// **'friends'**
  String get rewardUnitPerson;

  /// No description provided for @rewardBallsBadge.
  ///
  /// In en, this message translates to:
  /// **'+{balls} balls'**
  String rewardBallsBadge(int balls);

  /// No description provided for @rewardAdProgress.
  ///
  /// In en, this message translates to:
  /// **'{used} / {cap} times'**
  String rewardAdProgress(int used, int cap);

  /// No description provided for @rewardDoneToday.
  ///
  /// In en, this message translates to:
  /// **'Completed Today'**
  String get rewardDoneToday;

  /// No description provided for @rewardAdNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Ad not fully watched or temporarily unavailable. Please try again later.'**
  String get rewardAdNotCompleted;

  /// No description provided for @rewardAdFailed.
  ///
  /// In en, this message translates to:
  /// **'Ad reward failed: {error}'**
  String rewardAdFailed(String error);

  /// No description provided for @rewardWatchAdTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch Ad'**
  String get rewardWatchAdTitle;

  /// No description provided for @rewardWatchAdButton.
  ///
  /// In en, this message translates to:
  /// **'Watch Ad +{balls} balls'**
  String rewardWatchAdButton(int balls);

  /// No description provided for @rewardInviteFriendTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get rewardInviteFriendTitle;

  /// No description provided for @rewardInviteFriendDesc.
  ///
  /// In en, this message translates to:
  /// **'When a friend registers with your invite code, you both get +{balls} balls.'**
  String rewardInviteFriendDesc(int balls);

  /// No description provided for @rewardGetInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Get Invite Code'**
  String get rewardGetInviteCode;

  /// No description provided for @rewardYourInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Your Invite Code'**
  String get rewardYourInviteCode;

  /// No description provided for @rewardInviteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied'**
  String get rewardInviteCodeCopied;

  /// No description provided for @rewardInvitedFriends.
  ///
  /// In en, this message translates to:
  /// **'Invited Friends'**
  String get rewardInvitedFriends;

  /// No description provided for @rewardNoInviteHistory.
  ///
  /// In en, this message translates to:
  /// **'No invitations yet'**
  String get rewardNoInviteHistory;

  /// No description provided for @rewardShareInviteHint.
  ///
  /// In en, this message translates to:
  /// **'Share your invite code and practice together!'**
  String get rewardShareInviteHint;

  /// No description provided for @rewardEnterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Invite Code'**
  String get rewardEnterCodeTitle;

  /// No description provided for @rewardEnterCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter a friend\'s invite code — you both get +{balls} balls.'**
  String rewardEnterCodeDesc(int balls);

  /// No description provided for @rewardEnterCodeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter an invite code'**
  String get rewardEnterCodeEmpty;

  /// No description provided for @rewardInviteCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid invite code'**
  String get rewardInviteCodeInvalid;

  /// No description provided for @rewardApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Apply failed: {error}'**
  String rewardApplyFailed(String error);

  /// No description provided for @rewardApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying...'**
  String get rewardApplying;

  /// No description provided for @rewardApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply +{balls} balls'**
  String rewardApplyButton(int balls);

  /// No description provided for @rewardEnterFriendCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Friend\'s Invite Code'**
  String get rewardEnterFriendCode;

  /// No description provided for @rewardFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback'**
  String get rewardFeedbackTitle;

  /// No description provided for @rewardFeedbackTypeBug.
  ///
  /// In en, this message translates to:
  /// **'🐛 Bug Report'**
  String get rewardFeedbackTypeBug;

  /// No description provided for @rewardFeedbackTypeFeature.
  ///
  /// In en, this message translates to:
  /// **'💡 Feature Request'**
  String get rewardFeedbackTypeFeature;

  /// No description provided for @rewardFeedbackTypeOther.
  ///
  /// In en, this message translates to:
  /// **'💬 Other'**
  String get rewardFeedbackTypeOther;

  /// No description provided for @rewardFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Please describe your feedback in detail...'**
  String get rewardFeedbackHint;

  /// No description provided for @rewardSelectVideo.
  ///
  /// In en, this message translates to:
  /// **'Select Video'**
  String get rewardSelectVideo;

  /// No description provided for @rewardChangeVideo.
  ///
  /// In en, this message translates to:
  /// **'Change Video'**
  String get rewardChangeVideo;

  /// No description provided for @rewardUploadImage.
  ///
  /// In en, this message translates to:
  /// **'Upload Image'**
  String get rewardUploadImage;

  /// No description provided for @rewardChangeImage.
  ///
  /// In en, this message translates to:
  /// **'Change Image'**
  String get rewardChangeImage;

  /// No description provided for @rewardFeedbackEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your feedback'**
  String get rewardFeedbackEmpty;

  /// No description provided for @rewardFeedbackSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Feedback submitted. Thank you for your input!'**
  String get rewardFeedbackSubmitted;

  /// No description provided for @rewardSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed: {error}'**
  String rewardSubmitFailed(String error);

  /// No description provided for @rewardSubmitFeedback.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback'**
  String get rewardSubmitFeedback;

  /// No description provided for @rewardSubmitFeedbackWithBalls.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback +{balls} balls'**
  String rewardSubmitFeedbackWithBalls(int balls);

  /// No description provided for @rewardWriteFeedback.
  ///
  /// In en, this message translates to:
  /// **'Write Feedback'**
  String get rewardWriteFeedback;

  /// No description provided for @rewardWriteFeedbackWithBalls.
  ///
  /// In en, this message translates to:
  /// **'Write Feedback +{balls} balls'**
  String rewardWriteFeedbackWithBalls(int balls);

  /// No description provided for @rewardNoVideoHistory.
  ///
  /// In en, this message translates to:
  /// **'No recorded videos yet'**
  String get rewardNoVideoHistory;

  /// No description provided for @rewardLongVideo.
  ///
  /// In en, this message translates to:
  /// **'Long video'**
  String get rewardLongVideo;

  /// No description provided for @rewardShortVideo.
  ///
  /// In en, this message translates to:
  /// **'Short video'**
  String get rewardShortVideo;

  /// No description provided for @rewardUploadDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload Analysis Data'**
  String get rewardUploadDataTitle;

  /// No description provided for @rewardNoUploadable.
  ///
  /// In en, this message translates to:
  /// **'No analysis data available to upload'**
  String get rewardNoUploadable;

  /// No description provided for @rewardUploadPartialFail.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) failed to upload and were skipped'**
  String rewardUploadPartialFail(int count);

  /// No description provided for @rewardUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed. Please try again later.'**
  String get rewardUploadFailed;

  /// No description provided for @rewardUploadResubmitBlocked.
  ///
  /// In en, this message translates to:
  /// **'Review submission failed: data may have been submitted already (rejected items cannot be resubmitted), or there was a network error — please try again.'**
  String get rewardUploadResubmitBlocked;

  /// No description provided for @rewardUploadError.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String rewardUploadError(String error);

  /// No description provided for @rewardUploadAvailableCount.
  ///
  /// In en, this message translates to:
  /// **'{available} item(s) available to upload, {uploaded} already uploaded'**
  String rewardUploadAvailableCount(int available, int uploaded);

  /// No description provided for @rewardUploadAllDone.
  ///
  /// In en, this message translates to:
  /// **'All analysis data uploaded ({count} total)'**
  String rewardUploadAllDone(int count);

  /// No description provided for @rewardUploadReviewStatus.
  ///
  /// In en, this message translates to:
  /// **'Under review: {pending} / Approved: {approved}'**
  String rewardUploadReviewStatus(int pending, int approved);

  /// No description provided for @rewardUploadRejectedSuffix.
  ///
  /// In en, this message translates to:
  /// **' / Rejected: {count}'**
  String rewardUploadRejectedSuffix(int count);

  /// No description provided for @rewardUploadRejectedNote.
  ///
  /// In en, this message translates to:
  /// **'Rejected items cannot be resubmitted'**
  String get rewardUploadRejectedNote;

  /// No description provided for @rewardSelectUploadVideo.
  ///
  /// In en, this message translates to:
  /// **'Select Recording to Upload'**
  String get rewardSelectUploadVideo;

  /// No description provided for @rewardSelectUploadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select one and tap \"Confirm Upload\" to earn rewards'**
  String get rewardSelectUploadSubtitle;

  /// No description provided for @rewardNoneSelected.
  ///
  /// In en, this message translates to:
  /// **'None selected'**
  String get rewardNoneSelected;

  /// No description provided for @rewardOneSelected.
  ///
  /// In en, this message translates to:
  /// **'1 selected'**
  String get rewardOneSelected;

  /// No description provided for @rewardConfirmUpload.
  ///
  /// In en, this message translates to:
  /// **'Confirm Upload +{balls} balls'**
  String rewardConfirmUpload(int balls);

  /// No description provided for @rewardAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Analyzed'**
  String get rewardAnalyzed;

  /// No description provided for @rewardDurationSec.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String rewardDurationSec(int seconds);

  /// No description provided for @settingsNameSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Name updated, but server sync failed'**
  String get settingsNameSyncFailed;

  /// No description provided for @settingsGoogleCredentialFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to retrieve Google credentials, please try again'**
  String get settingsGoogleCredentialFailed;

  /// No description provided for @settingsGoogleLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Google account linking failed, please try again later'**
  String get settingsGoogleLinkFailed;

  /// No description provided for @shareImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Share Link'**
  String get shareImportTitle;

  /// No description provided for @shareImportEnterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter 16-digit Share Code'**
  String get shareImportEnterCodeTitle;

  /// No description provided for @shareImportEnterCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Once someone shares a video, enter the code to download it to your device'**
  String get shareImportEnterCodeDesc;

  /// No description provided for @shareImportCodeValidator.
  ///
  /// In en, this message translates to:
  /// **'Please enter the complete 16-digit share code'**
  String get shareImportCodeValidator;

  /// No description provided for @shareImportLooking.
  ///
  /// In en, this message translates to:
  /// **'Looking up…'**
  String get shareImportLooking;

  /// No description provided for @shareImportLookup.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get shareImportLookup;

  /// No description provided for @shareImportFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get shareImportFrom;

  /// No description provided for @shareImportSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get shareImportSize;

  /// No description provided for @shareImportExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get shareImportExpiry;

  /// No description provided for @shareImportReenter.
  ///
  /// In en, this message translates to:
  /// **'Re-enter Code'**
  String get shareImportReenter;

  /// No description provided for @shareImportDownload.
  ///
  /// In en, this message translates to:
  /// **'Download to Device'**
  String get shareImportDownload;

  /// No description provided for @shareImportPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing download…'**
  String get shareImportPreparing;

  /// No description provided for @shareImportDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get shareImportDownloading;

  /// No description provided for @shareImportExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get shareImportExtracting;

  /// No description provided for @shareImportDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Complete!'**
  String get shareImportDoneTitle;

  /// No description provided for @shareImportDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Video has been added to history'**
  String get shareImportDoneDesc;

  /// No description provided for @shareImportBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get shareImportBack;

  /// No description provided for @shareUploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Link'**
  String get shareUploadTitle;

  /// No description provided for @shareUploadChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking share status…'**
  String get shareUploadChecking;

  /// No description provided for @shareUploadCompressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing…'**
  String get shareUploadCompressing;

  /// No description provided for @shareUploadUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get shareUploadUnknownError;

  /// No description provided for @shareUploadUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…  {percent}%'**
  String shareUploadUploading(String percent);

  /// No description provided for @shareUploadCodeReused.
  ///
  /// In en, this message translates to:
  /// **'Existing share code (not yet expired)'**
  String get shareUploadCodeReused;

  /// No description provided for @shareUploadCodeNew.
  ///
  /// In en, this message translates to:
  /// **'Share code (valid for 1 day)'**
  String get shareUploadCodeNew;

  /// No description provided for @shareUploadCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shareUploadCopy;

  /// No description provided for @shareUploadCopied.
  ///
  /// In en, this message translates to:
  /// **'Share code copied'**
  String get shareUploadCopied;

  /// No description provided for @shareUploadShareText.
  ///
  /// In en, this message translates to:
  /// **'Golf swing share code: {code}\n(Valid for 1 day — enter this code in the app to get the video)'**
  String shareUploadShareText(String code);

  /// No description provided for @shareUploadSystemShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareUploadSystemShare;

  /// No description provided for @shotRecTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Swing Mode'**
  String get shotRecTitle;

  /// No description provided for @shotRecSettings.
  ///
  /// In en, this message translates to:
  /// **'Recording Settings'**
  String get shotRecSettings;

  /// No description provided for @shotRecShotsCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed {count} shots'**
  String shotRecShotsCompleted(int count);

  /// No description provided for @shotRecReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get shotRecReady;

  /// No description provided for @shotRecCalibrating.
  ///
  /// In en, this message translates to:
  /// **'Calibrating… Stay still'**
  String get shotRecCalibrating;

  /// No description provided for @shotRecAddressPrompt.
  ///
  /// In en, this message translates to:
  /// **'Take address position ({current}/{total})'**
  String shotRecAddressPrompt(int current, int total);

  /// No description provided for @shotRecAddressSubText.
  ///
  /// In en, this message translates to:
  /// **'Recording starts automatically when stance is confirmed'**
  String get shotRecAddressSubText;

  /// No description provided for @shotRecDetecting.
  ///
  /// In en, this message translates to:
  /// **'⚡ Detecting… Swing now'**
  String get shotRecDetecting;

  /// No description provided for @shotRecStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get shotRecStop;

  /// No description provided for @shotRecSwingDetected.
  ///
  /// In en, this message translates to:
  /// **'Swing detected ✓\nCountdown {seconds}s'**
  String shotRecSwingDetected(String seconds);

  /// No description provided for @shotRecAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get shotRecAnalyzing;

  /// No description provided for @shotRecExtractingAudio.
  ///
  /// In en, this message translates to:
  /// **'Extracting audio…'**
  String get shotRecExtractingAudio;

  /// No description provided for @shotRecDetectingImpact.
  ///
  /// In en, this message translates to:
  /// **'Detecting impact…'**
  String get shotRecDetectingImpact;

  /// No description provided for @shotRecClipping.
  ///
  /// In en, this message translates to:
  /// **'Clipping…'**
  String get shotRecClipping;

  /// No description provided for @shotRecScoringAudio.
  ///
  /// In en, this message translates to:
  /// **'Scoring audio…'**
  String get shotRecScoringAudio;

  /// No description provided for @shotRecDone.
  ///
  /// In en, this message translates to:
  /// **'Done!'**
  String get shotRecDone;

  /// No description provided for @shotRecWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get shotRecWatch;

  /// No description provided for @shotRecNextShot.
  ///
  /// In en, this message translates to:
  /// **'Next shot ({countdown})'**
  String shotRecNextShot(int countdown);

  /// No description provided for @shotRecVideoQuality.
  ///
  /// In en, this message translates to:
  /// **'Video Quality'**
  String get shotRecVideoQuality;

  /// No description provided for @shotRecFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame Rate'**
  String get shotRecFrameRate;

  /// No description provided for @shotRecEnableAudio.
  ///
  /// In en, this message translates to:
  /// **'Record Audio'**
  String get shotRecEnableAudio;

  /// No description provided for @shotRecApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get shotRecApply;

  /// No description provided for @shotRecAddressTimeout.
  ///
  /// In en, this message translates to:
  /// **'Address posture not detected, cancelled'**
  String get shotRecAddressTimeout;

  /// No description provided for @shotRecNoAnalysisWarning.
  ///
  /// In en, this message translates to:
  /// **'This device does not support skeleton detection during recording. Swing detection will still work automatically.'**
  String get shotRecNoAnalysisWarning;

  /// No description provided for @shotRecRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording failed (no valid video captured), please try again'**
  String get shotRecRecordFailed;

  /// No description provided for @shotRecNoSwingDetected.
  ///
  /// In en, this message translates to:
  /// **'No swing detected, please try again'**
  String get shotRecNoSwingDetected;

  /// No description provided for @shotRecClipFailed.
  ///
  /// In en, this message translates to:
  /// **'Clipping failed, please try again'**
  String get shotRecClipFailed;

  /// No description provided for @shotRecLiveShotName.
  ///
  /// In en, this message translates to:
  /// **'Live Shot {number}'**
  String shotRecLiveShotName(int number);

  /// No description provided for @termsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service & Privacy Policy'**
  String get termsPageSubtitle;

  /// No description provided for @termsReadPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please read the terms below, then check the box to agree and get started'**
  String get termsReadPrompt;

  /// No description provided for @termsScrolledToBottom.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the end of the terms. Please scroll back to the top to check the agreement box.'**
  String get termsScrolledToBottom;

  /// No description provided for @termsDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Exit'**
  String get termsDeclineTitle;

  /// No description provided for @termsDeclineContent.
  ///
  /// In en, this message translates to:
  /// **'You cannot use ORVIA without agreeing to the Terms of Service. Are you sure you want to exit?'**
  String get termsDeclineContent;

  /// No description provided for @termsDeclineBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get termsDeclineBack;

  /// No description provided for @termsDeclineExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get termsDeclineExit;

  /// No description provided for @termsPrivacyOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the Privacy Policy page. Please try again later.'**
  String get termsPrivacyOpenFailed;

  /// No description provided for @termsAgreePrefix.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to the Terms of Service and the '**
  String get termsAgreePrefix;

  /// No description provided for @termsPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get termsPrivacyLink;

  /// No description provided for @termsAgreeSuffix.
  ///
  /// In en, this message translates to:
  /// **'》'**
  String get termsAgreeSuffix;

  /// No description provided for @termsAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow usage analytics (optional)'**
  String get termsAnalyticsTitle;

  /// No description provided for @termsAnalyticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Helps us improve the app experience. No personally identifiable information is included.'**
  String get termsAnalyticsDesc;

  /// No description provided for @termsScrollFirst.
  ///
  /// In en, this message translates to:
  /// **'Please scroll through the full terms before checking the agreement box'**
  String get termsScrollFirst;

  /// No description provided for @termsDisagree.
  ///
  /// In en, this message translates to:
  /// **'Disagree'**
  String get termsDisagree;

  /// No description provided for @termsAgreeAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree & Continue'**
  String get termsAgreeAndContinue;

  /// No description provided for @termsOpenPrivacyFull.
  ///
  /// In en, this message translates to:
  /// **'Open Full Privacy Policy'**
  String get termsOpenPrivacyFull;

  /// No description provided for @termsSec1Title.
  ///
  /// In en, this message translates to:
  /// **'1. Service Description'**
  String get termsSec1Title;

  /// No description provided for @termsSec1Body.
  ///
  /// In en, this message translates to:
  /// **'ORVIA (hereinafter \"the Service\") is provided by the ORVIA team to help users record and analyze golf swing motions via mobile devices, and to provide related data statistics and recommendations.\n\nBefore using the Service, please read the following terms carefully. By starting to use the Service, you acknowledge that you have read, understood, and agreed to all content of these terms.'**
  String get termsSec1Body;

  /// No description provided for @termsSec2Title.
  ///
  /// In en, this message translates to:
  /// **'2. Account & Security'**
  String get termsSec2Title;

  /// No description provided for @termsSec2Body.
  ///
  /// In en, this message translates to:
  /// **'1. You must register via email or a Google account to access full features.\n2. You are responsible for keeping your account credentials secure and for all activities conducted under your account.\n3. If you discover unauthorized use of your account, please notify us immediately.\n4. You may not transfer your account to another person.'**
  String get termsSec2Body;

  /// No description provided for @termsSec3Title.
  ///
  /// In en, this message translates to:
  /// **'3. User Conduct'**
  String get termsSec3Title;

  /// No description provided for @termsSec3Body.
  ///
  /// In en, this message translates to:
  /// **'By using the Service, you agree to:\n\n1. Only upload video content that you personally filmed or hold legitimate authorization for.\n2. Not upload any illegal, infringing, or inappropriate content.\n3. Not interfere with or disrupt the normal operation of the Service.\n4. Not attempt unauthorized access to the Service\'s systems or data.'**
  String get termsSec3Body;

  /// No description provided for @termsSec4Title.
  ///
  /// In en, this message translates to:
  /// **'4. Video & Data Processing'**
  String get termsSec4Title;

  /// No description provided for @termsSec4Body.
  ///
  /// In en, this message translates to:
  /// **'1. Videos and analysis data you upload will be stored in the Service\'s cloud system to provide swing analysis.\n2. Share links generated by the sharing feature are valid for 1 day; related files will be automatically deleted after expiry.\n3. You may delete your personal data and recording history from within the app at any time.\n4. We will not provide your personal videos to unauthorized third parties.'**
  String get termsSec4Body;

  /// No description provided for @termsSec5Title.
  ///
  /// In en, this message translates to:
  /// **'5. Privacy Policy'**
  String get termsSec5Title;

  /// No description provided for @termsSec5Body.
  ///
  /// In en, this message translates to:
  /// **'We value your privacy and collect and use your information according to the following principles:\n\nInformation collected:\n• Account information (email, display name)\n• Swing videos and analysis results\n• Device information and usage records\n\nUsage analytics (with your consent):\n• We may collect anonymous usage data (feature clicks, page views, etc.)\n• Used to improve the app experience and feature design\n• Does not include personally identifiable information; can be turned off in Settings at any time\n\nData protection:\n• All data transmissions use TLS encryption\n• Server-side data is encrypted at rest\n• Regular security audits are conducted\n\nFull privacy policy: https://orvia.atk.tw/privacy.html'**
  String get termsSec5Body;

  /// No description provided for @termsSec6Title.
  ///
  /// In en, this message translates to:
  /// **'6. Intellectual Property'**
  String get termsSec6Title;

  /// No description provided for @termsSec6Body.
  ///
  /// In en, this message translates to:
  /// **'1. The software, interface design, trademarks, and all related content of the Service are owned by ORVIA and protected by copyright law.\n2. The copyright of videos you upload belongs to you; however, you grant the Service a limited license to use that content to provide analysis services.\n3. Without authorization, you may not reproduce, modify, or distribute any part of the Service.'**
  String get termsSec6Body;

  /// No description provided for @termsSec7Title.
  ///
  /// In en, this message translates to:
  /// **'7. Disclaimer'**
  String get termsSec7Title;

  /// No description provided for @termsSec7Body.
  ///
  /// In en, this message translates to:
  /// **'1. Swing analysis results provided by the Service are for reference only and do not constitute professional sports coaching advice.\n2. The Service is provided \"as is\" and does not guarantee uninterrupted or error-free operation.\n3. The Service is not liable for any direct or indirect losses arising from the use of the Service.\n4. Swing practice involves physical activity; please practice in a safe environment and assess your own physical condition.'**
  String get termsSec7Body;

  /// No description provided for @termsSec8Title.
  ///
  /// In en, this message translates to:
  /// **'8. Service Changes & Termination'**
  String get termsSec8Title;

  /// No description provided for @termsSec8Body.
  ///
  /// In en, this message translates to:
  /// **'1. We reserve the right to modify, suspend, or terminate the Service at any time.\n2. If there are significant changes to these terms, we will notify you via the app.\n3. Continued use of the Service constitutes acceptance of the updated terms.'**
  String get termsSec8Body;

  /// No description provided for @termsSec9Title.
  ///
  /// In en, this message translates to:
  /// **'9. Contact Us'**
  String get termsSec9Title;

  /// No description provided for @termsSec9Body.
  ///
  /// In en, this message translates to:
  /// **'If you have any questions about these terms, please contact us via:\n\nEmail: support@atk.tw\nWebsite: https://orvia.atk.tw\nPrivacy Policy: https://orvia.atk.tw/privacy.html\n\nThese terms were last updated: May 25, 2026'**
  String get termsSec9Body;

  /// No description provided for @testVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Test Video'**
  String get testVideoTitle;

  /// No description provided for @testVideoLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load videos\n{error}'**
  String testVideoLoadError(String error);

  /// No description provided for @testVideoEmpty.
  ///
  /// In en, this message translates to:
  /// **'No imported videos yet'**
  String get testVideoEmpty;

  /// No description provided for @testVideoSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get testVideoSelect;

  /// No description provided for @testVideoHint.
  ///
  /// In en, this message translates to:
  /// **'💡 Tip: Select a video as the test recording for demo and analysis testing'**
  String get testVideoHint;

  /// No description provided for @upgradeSubscribed.
  ///
  /// In en, this message translates to:
  /// **'Subscribed'**
  String get upgradeSubscribed;

  /// No description provided for @upgradeCurrentPlanActive.
  ///
  /// In en, this message translates to:
  /// **'Current Plan'**
  String get upgradeCurrentPlanActive;

  /// No description provided for @upgradeMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get upgradeMonthly;

  /// No description provided for @upgradeYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly (save ~2 months)'**
  String get upgradeYearly;

  /// No description provided for @upgradeSubscribeFailed.
  ///
  /// In en, this message translates to:
  /// **'Subscription failed: {error}'**
  String upgradeSubscribeFailed(String error);

  /// No description provided for @upgradeProductLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load product, please try again later'**
  String get upgradeProductLoadFailed;

  /// No description provided for @upgradeAppStoreSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe on App Store'**
  String get upgradeAppStoreSubscribe;

  /// No description provided for @upgradeGooglePlaySubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe on Google Play'**
  String get upgradeGooglePlaySubscribe;

  /// No description provided for @upgradeManageSubscriptionIos.
  ///
  /// In en, this message translates to:
  /// **'You can manage or cancel your subscription anytime in App Store'**
  String get upgradeManageSubscriptionIos;

  /// No description provided for @upgradeManageSubscriptionAndroid.
  ///
  /// In en, this message translates to:
  /// **'You can manage or cancel your subscription anytime in Google Play'**
  String get upgradeManageSubscriptionAndroid;

  /// No description provided for @upgradeBuyBalls.
  ///
  /// In en, this message translates to:
  /// **'Buy Balls'**
  String get upgradeBuyBalls;

  /// No description provided for @upgradeNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get upgradeNoExpiry;

  /// No description provided for @upgradeBallCount.
  ///
  /// In en, this message translates to:
  /// **'{count} balls'**
  String upgradeBallCount(int count);

  /// No description provided for @upgradeBallPackValidity.
  ///
  /// In en, this message translates to:
  /// **'Never expires, use anytime'**
  String get upgradeBallPackValidity;

  /// No description provided for @upgradeBuyButton.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get upgradeBuyButton;

  /// No description provided for @upgradePurchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed: {error}'**
  String upgradePurchaseFailed(String error);

  /// No description provided for @upgradeBuyBallCount.
  ///
  /// In en, this message translates to:
  /// **'Buy {count} balls'**
  String upgradeBuyBallCount(int count);

  /// No description provided for @upgradeBallPackDescription.
  ///
  /// In en, this message translates to:
  /// **'Balls never expire and have no time limit. Used automatically when your daily quota runs out.'**
  String get upgradeBallPackDescription;

  /// No description provided for @upgradeAppStorePurchase.
  ///
  /// In en, this message translates to:
  /// **'Buy on App Store'**
  String get upgradeAppStorePurchase;

  /// No description provided for @upgradeGooglePlayPurchase.
  ///
  /// In en, this message translates to:
  /// **'Buy on Google Play'**
  String get upgradeGooglePlayPurchase;

  /// No description provided for @usageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage History'**
  String get usageTitle;

  /// No description provided for @usageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis & Ball Ledger'**
  String get usageSubtitle;

  /// No description provided for @usageTabAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get usageTabAnalysis;

  /// No description provided for @usageTabBalls.
  ///
  /// In en, this message translates to:
  /// **'Ball Ledger'**
  String get usageTabBalls;

  /// No description provided for @usageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load. Pull down to retry.'**
  String get usageLoadFailed;

  /// No description provided for @usageLoadError.
  ///
  /// In en, this message translates to:
  /// **'Load error: {error}'**
  String usageLoadError(String error);

  /// No description provided for @usageEmptyAnalysis.
  ///
  /// In en, this message translates to:
  /// **'No analysis records yet'**
  String get usageEmptyAnalysis;

  /// No description provided for @usageAllLoaded.
  ///
  /// In en, this message translates to:
  /// **'All records loaded'**
  String get usageAllLoaded;

  /// No description provided for @usageSummaryTotalAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Total Analyses'**
  String get usageSummaryTotalAnalysis;

  /// No description provided for @usageUnitTimes.
  ///
  /// In en, this message translates to:
  /// **'times'**
  String get usageUnitTimes;

  /// No description provided for @usageSummaryTodayUsed.
  ///
  /// In en, this message translates to:
  /// **'Used Today'**
  String get usageSummaryTodayUsed;

  /// No description provided for @usageAnalysisItemTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Swing Analysis'**
  String get usageAnalysisItemTitle;

  /// No description provided for @usageSourceDailyQuota.
  ///
  /// In en, this message translates to:
  /// **'Daily Quota'**
  String get usageSourceDailyQuota;

  /// No description provided for @usageSourceBonusBall.
  ///
  /// In en, this message translates to:
  /// **'Bonus Ball'**
  String get usageSourceBonusBall;

  /// No description provided for @usageSourceDailyQuotaDesc.
  ///
  /// In en, this message translates to:
  /// **'Used daily quota'**
  String get usageSourceDailyQuotaDesc;

  /// No description provided for @usageSourceBonusBallDesc.
  ///
  /// In en, this message translates to:
  /// **'Consumed 1 ball'**
  String get usageSourceBonusBallDesc;

  /// No description provided for @usageEmptyBalls.
  ///
  /// In en, this message translates to:
  /// **'No ball records yet'**
  String get usageEmptyBalls;

  /// No description provided for @usageSummaryTotalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total Records'**
  String get usageSummaryTotalRecords;

  /// No description provided for @usageUnitRecords.
  ///
  /// In en, this message translates to:
  /// **'records'**
  String get usageUnitRecords;

  /// No description provided for @usageSummaryCurrentBalls.
  ///
  /// In en, this message translates to:
  /// **'Current Balls'**
  String get usageSummaryCurrentBalls;

  /// No description provided for @usageUnitBalls.
  ///
  /// In en, this message translates to:
  /// **'balls'**
  String get usageUnitBalls;

  /// No description provided for @usageBallBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {balance} balls'**
  String usageBallBalance(int balance);

  /// No description provided for @usageDateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get usageDateToday;

  /// No description provided for @usageDateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get usageDateYesterday;

  /// No description provided for @waveformCrispScore.
  ///
  /// In en, this message translates to:
  /// **'Crispness {score}'**
  String waveformCrispScore(int score);

  /// No description provided for @waveformPeakLabel.
  ///
  /// In en, this message translates to:
  /// **'Peak {level}'**
  String waveformPeakLabel(String level);

  /// No description provided for @extImportProgressCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying video...'**
  String get extImportProgressCopying;

  /// No description provided for @extImportProgressTranscoding.
  ///
  /// In en, this message translates to:
  /// **'Preparing transcode...'**
  String get extImportProgressTranscoding;

  /// No description provided for @extImportProgressDurationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Video duration invalid (must be 1–600 seconds)'**
  String get extImportProgressDurationInvalid;

  /// No description provided for @extImportProgressThumbnail.
  ///
  /// In en, this message translates to:
  /// **'Generating thumbnail...'**
  String get extImportProgressThumbnail;

  /// No description provided for @extImportProgressDone.
  ///
  /// In en, this message translates to:
  /// **'Import complete ✅'**
  String get extImportProgressDone;

  /// No description provided for @learnHubGoodSwingTitle.
  ///
  /// In en, this message translates to:
  /// **'Good Swing Demo'**
  String get learnHubGoodSwingTitle;

  /// No description provided for @learnHubGoodSwingDesc.
  ///
  /// In en, this message translates to:
  /// **'Smooth tempo, stable weight shift, complete follow-through after impact.'**
  String get learnHubGoodSwingDesc;

  /// No description provided for @learnHubEarlyReleaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Common Error: Early Release'**
  String get learnHubEarlyReleaseTitle;

  /// No description provided for @learnHubEarlyReleaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Wrists release too early, resulting in insufficient clubhead acceleration and a weak or right-curving shot.'**
  String get learnHubEarlyReleaseDesc;

  /// No description provided for @learnHubMarkerBackswingTop.
  ///
  /// In en, this message translates to:
  /// **'Top of Backswing'**
  String get learnHubMarkerBackswingTop;

  /// No description provided for @learnHubMarkerBackswingTopNote.
  ///
  /// In en, this message translates to:
  /// **'Weight still centered over feet, shaft and arms form a straight line.'**
  String get learnHubMarkerBackswingTopNote;

  /// No description provided for @learnHubMarkerImpact.
  ///
  /// In en, this message translates to:
  /// **'Impact'**
  String get learnHubMarkerImpact;

  /// No description provided for @learnHubMarkerImpactNote.
  ///
  /// In en, this message translates to:
  /// **'Hands ahead of the ball, body rotation drives the impact.'**
  String get learnHubMarkerImpactNote;

  /// No description provided for @learnHubMarkerFinish.
  ///
  /// In en, this message translates to:
  /// **'Follow-Through'**
  String get learnHubMarkerFinish;

  /// No description provided for @learnHubMarkerFinishNote.
  ///
  /// In en, this message translates to:
  /// **'Weight transferred to lead foot, body maintains balance.'**
  String get learnHubMarkerFinishNote;

  /// No description provided for @learnHubMarkerEarlyReleaseTopNote.
  ///
  /// In en, this message translates to:
  /// **'Wrist angle releases too early, clubhead lags behind.'**
  String get learnHubMarkerEarlyReleaseTopNote;

  /// No description provided for @learnHubMarkerPreImpact.
  ///
  /// In en, this message translates to:
  /// **'Pre-Impact'**
  String get learnHubMarkerPreImpact;

  /// No description provided for @learnHubMarkerPreImpactNote.
  ///
  /// In en, this message translates to:
  /// **'Insufficient hand lead, weight biased to trail side.'**
  String get learnHubMarkerPreImpactNote;

  /// No description provided for @learnHubMarkerEarlyReleaseFinishNote.
  ///
  /// In en, this message translates to:
  /// **'Weight not transferred to lead foot, poor balance.'**
  String get learnHubMarkerEarlyReleaseFinishNote;

  /// No description provided for @playerTimelineAbbrAddress.
  ///
  /// In en, this message translates to:
  /// **'Adr'**
  String get playerTimelineAbbrAddress;

  /// No description provided for @playerTimelineAbbrTakeaway.
  ///
  /// In en, this message translates to:
  /// **'Tkw'**
  String get playerTimelineAbbrTakeaway;

  /// No description provided for @playerTimelineAbbrBackswing.
  ///
  /// In en, this message translates to:
  /// **'Bk'**
  String get playerTimelineAbbrBackswing;

  /// No description provided for @playerTimelineAbbrTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get playerTimelineAbbrTop;

  /// No description provided for @playerTimelineAbbrDownswing.
  ///
  /// In en, this message translates to:
  /// **'Dwn'**
  String get playerTimelineAbbrDownswing;

  /// No description provided for @playerTimelineAbbrImpact.
  ///
  /// In en, this message translates to:
  /// **'Imp'**
  String get playerTimelineAbbrImpact;

  /// No description provided for @playerTimelineAbbrFollowthrough.
  ///
  /// In en, this message translates to:
  /// **'Fol'**
  String get playerTimelineAbbrFollowthrough;

  /// No description provided for @playerTimelineAbbrFinish.
  ///
  /// In en, this message translates to:
  /// **'Fin'**
  String get playerTimelineAbbrFinish;

  /// No description provided for @recHistSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording History'**
  String get recHistSheetTitle;

  /// No description provided for @recTabsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get recTabsToday;

  /// No description provided for @recTabsYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get recTabsYesterday;

  /// No description provided for @recTabsDateMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String recTabsDateMonthDay(int month, int day);

  /// No description provided for @recWidgetsZoomWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get recWidgetsZoomWide;

  /// No description provided for @recWidgetsSavingVideo.
  ///
  /// In en, this message translates to:
  /// **'Saving video…'**
  String get recWidgetsSavingVideo;

  /// No description provided for @rewardFriendFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get rewardFriendFallbackName;

  /// No description provided for @upgradeHighlightFullFeatured.
  ///
  /// In en, this message translates to:
  /// **'Full recording & analysis features'**
  String get upgradeHighlightFullFeatured;

  /// No description provided for @upgradeHighlightAiDaily10.
  ///
  /// In en, this message translates to:
  /// **'AI coach analysis 10 times per day'**
  String get upgradeHighlightAiDaily10;

  /// No description provided for @upgradeHighlightBuyMore.
  ///
  /// In en, this message translates to:
  /// **'Top up balls when quota runs out'**
  String get upgradeHighlightBuyMore;

  /// No description provided for @upgradeHighlightAiDaily90.
  ///
  /// In en, this message translates to:
  /// **'AI coach analysis 90 times per day'**
  String get upgradeHighlightAiDaily90;

  /// No description provided for @upgradeHighlightAiUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited AI coach analysis'**
  String get upgradeHighlightAiUnlimited;

  /// No description provided for @upgradeFeatureAutoClip.
  ///
  /// In en, this message translates to:
  /// **'Auto clip long videos'**
  String get upgradeFeatureAutoClip;

  /// No description provided for @upgradeFeatureVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Real-time voice prompts'**
  String get upgradeFeatureVoiceHint;

  /// No description provided for @upgradeFeatureAudioScore.
  ///
  /// In en, this message translates to:
  /// **'Audio analysis (impact scoring)'**
  String get upgradeFeatureAudioScore;

  /// No description provided for @upgradeFeatureDualVideo.
  ///
  /// In en, this message translates to:
  /// **'Dual video comparison'**
  String get upgradeFeatureDualVideo;

  /// No description provided for @upgradeFeatureAiCoachAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI coach analysis'**
  String get upgradeFeatureAiCoachAnalysis;

  /// No description provided for @upgradeQuotaDaily10.
  ///
  /// In en, this message translates to:
  /// **'10/day'**
  String get upgradeQuotaDaily10;

  /// No description provided for @upgradeQuotaDaily90.
  ///
  /// In en, this message translates to:
  /// **'90/day'**
  String get upgradeQuotaDaily90;

  /// No description provided for @upgradeQuotaUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get upgradeQuotaUnlimited;

  /// No description provided for @upgradeBadgePopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get upgradeBadgePopular;

  /// No description provided for @upgradeBadgeValue.
  ///
  /// In en, this message translates to:
  /// **'Good Value'**
  String get upgradeBadgeValue;

  /// No description provided for @upgradeBadgeBestDeal.
  ///
  /// In en, this message translates to:
  /// **'Best Deal'**
  String get upgradeBadgeBestDeal;

  /// No description provided for @upgradePerYear.
  ///
  /// In en, this message translates to:
  /// **'/year'**
  String get upgradePerYear;

  /// No description provided for @usageReasonAd.
  ///
  /// In en, this message translates to:
  /// **'Watch Ad Reward'**
  String get usageReasonAd;

  /// No description provided for @usageReasonFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback Reward'**
  String get usageReasonFeedback;

  /// No description provided for @usageReasonInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite Friend Reward'**
  String get usageReasonInvite;

  /// No description provided for @usageReasonUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload Data Reward'**
  String get usageReasonUpload;

  /// No description provided for @usageReasonAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis Cost'**
  String get usageReasonAnalysis;

  /// No description provided for @usageReasonManual.
  ///
  /// In en, this message translates to:
  /// **'Manual Adjustment'**
  String get usageReasonManual;

  /// No description provided for @usageReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get usageReasonOther;

  /// No description provided for @waveformPeakHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get waveformPeakHigh;

  /// No description provided for @waveformPeakMid.
  ///
  /// In en, this message translates to:
  /// **'Mid'**
  String get waveformPeakMid;

  /// No description provided for @waveformPeakLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get waveformPeakLow;

  /// No description provided for @waveformFreqCrispy.
  ///
  /// In en, this message translates to:
  /// **'Crispy'**
  String get waveformFreqCrispy;

  /// No description provided for @waveformFreqMid.
  ///
  /// In en, this message translates to:
  /// **'Mid tone'**
  String get waveformFreqMid;

  /// No description provided for @waveformFreqMuffled.
  ///
  /// In en, this message translates to:
  /// **'Muffled'**
  String get waveformFreqMuffled;

  /// No description provided for @historyProgressV2AudioScan.
  ///
  /// In en, this message translates to:
  /// **'V2 audio scanning...'**
  String get historyProgressV2AudioScan;

  /// No description provided for @historyProgressV3AudioScan.
  ///
  /// In en, this message translates to:
  /// **'V3 audio scanning...'**
  String get historyProgressV3AudioScan;

  /// No description provided for @historyProgressWaitingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Waiting for clip confirmation...'**
  String get historyProgressWaitingConfirm;

  /// No description provided for @historyProgressClipping.
  ///
  /// In en, this message translates to:
  /// **'Trimming clips...'**
  String get historyProgressClipping;

  /// No description provided for @historyProgressClippingPct.
  ///
  /// In en, this message translates to:
  /// **'Trimming clips... {pct}% ({cur}/{total})'**
  String historyProgressClippingPct(int pct, int cur, int total);

  /// No description provided for @historyProgressV3SkeletonAnalysis.
  ///
  /// In en, this message translates to:
  /// **'V3 skeleton analysis {cur}/{total}'**
  String historyProgressV3SkeletonAnalysis(int cur, int total);

  /// No description provided for @historyProgressV3SkeletonItem.
  ///
  /// In en, this message translates to:
  /// **'Item {cur}/{total}'**
  String historyProgressV3SkeletonItem(int cur, int total);

  /// No description provided for @historyProgressDetectingHit.
  ///
  /// In en, this message translates to:
  /// **'Detecting impact...'**
  String get historyProgressDetectingHit;

  /// No description provided for @historyProgressVideoAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analyzing video...'**
  String get historyProgressVideoAnalysis;

  /// No description provided for @historyProgressDetectingPhase.
  ///
  /// In en, this message translates to:
  /// **'Detecting swing phases...'**
  String get historyProgressDetectingPhase;

  /// No description provided for @historyProgressAudioAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Analyzing audio...'**
  String get historyProgressAudioAnalysis;

  /// No description provided for @historyDlLabelFull.
  ///
  /// In en, this message translates to:
  /// **'Full Analysis'**
  String get historyDlLabelFull;

  /// No description provided for @historyDlDescFull.
  ///
  /// In en, this message translates to:
  /// **'Skeleton + ball trajectory overlay'**
  String get historyDlDescFull;

  /// No description provided for @historyDlLabelSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton Version'**
  String get historyDlLabelSkeleton;

  /// No description provided for @historyDlDescSkeleton.
  ///
  /// In en, this message translates to:
  /// **'Skeleton overlay only'**
  String get historyDlDescSkeleton;

  /// No description provided for @historyDlLabelClip.
  ///
  /// In en, this message translates to:
  /// **'Original Clip'**
  String get historyDlLabelClip;

  /// No description provided for @historyDlDescClip.
  ///
  /// In en, this message translates to:
  /// **'Original clip without overlay'**
  String get historyDlDescClip;

  /// No description provided for @historyDlLabelRaw.
  ///
  /// In en, this message translates to:
  /// **'Original Video'**
  String get historyDlLabelRaw;

  /// No description provided for @historyDlDescRaw.
  ///
  /// In en, this message translates to:
  /// **'No overlay'**
  String get historyDlDescRaw;

  /// No description provided for @historyDlLabelRawMov.
  ///
  /// In en, this message translates to:
  /// **'Original Video (MOV)'**
  String get historyDlLabelRawMov;

  /// No description provided for @historyDlDescRawMov.
  ///
  /// In en, this message translates to:
  /// **'Original MOV file'**
  String get historyDlDescRawMov;

  /// No description provided for @historyCandidateDuration.
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String historyCandidateDuration(int seconds);

  /// No description provided for @recDetailPointCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pts'**
  String recDetailPointCount(int count);
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
