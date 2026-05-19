import 'package:flutter/material.dart';

// ── 主色 ─────────────────────────────────────────────────────────
const kPrimaryGreen  = Color(0xFF1E8E5A);
const kPrimaryDark   = Color(0xFF0A3D2E);
const kPrimaryLight  = Color(0xFF2DB86A);

// ── 語意色 ───────────────────────────────────────────────────────
const kGoodColor   = Color(0xFF1E8E5A);
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
