import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Obsidian Royale" — deep violet-black surfaces, royal violet primary, champagne gold for money,
/// mint for success. Display font Sora, body font Manrope.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF07060E);
  static const bgTop = Color(0xFF120C2B);
  static const surface = Color(0xFF110F22);
  static const surface2 = Color(0xFF1A1733);
  static const surface3 = Color(0xFF231F45);
  static const stroke = Color(0xFF2B2752);
  static const primary = Color(0xFF7C5CFF);
  static const primaryLight = Color(0xFFA58BFF);
  static const gold = Color(0xFFF5C451);
  static const goldLight = Color(0xFFFFE9A8);
  static const goldDeep = Color(0xFFB07A12);
  static const mint = Color(0xFF3DF5C0);
  static const danger = Color(0xFFFF5C7A);
  static const warning = Color(0xFFFFB547);
  static const text = Color(0xFFF4F2FF);
  static const muted = Color(0xFF9A94C2);
  static const faint = Color(0xFF5E5888);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDeep],
  );

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary, Color(0xFF4B2FE0)],
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1E5C), Color(0xFF16112F), Color(0xFF0B0918)],
  );
}

class AppTheme {
  AppTheme._();

  static TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color color = AppColors.text, double? height}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: -0.3);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w500, Color color = AppColors.text, double? height}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, color: color, height: height);

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Color(0xFF1A1200),
        onSurface: AppColors.text,
      ),
    );
    final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: AppColors.text, displayColor: AppColors.text);
    return base.copyWith(
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: display(18),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        hintStyle: body(14, color: AppColors.faint),
        labelStyle: body(13, color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.stroke)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.stroke)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.danger)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface3,
        contentTextStyle: body(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.faint,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primaryLight),
      dividerColor: AppColors.stroke,
    );
  }
}
