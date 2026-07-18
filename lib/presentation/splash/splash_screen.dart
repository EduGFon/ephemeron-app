import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/google/google_auth_provider.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

/// Shown at launch while [googleAuthInitProvider] completes.
/// Once init resolves the router redirect takes over automatically.
/// Using a dedicated splash route avoids the flash of /auth on every
/// restart when [attemptLightweightAuthentication] is in flight.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching (not just reading) here ensures the router refreshes when
    // the FutureProvider transitions from loading → data.
    ref.watch(googleAuthInitProvider);

    return const Scaffold(
      body: Center(child: AppLoadingIndicator()),
    );
  }
}
