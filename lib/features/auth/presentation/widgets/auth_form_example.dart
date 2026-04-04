import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/car_toast_service.dart';
import '../providers/auth_provider.dart';

/// Example of how to integrate car toasts with authentication forms
class AuthFormExample extends StatefulWidget {
  const AuthFormExample({super.key});

  @override
  State<AuthFormExample> createState() => _AuthFormExampleState();
}

class _AuthFormExampleState extends State<AuthFormExample> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header with car emoji
              const Text(
                '🚗 TuLink Auth',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Watch the toasts drive by!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),

              // Auth Form
              _buildAuthForm(),
              
              const SizedBox(height: 24),
              
              // Toggle between Sign In / Sign Up
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSignUp = !_isSignUp;
                  });
                },
                child: Text(
                  _isSignUp 
                    ? 'Already have an account? Sign In' 
                    : 'Need an account? Sign Up',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Demo Buttons
              _buildDemoButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Column(
          children: [
            // Email Field
            _buildTextField(
              controller: _emailController,
              hintText: 'Email',
              icon: Icons.email,
            ),
            const SizedBox(height: 16),
            
            // Password Field
            _buildTextField(
              controller: _passwordController,
              hintText: 'Password',
              icon: Icons.lock,
              obscureText: true,
            ),
            
            // Name Field (Sign Up only)
            if (_isSignUp) ...[
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                hintText: 'Full Name',
                icon: Icons.person,
              ),
            ],
            
            const SizedBox(height: 32),
            
            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: authProvider.isLoading ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: authProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        _isSignUp ? 'Create Account' : 'Sign In',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildDemoButtons() {
    return Column(
      children: [
        const Text(
          'Demo Toasts:',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDemoButton(
                'Success',
                Colors.green,
                () => context.showSuccessToast('Login successful! 🎉'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDemoButton(
                'Warning',
                Colors.orange,
                () => context.showWarningToast('Check your connection ⚠️'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDemoButton(
                'Error',
                Colors.red,
                () => context.showErrorToast('Invalid credentials ❌'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDemoButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  void _handleSubmit() async {
    final authProvider = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      context.showErrorToast('Please fill in all required fields');
      return;
    }

    if (_isSignUp && name.isEmpty) {
      context.showErrorToast('Please enter your name');
      return;
    }

    // Attempt authentication
    bool success;
    if (_isSignUp) {
      success = await authProvider.signUp(
        email: email,
        password: password,
        name: name,
      );
    } else {
      success = await authProvider.signIn(
        email: email,
        password: password,
      );
    }

    // Clear fields on successful sign up
    if (success && _isSignUp) {
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}