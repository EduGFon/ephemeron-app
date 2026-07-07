import 'package:flutter/material.dart';

import '../domain/countdown_type.dart';
import 'countdown_form_sheet.dart';

import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_engine_provider.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';

Future<void> showCountdownTemplatePicker(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: Consumer(
              builder: (context, ref, child) {
                final palette = ref.watch(themeEngineProvider);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: GlassmorphicWrapper(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Select type',
                              style: TextStyle(color: palette.text, fontSize: 24, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            for (final type in CountdownType.values)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                    showCountdownFormSheet(context, type: type);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: palette.text.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(_iconFor(type), color: palette.primary),
                                        const SizedBox(width: 16),
                                        Text(
                                          type.label,
                                          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600, fontSize: 16),
                                        ),
                                        const Spacer(),
                                        Icon(Icons.chevron_right, color: palette.text.withValues(alpha: 0.3)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: curve,
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}

IconData _iconFor(CountdownType type) {
  return switch (type) {
    CountdownType.holiday => Icons.celebration_outlined,
    CountdownType.anniversary => Icons.favorite_outline,
    CountdownType.birthday => Icons.cake_outlined,
    CountdownType.custom => Icons.hourglass_bottom_outlined,
  };
}
