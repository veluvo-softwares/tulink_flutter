import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/tulink_colors.dart';
import '../services/location_permission_service.dart';

/// Why a location-dependent action is being blocked.
enum LocationBlockReason {
  /// The device-wide location/GPS master switch is off.
  servicesOff,

  /// The app's location permission is denied (or permanently denied).
  permissionDenied,
}

/// Hard gate for any map/convoy action that needs the user's live position.
///
/// Waze-style: if location services are off or permission isn't granted, we do
/// NOT proceed. We surface a bottom sheet that routes the user to the relevant
/// settings screen instead. Returns `true` only when there's a usable location
/// path (services on + permission granted).
///
/// Call this BEFORE making any backend/convoy calls so a blocked user never
/// triggers a journey they can't actually participate in.
Future<bool> ensureLocationReady(BuildContext context) async {
  // 1. Device location services master switch — distinct from app permission.
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      await showLocationRequiredSheet(context, LocationBlockReason.servicesOff);
    }
    return false;
  }

  // 2. App-level permission. Request inline on a first 'denied'; anything still
  //    not granted falls through to the settings hand-off.
  //
  // Uses the shared guarded request (not Geolocator.requestPermission()
  // directly) because multiple screens can react to the same event (e.g. the
  // home screen and this journey-preview screen both listen for
  // journey-started) and each try to gate location around the same moment —
  // without the shared guard, two concurrent native requests stack two OS
  // permission dialogs.
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await LocationPermissionService.requestPermissionGuarded();
  }

  final granted =
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
  if (!granted) {
    if (context.mounted) {
      await showLocationRequiredSheet(
        context,
        LocationBlockReason.permissionDenied,
      );
    }
    return false;
  }

  return true;
}

/// First-run education shown right after login, BEFORE the OS permission
/// dialog, to lift grant rates. No-op when permission is already resolved
/// (granted, or already asked) — there's nothing to prime. When the user taps
/// "Continue" the OS permission dialog is triggered.
Future<void> maybeShowLocationPriming(BuildContext context) async {
  // Already granted → nothing to prime.
  if (await LocationPermissionService.hasLocationPermission()) return;

  // Only prime the *first* ask. `denied` covers "not yet asked" on both
  // platforms; if it's permanently denied the OS won't re-prompt, so we leave
  // it — the in-flow gate routes such users to settings when they start.
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.denied) return;

  if (!context.mounted) return;
  final colors = Theme.of(context).tulinkColors;

  final proceed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _LocationSheet(
      icon: Icons.my_location_rounded,
      title: 'Share your location with your convoy',
      body:
          'Tulink uses your location to place you on the map, keep your '
          'convoy in sync, and guide you turn-by-turn. You can change this '
          'anytime in settings.',
      steps: 'Next, allow location — choose “While using the app”.',
      primaryLabel: 'Continue',
      secondaryLabel: 'Not now',
      colors: colors,
      onPrimary: () => Navigator.of(sheetContext).pop(true),
      onSecondary: () => Navigator.of(sheetContext).pop(false),
    ),
  );

  if (proceed == true) {
    await LocationPermissionService.requestPermissionGuarded();
  }
}

/// Waze-style bottom sheet shown when a location-dependent action is blocked.
/// Primary CTA routes to the correct settings screen; secondary cancels.
Future<void> showLocationRequiredSheet(
  BuildContext context,
  LocationBlockReason reason,
) {
  final colors = Theme.of(context).tulinkColors;
  final servicesOff = reason == LocationBlockReason.servicesOff;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _LocationSheet(
      icon: servicesOff
          ? Icons.location_off_rounded
          : Icons.my_location_rounded,
      title: servicesOff
          ? 'Turn on location to drive with Tulink'
          : 'Tulink needs your location',
      body: servicesOff
          ? 'Your device location is off. Tulink uses your location to place '
                'you on the map and keep your convoy in sync.'
          : 'Allow location access so your convoy can see you and you get '
                'turn-by-turn guidance.',
      steps: servicesOff
          ? 'Open settings, then turn on Location.'
          : 'Open settings, then allow Location — choose “While using the app”.',
      primaryLabel: 'Open Settings',
      secondaryLabel: 'Cancel',
      colors: colors,
      onPrimary: () async {
        Navigator.of(sheetContext).pop();
        if (servicesOff) {
          await Geolocator.openLocationSettings();
        } else {
          await Geolocator.openAppSettings();
        }
      },
      onSecondary: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// Shared visual shell for the priming and blocking sheets.
class _LocationSheet extends StatelessWidget {
  const _LocationSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.steps,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.colors,
    required this.onPrimary,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String steps;
  final String primaryLabel;
  final String secondaryLabel;
  final TulinkColors colors;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.routeTeal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors.routeTeal, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: colors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(color: colors.muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.settings_outlined, size: 16, color: colors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onPrimary,
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel,
                  style: TextStyle(
                    color: colors.deepTeal,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
