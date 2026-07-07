import 'package:flutter/material.dart';
import '../../../core/theme/theme_palettes.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed, required AppPalette palette}) {
  return FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.login),
    label: const Text('Connect Google Calendar'),
  );
}
