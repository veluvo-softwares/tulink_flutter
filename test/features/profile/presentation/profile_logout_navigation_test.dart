import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/auth/domain/entities/user_entity.dart';
import 'package:tulink_flutter/features/auth/domain/repositories/auth_repository.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/navigation_provider.dart';
import 'package:tulink_flutter/features/profile/presentation/screens/profile_screen.dart';

@GenerateNiceMocks([
  MockSpec<AuthRepository>(),
  MockSpec<AnalyticsProvider>(),
  MockSpec<ConvoyProvider>(),
  MockSpec<NavigationProvider>(),
])
import 'profile_logout_navigation_test.mocks.dart';

void main() {
  testWidgets('successful profile sign-out returns to the existing auth root', (
    tester,
  ) async {
    final repository = MockAuthRepository();
    final analytics = MockAnalyticsProvider();
    final convoy = MockConvoyProvider();
    final navigation = MockNavigationProvider();
    final navigatorKey = GlobalKey<NavigatorState>();
    final user = UserEntity(
      id: 'user-1',
      email: 'driver@tulink.app',
      name: 'TuLink Driver',
      isEmailVerified: true,
      createdAt: DateTime(2026),
    );

    when(repository.isSignedIn()).thenAnswer((_) async => true);
    when(
      repository.getCurrentUser(),
    ).thenAnswer((_) async => (user: user, failure: null));
    when(
      repository.signOut(),
    ).thenAnswer((_) async => (success: true, failure: null));
    when(analytics.loadJourneyHistory()).thenAnswer((_) async {});
    when(analytics.journeyHistory).thenReturn(const []);
    when(convoy.stopUserChannel()).thenAnswer((_) async {});
    when(navigation.isVoiceEnabled).thenReturn(false);

    final auth = AuthProvider(repository);
    await auth.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AnalyticsProvider>.value(value: analytics),
          ChangeNotifierProvider<ConvoyProvider>.value(value: convoy),
          ChangeNotifierProvider<NavigationProvider>.value(value: navigation),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.tulinkTheme,
          home: Consumer<AuthProvider>(
            builder: (context, provider, _) {
              if (!provider.isSignedIn) {
                return const Scaffold(body: Text('AUTH_ROOT'));
              }
              return Scaffold(
                body: Builder(
                  builder: (routeContext) => TextButton(
                    key: const Key('open-profile'),
                    onPressed: () => Navigator.of(routeContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen(),
                      ),
                    ),
                    child: const Text('Open profile'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('AUTH_ROOT'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    verify(convoy.stopUserChannel()).called(1);
    verify(repository.signOut()).called(1);
  });
}
