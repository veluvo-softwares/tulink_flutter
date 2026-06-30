import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/main.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/verify_email_screen.dart';

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
    if (ok) _navigate(context, auth);
  }

  Future<void> _apple(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithApple();
    if (!context.mounted) return;
    if (ok) _navigate(context, auth);
  }

  /// Social emails arrive already verified, so this lands on HomePage; the
  /// verify branch is kept for parity with the email flow.
  void _navigate(BuildContext context, AuthProvider auth) {
    Navigator.of(context).pushReplacementNamed(
      auth.isEmailVerified ? HomePage.routeName : VerifyEmailScreen.routeName,
    );
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
                  child: Text('or', style: TextStyle(color: colors.silver)),
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
                    borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.brushedSteel),
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
