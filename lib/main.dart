import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/maps/presentation/tulink_map_screen.dart';

import 'core/config/app_config.dart';
import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/main_navigation_screen.dart';
import 'features/auth/data/models/user_model.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'core/theme/theme_provider.dart';
import 'features/maps/presentation/providers/map_provider.dart';
import 'features/journeys/presentation/providers/journey_provider.dart';
// import 'features/journeys/presentation/providers/invitation_provider.dart';

void main() async {
  // Ensure Flutter framework is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");

  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Hive adapters
  Hive.registerAdapter(UserModelAdapter());

  // Initialize service locator and all dependencies
  final serviceLocator = ServiceLocator();
  await serviceLocator.init();

  // Initialize Mapbox with access token before running the app
  MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);

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
        // Map Provider
        ChangeNotifierProvider<MapProvider>.value(
          value: serviceLocator.mapProvider,
        ),
        // Journey Provider
        ChangeNotifierProvider<JourneyProvider>.value(
          value: serviceLocator.journeyProvider,
        ),
        // Invitation Provider
        // ChangeNotifierProvider<InvitationProvider>.value(
        //   value: serviceLocator.invitationProvider,
        // ),
        // Analytics Provider
        ChangeNotifierProvider.value(
          value: serviceLocator.analyticsProvider,
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
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!authProvider.isSignedIn) {
            return const AuthScreen();
          } else {
            return const MainNavigationScreen();
          }
        },
      ),
    );
  }

}