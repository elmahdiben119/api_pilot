import 'package:flutter/material.dart';

const mono = 'monospace';

class AppColors {
  static const bg = Color(0xFF0E1116);
  static const surface = Color(0xFF161B22);
  static const surface2 = Color(0xFF1F2630);
  static const border = Color(0xFF2B3440);
  static const text = Color(0xFFE6EDF3);
  static const muted = Color(0xFF8B96A5);
  static const accent = Color(0xFF7C9CFF);

  // JSON syntax colors
  static const jKey = Color(0xFF9CDCFE);
  static const jString = Color(0xFFCE9178);
  static const jNumber = Color(0xFFB5CEA8);
  static const jBool = Color(0xFF569CD6);
  static const jNull = Color(0xFFC586C0);
  static const jPunct = Color(0xFF8B96A5);
}

Color methodColor(String m) {
  switch (m.toUpperCase()) {
    case 'GET':
      return const Color(0xFF4ADE80);
    case 'POST':
      return const Color(0xFFFBBF24);
    case 'PUT':
      return const Color(0xFF60A5FA);
    case 'PATCH':
      return const Color(0xFFC084FC);
    case 'DELETE':
      return const Color(0xFFF87171);
    default:
      return const Color(0xFF94A3B8);
  }
}

Color statusColor(int? code) {
  if (code == null) return const Color(0xFFF87171);
  if (code < 300) return const Color(0xFF4ADE80);
  if (code < 400) return const Color(0xFF60A5FA);
  if (code < 500) return const Color(0xFFFBBF24);
  return const Color(0xFFF87171);
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

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    primary: AppColors.accent,
    outline: AppColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      height: 64,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface2,
      hintStyle: const TextStyle(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.accent,
      dividerColor: AppColors.border,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    cardTheme: const CardThemeData(color: AppColors.surface, margin: EdgeInsets.zero),
  );
}
