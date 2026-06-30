import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/tulink_colors.dart';
import '../providers/auth_provider.dart';

/// "Forgot password" screen: the user enters their email and the backend sends
/// a Firebase password-reset link. The new password is then set on Firebase's
/// hosted reset page reached from that email — so this screen's job ends at
/// "we've sent the link".
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  // Flips to the confirmation view after the reset email is requested.
  bool _emailSent = false;
  String _sentTo = '';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Reset password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _emailSent
              ? _buildConfirmation(colors)
              : _buildForm(colors),
        ),
      ),
    );
  }

  Widget _buildForm(TulinkColors colors) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Forgot your password?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the email associated with your account and we\'ll send you '
            'a link to reset your password.',
            style: TextStyle(color: colors.silver),
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _handleSubmit(),
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@') || !value.contains('.')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),

          const SizedBox(height: 24),

          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return ElevatedButton(
                onPressed: authProvider.isLoading ? null : _handleSubmit,
                child: authProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send reset link'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(TulinkColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.mark_email_read_outlined, size: 64, color: colors.electricRed),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'If an account exists for $_sentTo, we\'ve sent a password reset '
          'link. Open it to choose a new password, then sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.silver),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Sign In'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _emailSent = false),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resetPassword(email: email);

    if (!mounted) return;

    if (success) {
      setState(() {
        _emailSent = true;
        _sentTo = email;
      });
    }
    // On failure the provider surfaces a CarToast; stay on the form.
  }
}
