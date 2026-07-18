import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AppLoadingIndicator extends StatelessWidget {
  final double size;
  
  const AppLoadingIndicator({
    super.key,
    this.size = 64.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageAsset = isDark ? 'assets/app_icon_inverted.png' : 'assets/app_icon.png';
    
    return Image.asset(
      imageAsset,
      width: size,
      height: size,
    )
    .animate(onPlay: (controller) => controller.repeat())
    .shimmer(duration: 1200.ms, color: isDark ? Colors.white24 : Colors.black12)
    .scaleXY(begin: 0.95, end: 1.05, duration: 800.ms, curve: Curves.easeInOut)
    .then()
    .scaleXY(begin: 1.05, end: 0.95, duration: 800.ms, curve: Curves.easeInOut);
  }
}
