import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../providers/auth_provider.dart';

/// "or" divider + Continue with Google / Apple buttons. Self-contained: drives
/// the AuthProvider social flows and navigates on success, so it can be dropped
/// into both the sign-in and sign-up screens unchanged. Social is an upsert, so
/// it serves sign-in and sign-up identically.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({super.key});

  Future<void> _google(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    if (!context.mounted) return;
    if (ok) _navigate(context);
  }

  Future<void> _apple(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithApple();
    if (!context.mounted) return;
    if (ok) _navigate(context);
  }

  /// This widget is used both inline within AuthScreen (rendered directly at
  /// '/home' by HomePage's Consumer<AuthProvider>) and within SignUpScreen
  /// (pushed on top of '/home'). Either way, HomePage's own Consumer already
  /// reacted to the auth state change above and reactively swapped its inline
  /// child to VerifyEmailScreen/MainNavigationScreen — popping back to the
  /// first route is a no-op in the inline case and reveals the
  /// already-updated Home when reached via SignUpScreen. Explicitly pushing a
  /// HomePage/VerifyEmailScreen route here raced that reactive swap and
  /// double-mounted HomeScreen (see
  /// .planning/debug/resolved/location-permission-prompt-sh.md).
  void _navigate(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final disabled = auth.isLoading;
        return Column(
          children: [
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: colors.muted)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // Google — white surface + official multi-color "G" mark, no
            // recoloring (Google branding requirement).
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: disabled ? null : () => _google(context),
                icon: SvgPicture.asset(
                  'assets/icons/google_logo.svg',
                  width: 20,
                  height: 20,
                ),
                label: const Text('Continue with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1F1F1F),
                  disabledBackgroundColor: Colors.white70,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            // Apple — black surface + Apple logo (HIG). iOS only for now;
            // Android Apple sign-in (web redirect) is deferred.
            if (Platform.isIOS) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: disabled ? null : () => _apple(context),
                  icon: const Icon(Icons.apple, color: Colors.white, size: 22),
                  label: const Text('Continue with Apple'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black54,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colors.divider),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
