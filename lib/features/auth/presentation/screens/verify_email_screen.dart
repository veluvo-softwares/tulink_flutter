import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/navigation/main_navigation_screen.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/email_verification_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/screens/auth_screen.dart';

/// Screen shown to users whose email is not yet verified.
///
/// Auto-polls every 5 s for verification status and navigates to
/// [MainNavigationScreen] when verified. Provides a resend button with a
/// 60-second cooldown and a sign-out path for switching accounts.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  static const String routeName = '/verify-email';

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmailVerificationProvider>().startPolling();
    });
  }

  @override
  void dispose() {
    context.read<EmailVerificationProvider>().stopPolling();
    super.dispose();
  }

  Future<void> _handleResend() async {
    await context.read<EmailVerificationProvider>().resendVerificationEmail();
  }

  Future<void> _handleSignOut() async {
    final success = await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    if (success) {
      await Navigator.of(context).pushNamedAndRemoveUntil(
        AuthScreen.routeName,
        (route) => false,
      );
    } else {
      CarToastService.showError("Couldn't sign out — please try again");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              SvgPicture.asset(
                'assets/icons/email_verification.svg',
                width: 80,
                height: 80,
                colorFilter: ColorFilter.mode(
                  colors.electricRed,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Check your inbox',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Consumer<EmailVerificationProvider>(
                builder: (context, provider, child) {
                  // Auto-navigate when email is verified (SCR-02)
                  if (provider.isEmailVerified) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          MainNavigationScreen.routeName,
                          (route) => false,
                        );
                      }
                    });
                  }
                  return Text(
                    'We sent a verification link to'
                    ' ${provider.userEmail ?? ''}.'
                    ' Tap the link in the email to continue.'
                    " Can't find it? Check your spam or junk folder.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.silver,
                        ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 40),
              // Resend button (SCR-03, SCR-04)
              Consumer<EmailVerificationProvider>(
                builder: (context, provider, child) {
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.electricRed),
                        foregroundColor: colors.electricRed,
                        backgroundColor: Colors.transparent,
                      ),
                      onPressed: provider.canResend ? _handleResend : null,
                      child: Text(
                        provider.canResend
                            ? 'Resend'
                            : 'Resend in ${provider.resendCooldownSeconds}s',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Sign-out button (SCR-07)
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return TextButton(
                    onPressed:
                        authProvider.isLoading ? null : _handleSignOut,
                    child: authProvider.isLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.silver,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Signing out...',
                                style: TextStyle(color: colors.silver),
                              ),
                            ],
                          )
                        : Text(
                            'Use a different account',
                            style: TextStyle(color: colors.silver),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
