import 'package:flutter/material.dart';

// ── ORVIA 品牌色 ─────────────────────────────────────────────────
const kOrviaMint   = Color(0xFF2BD9A0); // logo 漸層起點
const kOrviaBlue   = Color(0xFF38B6E8); // logo 漸層中段
const kOrviaViolet = Color(0xFF5B5BE8); // logo 漸層終點
const kOrviaInk    = Color(0xFF0A0A0F); // 深色背景

// ── 主色 ─────────────────────────────────────────────────────────
// 淺色主題用加深的 mint(#1AA87C)確保對比度;深色主題用 logo 原色
const kPrimaryGreen  = Color(0xFF1AA87C);
const kPrimaryDark   = Color(0xFF0F5C46);
const kPrimaryLight  = kOrviaMint;

// ── 語意色 ───────────────────────────────────────────────────────
const kGoodColor   = Color(0xFF1AA87C);
const kBadColor    = Color(0xFFE05252);
const kSpeedColor  = Color(0xFF2E8EFF);
const kSweetColor  = Color(0xFF8E4AF4);
const kCrispColor  = Color(0xFFFF9800);
const kNeutralColor = Color(0xFF6F7B86);

// ── 背景 ─────────────────────────────────────────────────────────
const kBgPage  = Color(0xFFF5F7FB);
const kBgCard  = Colors.white;
const kBgDark  = Color(0xFF1A1A1A);

// ── 文字 ─────────────────────────────────────────────────────────
const kTextPrimary   = Color(0xFF0B2A2E);
const kTextSecondary = Color(0xFF6F7B86);
const kTextHint      = Color(0xFFB0BAC4);

// ── 間距常數 ─────────────────────────────────────────────────────
const kSpaceXS = 4.0;
const kSpaceSM = 8.0;
const kSpaceMD = 16.0;
const kSpaceLG = 24.0;
const kSpaceXL = 32.0;

// ── 圓角 ─────────────────────────────────────────────────────────
const kRadiusSM  = 10.0;
const kRadiusMD  = 16.0;
const kRadiusLG  = 22.0;
const kRadiusXL  = 28.0;

// ── 陰影 ─────────────────────────────────────────────────────────
const kCardShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
];

const kElevatedShadow = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 6)),
];

// ── 深色對應色 ───────────────────────────────────────────────────
const kTextPrimaryDark   = Color(0xFFE6EAEE);
const kTextSecondaryDark = Color(0xFF9AA4AE);
const kTextHintDark      = Color(0xFF5C6670);
const kBgInsetLight = Color(0xFFF4F6F9); // 淺灰填底(chip/欄位)
const kBgInsetDark  = Color(0xFF1E1E28);
const kBorderLight  = Color(0xFFDDE1E7);
const kBorderDark   = Color(0xFF2A2A36);
const kMintTintLight = Color(0xFFF0FBF6); // 薄荷淡底(提示框/頭像底)
const kMintTintDark  = Color(0xFF12352B);

// ── 深淺自適應(取代頁面內寫死顏色)──────────────────────────────
extension AppColorsX on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get bgPage  => isDarkMode ? kBgPageDark : kBgPage;
  Color get bgCard  => isDarkMode ? kBgCardDark : kBgCard;
  Color get bgInset => isDarkMode ? kBgInsetDark : kBgInsetLight;

  Color get textPrimary   => isDarkMode ? kTextPrimaryDark : kTextPrimary;
  Color get textSecondary => isDarkMode ? kTextSecondaryDark : kTextSecondary;
  Color get textHint      => isDarkMode ? kTextHintDark : kTextHint;

  Color get borderColor => isDarkMode ? kBorderDark : kBorderLight;
  Color get mintTint    => isDarkMode ? kMintTintDark : kMintTintLight;

  List<BoxShadow> get cardShadow => isDarkMode ? const [] : kCardShadow;
}

// ── 卡片裝飾 ─────────────────────────────────────────────────────
BoxDecoration kCardDecoration({
  Color? color,
  double radius = kRadiusMD,
  List<BoxShadow>? shadow,
  Border? border,
}) =>
    BoxDecoration(
      color: color ?? kBgCard,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ?? kCardShadow,
      border: border,
    );

// ── 漸層 ─────────────────────────────────────────────────────────
const kPrimaryGradient = LinearGradient(
  colors: [kPrimaryGreen, kPrimaryDark],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ORVIA 品牌漸層(logo 軌跡環:mint → blue → violet)
const kOrviaGradient = LinearGradient(
  colors: [kOrviaMint, kOrviaBlue, kOrviaViolet],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

LinearGradient kColorGradient(Color color) => LinearGradient(
      colors: [color, Color.lerp(color, Colors.black, 0.2)!],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

// ── ThemeData ─────────────────────────────────────────────────────
ThemeData buildAppTheme() {
  final cs = ColorScheme.fromSeed(
    seedColor: kPrimaryGreen,
    primary: kPrimaryGreen,
    onPrimary: Colors.white,
    secondary: kOrviaViolet,
    onSecondary: Colors.white,
    surface: kBgCard,
    onSurface: kTextPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: kBgPage,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBgPage,
      foregroundColor: kTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kBgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMD)),
      shadowColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
        padding:
            const EdgeInsets.symmetric(horizontal: kSpaceLG, vertical: kSpaceMD),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
        padding: const EdgeInsets.symmetric(vertical: kSpaceMD),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMD),
        borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
      ),
      labelStyle: const TextStyle(color: kTextSecondary),
      floatingLabelStyle: const TextStyle(color: kPrimaryGreen),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSM)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSM)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: kPrimaryGreen),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kPrimaryGreen : null,
      ),
    ),
  );
}

// ── 深色 ThemeData(ORVIA 品牌主色)──────────────────────────────
const kBgPageDark = kOrviaInk;
const kBgCardDark = Color(0xFF16161E);

ThemeData buildAppDarkTheme() {
  final cs = ColorScheme.fromSeed(
    seedColor: kOrviaMint,
    brightness: Brightness.dark,
    primary: kOrviaMint,
    onPrimary: Color(0xFF00261A),
    secondary: kOrviaViolet,
    onSecondary: Colors.white,
    surface: kBgCardDark,
    onSurface: Color(0xFFE6EAEE),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: kBgPageDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBgPageDark,
      foregroundColor: Color(0xFFE6EAEE),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kBgCardDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMD)),
      shadowColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kOrviaMint,
        foregroundColor: const Color(0xFF00261A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
        padding:
            const EdgeInsets.symmetric(horizontal: kSpaceLG, vertical: kSpaceMD),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kOrviaMint,
        foregroundColor: const Color(0xFF00261A),
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
        padding: const EdgeInsets.symmetric(vertical: kSpaceMD),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusMD)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMD),
        borderSide: const BorderSide(color: kOrviaMint, width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF9AA4AE)),
      floatingLabelStyle: const TextStyle(color: kOrviaMint),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSM)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSM)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: kOrviaMint),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kOrviaMint : null,
      ),
    ),
  );
}
