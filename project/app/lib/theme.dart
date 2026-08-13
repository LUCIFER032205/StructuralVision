import 'package:flutter/material.dart';

// ── StructuralVision premium dark theme ─────────────────────────────────────
// Surfaces: deep slate family
// Accent:   amber-400 (#FBBF24) — construction / warning-aware
// Danger:   rose-500  (#F43F5E)
// Success:  emerald-400 (#34D399)
// -----------------------------------------------------------------------------

class AppColors {
  AppColors._();

  // Surfaces
  static const bg       = Color(0xFF0D1117); // page background
  static const surface  = Color(0xFF161B22); // cards, panels
  static const surface2 = Color(0xFF21262D); // elevated cards
  static const border   = Color(0xFF30363D); // dividers, strokes

  // Text
  static const textPrimary   = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted     = Color(0xFF484F58);

  // Accent
  static const accent     = Color(0xFFFBBF24); // amber-400
  static const accentDark = Color(0xFF92400E); // amber-900 (pressed)

  // Semantic
  static const danger  = Color(0xFFF43F5E);
  static const warning = Color(0xFFFB923C);
  static const success = Color(0xFF34D399);

  // Risk
  static const riskHigh   = Color(0xFFF43F5E);
  static const riskMedium = Color(0xFFFB923C);
  static const riskLow    = Color(0xFF34D399);
}

class AppTextStyles {
  AppTextStyles._();

  static const _base = TextStyle(
    fontFamily: 'Roboto',
    color: AppColors.textPrimary,
    letterSpacing: 0,
  );

  static final displayLg = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static final titleLg   = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3);
  static final titleMd   = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4);
  static final titleSm   = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.textSecondary);
  static final bodyMd    = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static final bodySm    = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400, height: 1.5, color: AppColors.textSecondary);
  static final label     = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: AppColors.textMuted);
  static final mono      = _base.copyWith(fontSize: 13, fontFamily: 'RobotoMono', color: AppColors.textSecondary);
}

const kCardRadius   = 12.0;
const kButtonRadius = 10.0;
const kPagePadding  = 20.0;

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.dark(
      primary:    AppColors.accent,
      onPrimary:  AppColors.bg,
      secondary:  AppColors.accent,
      surface:    AppColors.surface,
      onSurface:  AppColors.textPrimary,
      error:      AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: AppColors.border,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 22),
      actionsIconTheme: IconThemeData(color: AppColors.textSecondary, size: 22),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface2,
      labelStyle: AppTextStyles.titleSm.copyWith(color: AppColors.textPrimary),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        textStyle: AppTextStyles.titleSm.copyWith(color: AppColors.bg, fontWeight: FontWeight.w600, letterSpacing: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kButtonRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        textStyle: AppTextStyles.titleSm.copyWith(color: AppColors.textPrimary, letterSpacing: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kButtonRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.accent, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kButtonRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
      hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kButtonRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kButtonRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kButtonRadius),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kButtonRadius),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: AppTextStyles.bodyMd,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.bg,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
  );
}

// ── Shared card widget ────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: AppColors.border),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

// ── Risk badge ────────────────────────────────────────────────────────────────
class RiskBadge extends StatelessWidget {
  final String risk;
  final bool large;

  const RiskBadge(this.risk, {super.key, this.large = false});

  Color get _color {
    switch (risk) {
      case 'HIGH':   return AppColors.riskHigh;
      case 'MEDIUM': return AppColors.riskMedium;
      case 'LOW':    return AppColors.riskLow;
      default:       return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical:   large ? 6  : 3,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Text(
        risk,
        style: (large ? AppTextStyles.titleMd : AppTextStyles.bodySm)
            .copyWith(color: _color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
