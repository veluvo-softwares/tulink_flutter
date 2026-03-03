import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'features/auth/data/models/user_model.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
<<<<<<< HEAD
import 'features/auth/presentation/screens/auth_screen.dart';
=======
import 'features/auth/presentation/screens/sign_up_screen.dart';
>>>>>>> 45fc50b (feat: implement centralized navigation router with onGenerateRoute)
import 'core/theme/theme_provider.dart';

void main() async {
  // Ensure Flutter framework is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Hive adapters
  Hive.registerAdapter(UserModelAdapter());

  // Initialize service locator and all dependencies
  final serviceLocator = ServiceLocator();
  await serviceLocator.init();

  runApp(MyApp(serviceLocator: serviceLocator));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.serviceLocator,
  });

  final ServiceLocator serviceLocator;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme Provider
        ChangeNotifierProvider<ThemeProvider>.value(
          value: serviceLocator.themeProvider,
        ),
        // Auth Provider
        ChangeNotifierProvider<AuthProvider>.value(
          value: serviceLocator.authProvider,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'TuLink Flutter',
            debugShowCheckedModeBanner: false,
            
            // Theme configuration - Tu-Link dark theme only
            theme: AppTheme.tulinkTheme,
            darkTheme: AppTheme.tulinkTheme,
            themeMode: ThemeMode.dark, // Tu-Link is dark mode only
            
            // Centralized routing with onGenerateRoute
            onGenerateRoute: AppRouter.generateRoute,
            
            // Initial route
            initialRoute: HomePage.routeName,
          );
        },
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  /// Route name for navigation
  static const String routeName = '/home';
  
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TuLink Flutter'),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                icon: Icon(
                  themeProvider.isDarkMode 
                      ? Icons.light_mode 
                      : Icons.dark_mode,
                ),
                onPressed: () {
                  themeProvider.toggleTheme();
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!authProvider.isSignedIn) {
            return const SignUpScreen();
          } else {
            return _buildSignedOutView(context, authProvider);
          }
        },
      ),
    );
  }


  Widget _buildSignedOutView(BuildContext context, AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (authProvider.hasError)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authProvider.errorMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clean Architecture Demo',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This is a professional Flutter project structure following Clean Architecture principles.',
                  ),
                  const SizedBox(height: 8),
                  const Text('Architecture layers:'),
                  const SizedBox(height: 4),
                  const Text('• Domain: Entities, Repositories, Use Cases'),
                  const Text('• Data: Models, Data Sources, Repository Impl'),
                  const Text('• Presentation: Pages, Providers, Widgets'),
                  const SizedBox(height: 16),
                  const Text('Key features implemented:'),
                  const SizedBox(height: 4),
                  const Text('• Feature-first directory structure'),
                  const Text('• Repository pattern with caching'),
                  const Text('• Dio HTTP client with interceptors'),
                  const Text('• Hive local storage'),
                  const Text('• Flutter Secure Storage'),
                  const Text('• Provider state management'),
                  const Text('• Material 3 theming'),
                  const Text('• Centralized error handling'),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Note: This demo uses mock authentication. '
            'In production, connect to your actual API.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AuthScreen(),
                  ),
                );
              },
              child: const Text('Sign In / Sign Up'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pushNamed(context, Routes.signUp);
              },
              child: const Text('Go to Sign-Up Screen'),
            ),
          ),
        ],
      ),
    );
  }
}