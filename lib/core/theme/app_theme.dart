import 'package:flutter/material.dart';
import 'theme_palettes.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData build(AppPalette palette, {required bool reducedMotion}) {
    final colorScheme = ColorScheme(
      brightness: palette.background.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark,
      primary: palette.primary,
      onPrimary: _onColor(palette.primary),
      secondary: palette.secondary,
      onSecondary: _onColor(palette.secondary),
      error: const Color(0xFFE0876D),
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.text,
    );

    final textTheme = _textTheme(palette.text);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      textTheme: textTheme,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: reducedMotion
                ? const FadeUpwardsPageTransitionsBuilder()
                : const _PremiumPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent, // Let glass effect show through
        indicatorColor: palette.secondary.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.text,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: _onColor(palette.primary),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  static Color _onColor(Color color) {
    return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  static TextTheme _textTheme(Color onSurface) {
    const display = 'Fraunces';
    const body = 'Inter';
    return TextTheme(
      displayLarge: TextStyle(fontFamily: display, fontWeight: FontWeight.w600, fontSize: 40, color: onSurface),
      headlineMedium: TextStyle(fontFamily: display, fontWeight: FontWeight.w600, fontSize: 26, color: onSurface),
      titleLarge: TextStyle(fontFamily: display, fontWeight: FontWeight.w600, fontSize: 20, color: onSurface),
      bodyLarge: TextStyle(fontFamily: body, fontSize: 16, color: onSurface),
      bodyMedium: TextStyle(fontFamily: body, fontSize: 14, color: onSurface),
      labelSmall: TextStyle(fontFamily: body, fontWeight: FontWeight.w500, fontSize: 12, color: onSurface),
    );
  }
}

class _PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const _PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
