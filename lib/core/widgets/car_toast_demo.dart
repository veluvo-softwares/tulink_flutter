import 'package:flutter/material.dart';
import '../services/car_toast_service.dart';

/// Demo screen to showcase the car toast animations
/// This can be used for testing and demonstration purposes
class CarToastDemo extends StatelessWidget {
  const CarToastDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // Dark theme
      appBar: AppBar(
        title: const Text('Car Toast Demo'),
        backgroundColor: const Color(0xFF2D2D2D),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Car Toast Animations',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Watch the toasts drive across your screen like cars! 🚗',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            
            // Success Toast Button
            _buildToastButton(
              context: context,
              label: 'Success Toast',
              description: 'Shows green success message',
              color: const Color(0xFF10B981),
              onPressed: () => context.showSuccessToast(
                'Welcome back, John! Your journey continues.',
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Warning Toast Button
            _buildToastButton(
              context: context,
              label: 'Warning Toast',
              description: 'Shows orange warning/info message',
              color: const Color(0xFFF59E0B),
              onPressed: () => context.showWarningToast(
                'Your journey will start in 2 minutes. Get ready!',
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Error Toast Button
            _buildToastButton(
              context: context,
              label: 'Error Toast',
              description: 'Shows red error message',
              color: const Color(0xFFEF4444),
              onPressed: () => context.showErrorToast(
                'Authentication failed. Please check your credentials.',
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Authentication Demo Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: Colors.red, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Authentication Flow Demo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'These toasts are automatically triggered during authentication:',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  _buildAuthExample('✅ Login Success', 'Welcome back, [Name]!'),
                  _buildAuthExample('❌ Login Failed', 'Invalid credentials'),
                  _buildAuthExample('✅ Sign Up Success', 'Account created successfully!'),
                  _buildAuthExample('📧 Password Reset', 'Reset email sent!'),
                  _buildAuthExample('👋 Sign Out', 'See you next time!'),
                ],
              ),
            ),
            
            const Spacer(),
            
            const Text(
              'Car-like Movement:\n• Slides in from left\n• Pauses for 2 seconds\n• Drives off to the right',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToastButton({
    required BuildContext context,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthExample(String event, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(event, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '→ "$message"',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}