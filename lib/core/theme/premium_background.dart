import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'theme_palettes.dart';

class PremiumBackground extends StatelessWidget {
  final AppPalette palette;
  final bool isReducedMotion;

  const PremiumBackground({
    required this.palette,
    required this.isReducedMotion,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (palette.isAmoled) {
      return Container(color: Colors.black);
    }

    if (isReducedMotion) {
      return Container(color: palette.background);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.background,
            palette.meshColors[0],
            palette.meshColors[1],
            palette.background,
          ],
        ),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: const Duration(seconds: 15),
          colors: [
            palette.meshColors[2].withValues(alpha: 0.2),
            palette.meshColors[3].withValues(alpha: 0.2),
            palette.meshColors[2].withValues(alpha: 0.2),
          ],
          angle: 0.5,
        )
        .blur(end: const Offset(15, 15), duration: const Duration(seconds: 10), curve: Curves.easeInOutSine)
        .then()
        .blur(end: const Offset(25, 25), duration: const Duration(seconds: 10), curve: Curves.easeInOutSine);
  }
}
