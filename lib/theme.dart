import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const mono = 'monospace';

/// iOS-style palette (system colors from Apple's HIG), one instance per
/// brightness. Read it with `AppColors.of(context)` so widgets rebuild when
/// the system switches between light and dark.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Screen background (systemGroupedBackground).
  final Color bg;

  /// Grouped cells and cards (secondarySystemGroupedBackground).
  final Color surface;

  /// Input fields and chips inside cells (tertiary fill).
  final Color surface2;

  /// Hairline separators.
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color warning;
  final Color success;
  final Color danger;
  final Color purple;
  final Color gray;

  /// Translucent bars (navigation and tab bar).
  final Color bar;

  /// Text and glyphs drawn on a colored fill (buttons, icon boxes).
  final Color onTint;

  /// Selected thumb of a segmented control.
  final Color thumb;

  // JSON syntax colors
  final Color jKey;
  final Color jString;
  final Color jNumber;
  final Color jBool;
  final Color jNull;
  final Color jPunct;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.warning,
    required this.success,
    required this.danger,
    required this.purple,
    required this.gray,
    required this.bar,
    required this.onTint,
    required this.thumb,
    required this.jKey,
    required this.jString,
    required this.jNumber,
    required this.jBool,
    required this.jNull,
    required this.jPunct,
  });

  static const light = AppColors(
    bg: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEEEF0),
    border: Color(0xFFC6C6C8),
    text: Color(0xFF000000),
    muted: Color(0xFF8A8A8E),
    accent: Color(0xFF007AFF),
    warning: Color(0xFFFF9500),
    success: Color(0xFF34C759),
    danger: Color(0xFFFF3B30),
    purple: Color(0xFFAF52DE),
    gray: Color(0xFF8E8E93),
    bar: Color(0xF0F9F9F9),
    onTint: Color(0xFFFFFFFF),
    thumb: Color(0xFFFFFFFF),
    jKey: Color(0xFF1F5FBF),
    jString: Color(0xFFC41A16),
    jNumber: Color(0xFF1C00CF),
    jBool: Color(0xFFAD3DA4),
    jNull: Color(0xFFAD3DA4),
    jPunct: Color(0xFF6E6E73),
  );

  static const dark = AppColors(
    bg: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    border: Color(0xFF38383A),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFF98989F),
    accent: Color(0xFF0A84FF),
    warning: Color(0xFFFF9F0A),
    success: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
    purple: Color(0xFFBF5AF2),
    gray: Color(0xFF8E8E93),
    bar: Color(0xF0161618),
    onTint: Color(0xFFFFFFFF),
    thumb: Color(0xFF636366),
    jKey: Color(0xFF5DD8FF),
    jString: Color(0xFFFC6A5D),
    jNumber: Color(0xFFD0BF69),
    jBool: Color(0xFFFC5FA3),
    jNull: Color(0xFFFC5FA3),
    jPunct: Color(0xFF98989F),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>() ?? dark;

  Color method(String m) => switch (m.toUpperCase()) {
        'GET' => success,
        'POST' => warning,
        'PUT' => accent,
        'PATCH' => purple,
        'DELETE' => danger,
        _ => gray,
      };

  Color status(int? code) {
    if (code == null) return danger;
    if (code < 300) return success;
    if (code < 400) return accent;
    if (code < 500) return warning;
    return danger;
  }

  @override
  AppColors copyWith() => this;

  // Palettes are swapped, not animated: only light and dark exist.
  @override
  AppColors lerp(AppColors? other, double t) => other == null || t < 0.5 ? this : other;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Material theme dressed as iOS: iOS platform behavior (swipe-back
/// transitions, bouncing scroll, centered titles, adaptive controls) with
/// Apple's system colors.
ThemeData buildTheme([Brightness brightness = Brightness.dark]) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
    surface: c.surface,
    primary: c.accent,
    onPrimary: c.onTint,
    error: c.danger,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerHighest: c.surface2,
  );
  final fieldBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    platform: TargetPlatform.iOS,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.text.withValues(alpha: 0.06),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: c.accent,
      scaffoldBackgroundColor: c.bg,
      barBackgroundColor: c.bar,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bar,
      foregroundColor: c.accent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      shape: Border(bottom: BorderSide(color: c.border, width: 0)),
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.surface2,
      hintStyle: TextStyle(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(borderSide: BorderSide(color: c.accent, width: 1.2)),
      errorBorder: fieldBorder.copyWith(borderSide: BorderSide(color: c.danger, width: 1)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.text,
      unselectedLabelColor: c.muted,
      indicatorColor: c.accent,
      dividerColor: c.border,
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface2,
      contentTextStyle: TextStyle(color: c.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 0.5),
    cardTheme: CardThemeData(color: c.surface, margin: EdgeInsets.zero),
  );
}
