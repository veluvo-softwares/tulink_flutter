import 'package:flutter/material.dart';

import 'package:tulink_flutter/core/theme/tulink_colors.dart';

/// Screen displayed when navigating to an undefined/unknown route
/// Prevents app crashes and provides helpful feedback to users
class UndefinedRouteScreen extends StatelessWidget {
  /// Route name for navigation  
  static const String routeName = '/undefined';
  
  /// The route name that was not found
  final String undefinedRouteName;

  /// Constructor requiring the undefined route name
  const UndefinedRouteScreen({
    super.key,
    required this.undefinedRouteName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tulinkColors = theme.extension<TulinkColors>()!;
    
    return Scaffold(
      backgroundColor: tulinkColors.carbonBlack,
      appBar: AppBar(
        title: const Text('Route Not Found'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 80,
                color: tulinkColors.electricRed,
              ),
              const SizedBox(height: 24),
              Text(
                '404 - Route Not Found',
                style: theme.textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'The route "$undefinedRouteName" does not exist.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Please check the URL or use the navigation menu.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  },
                  child: const Text('Go to Home'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}