import 'package:flutter/material.dart';

/// What the platform Back gesture does at the Home/live-journey boundary.
///
/// Modelled as its own widget so the rule is *production* wiring that a test
/// can drive through a real [PopScope] and a real [Navigator]. The previous
/// proof searched Home's source for a callback name, and separately tapped a
/// `ConvoyStatusBar` constructed with test-only callbacks — neither could see
/// that Home stopped intercepting Back once the chrome was collapsed.
///
/// The rule for an active journey:
///
/// * Back while the chrome is **expanded** collapses it. The journey keeps
///   running and the restore pill becomes the observable proof of that.
/// * Back while the chrome is **collapsed** restores it. It does *not* pop the
///   shell: popping would leave a live convoy running behind a screen the user
///   can no longer reach, and it would be an implicit exit from a journey that
///   other people are navigating off.
///
/// Leaving or ending a live journey therefore stays what it always was — an
/// explicit, confirmed action on the journey chrome itself.
class LiveJourneyBackBoundary extends StatelessWidget {
  const LiveJourneyBackBoundary({
    super.key,
    required this.hasActiveJourney,
    required this.isChromeCollapsed,
    required this.onCollapseChrome,
    required this.onRestoreChrome,
    required this.child,
  });

  /// True while a journey owns the screen — running, or tearing down.
  final bool hasActiveJourney;

  /// True once Back has already collapsed the journey chrome.
  final bool isChromeCollapsed;

  final VoidCallback onCollapseChrome;
  final VoidCallback onRestoreChrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept for the whole life of the journey, not just while the chrome
      // is expanded. Releasing the intercept on collapse meant a second Back
      // popped the shell out from under a running convoy.
      canPop: !hasActiveJourney,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !hasActiveJourney) return;
        if (isChromeCollapsed) {
          onRestoreChrome();
        } else {
          onCollapseChrome();
        }
      },
      child: child,
    );
  }
}
