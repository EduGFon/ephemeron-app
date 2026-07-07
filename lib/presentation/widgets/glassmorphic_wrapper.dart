import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/app_settings_provider.dart';

class GlassmorphicWrapper extends ConsumerWidget {
  final Widget child;
  final ImageFilter filter;

  const GlassmorphicWrapper({
    super.key,
    required this.child,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    if (!settings.glassmorphismEnabled) {
      return child;
    }

    return BackdropFilter(
      filter: filter,
      child: child,
    );
  }
}
