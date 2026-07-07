import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart' as web;
import '../../../core/theme/theme_palettes.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed, required AppPalette palette}) {
  return (GoogleSignInPlatform.instance as web.GoogleSignInPlugin).renderButton(
    configuration: web.GSIButtonConfiguration(
      type: web.GSIButtonType.standard,
      shape: web.GSIButtonShape.rectangular,
      size: web.GSIButtonSize.large,
      theme: web.GSIButtonTheme.outline,
      text: web.GSIButtonText.signinWith,
    ),
  );
}
