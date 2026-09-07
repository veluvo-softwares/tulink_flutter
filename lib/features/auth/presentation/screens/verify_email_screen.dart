import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/layout/tulink_breakpoints.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/email_verification_provider.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  static const String routeName = '/verify-email';

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final EmailVerificationProvider _verificationProvider;

  @override
  void initState() {
    super.initState();
    _verificationProvider = context.read<EmailVerificationProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificationProvider.startPolling();
    });
  }

  @override
  void dispose() {
    _verificationProvider.stopPolling();
    super.dispose();
  }

  Future<void> _handleResend() async {
    await context.read<EmailVerificationProvider>().resendVerificationEmail();
  }

  Future<void> _handleSignOut() async {
    final success = await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    if (success) {
      // This screen is always reached inline within HomePage's
      // Consumer<AuthProvider> at '/home' — that Consumer already reacted to
      // isSignedIn flipping false above and reactively swapped its child back
      // to AuthScreen. Pushing a standalone AuthScreen route here used to
      // fight that reactive swap (a duplicate route momentarily coexisting
      // with the reactively-updated one) and could double-mount screens; a
      // no-op pop is enough since we're already at the first (only) route.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      CarToastService.showError("Couldn't sign out — please try again");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Scaffold(
          backgroundColor: colors.warmSand,
          appBar: AppBar(
            leading: IconButton.filledTonal(
              tooltip: 'Sign out and return to login',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: authProvider.isLoading ? null : _handleSignOut,
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, _) {
                final wide = TulinkBreakpoints.isWideLandscape(context);
                final details = _VerificationDetails(
                  isSigningOut: authProvider.isLoading,
                  onResend: _handleResend,
                );
                if (!wide) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            const SizedBox(height: 24),
                            _VerificationIllustration(color: colors.routeTeal),
                            const SizedBox(height: 32),
                            details,
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _VerificationIllustration(
                          color: colors.routeTeal,
                          size: 180,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: colors.surface,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Padding(
                              padding: const EdgeInsets.all(48),
                              child: details,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _VerificationIllustration extends StatelessWidget {
  const _VerificationIllustration({required this.color, this.size = 80});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/email_verification.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class _VerificationDetails extends StatelessWidget {
  const _VerificationDetails({
    required this.isSigningOut,
    required this.onResend,
  });

  final bool isSigningOut;
  final Future<void> Function() onResend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check your inbox',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Consumer<EmailVerificationProvider>(
          builder: (context, provider, child) => Text(
            'We sent a verification link to ${provider.userEmail ?? ''}. '
            'Tap the link in the email to continue. Can\'t find it? Check '
            'your spam or junk folder.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.muted),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 40),
        Consumer<EmailVerificationProvider>(
          builder: (context, provider, child) => ElevatedButton(
            onPressed: provider.canResend ? onResend : null,
            child: Text(
              provider.canResend
                  ? 'Resend verification email'
                  : 'Resend in ${provider.resendCooldownSeconds}s',
            ),
          ),
        ),
        if (isSigningOut) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.muted,
                ),
              ),
              const SizedBox(width: 8),
              Text('Signing out...', style: TextStyle(color: colors.muted)),
            ],
          ),
        ],
      ],
    );
  }
}
