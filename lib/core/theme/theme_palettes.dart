import 'package:flutter/material.dart';

enum AppPaletteType {
  obsidian,
  aurora,
  minimalist,
  amoled,
}

class AppPalette {
  final AppPaletteType type;
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final List<Color> meshColors;
  final bool isAmoled;

  const AppPalette({
    required this.type,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.meshColors,
    this.isAmoled = false,
  });

  static const obsidian = AppPalette(
    type: AppPaletteType.obsidian,
    name: 'Obsidian Glass',
    primary: Color(0xFF6C63FF),
    secondary: Color(0xFF03DAC6),
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    text: Color(0xFFE0E0E0),
    meshColors: [
      Color(0xFF1A1A24),
      Color(0xFF2C2C3E),
      Color(0xFF121212),
      Color(0xFF1E1E2C),
    ],
  );

  static const aurora = AppPalette(
    type: AppPaletteType.aurora,
    name: 'Aurora',
    primary: Color(0xFFFF6584),
    secondary: Color(0xFF38B2AC),
    background: Color(0xFF1A202C),
    surface: Color(0xFF2D3748),
    text: Color(0xFFF7FAFC),
    meshColors: [
      Color(0xFF4A148C),
      Color(0xFF880E4F),
      Color(0xFF004D40),
      Color(0xFF1A237E),
    ],
  );

  static const minimalist = AppPalette(
    type: AppPaletteType.minimalist,
    name: 'Minimalist Silk',
    primary: Color(0xFF2D3748),
    secondary: Color(0xFF718096),
    background: Color(0xFFF7FAFC),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1A202C),
    meshColors: [
      Color(0xFFF7FAFC),
      Color(0xFFEDF2F7),
      Color(0xFFE2E8F0),
      Color(0xFFFFFFFF),
    ],
  );

  static const amoled = AppPalette(
    type: AppPaletteType.amoled,
    name: 'Pure AMOLED',
    primary: Color(0xFFBB86FC),
    secondary: Color(0xFF03DAC6),
    background: Colors.black,
    surface: Colors.black,
    text: Color(0xFFE0E0E0),
    meshColors: [
      Colors.black,
      Colors.black,
      Colors.black,
      Colors.black,
    ],
    isAmoled: true,
  );

  static const values = [obsidian, aurora, minimalist, amoled];
}
