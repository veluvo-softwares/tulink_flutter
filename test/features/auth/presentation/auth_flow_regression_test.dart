import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/auth/domain/entities/user_entity.dart';
import 'package:tulink_flutter/features/auth/domain/repositories/auth_repository.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/features/auth/presentation/widgets/auth_brand_header.dart';
import 'package:tulink_flutter/main.dart';

@GenerateMocks([AuthRepository])
import 'auth_flow_regression_test.mocks.dart';

void main() {
  testWidgets(
    'a failed sign in completes, keeps credentials mounted, and reports the '
    'failure exactly once',
    (tester) async {
      final repository = MockAuthRepository();
      final signInResult =
          Completer<({UserEntity? user, String? token, Failure? failure})>();

      when(repository.isSignedIn()).thenAnswer((_) async => false);
      when(
        repository.signIn(
          email: anyNamed('email'),
          password: anyNamed('password'),
        ),
      ).thenAnswer((_) => signInResult.future);

      final auth = AuthProvider(repository);
      await auth.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.tulinkTheme,
            home: const HomePage(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'you@example.com'),
        'driver@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your password'),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await tester.pump();

      expect(find.text('driver@example.com'), findsOneWidget);
      expect(find.text('wrong-password'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      signInResult.complete((
        user: null,
        token: null,
        failure: const AuthFailure(message: 'Invalid email or password'),
      ));
      await tester.pump();

      // What the user typed survives the failure — retyping a password to see
      // an error message is the regression this test was written for.
      expect(find.text('driver@example.com'), findsOneWidget);
      expect(find.text('wrong-password'), findsOneWidget);

      // The request really completed. A sign-in that leaves the button spinning
      // forever is indistinguishable from a slow network, and that is exactly
      // what a 401 used to do when the auth interceptor tried to refresh a
      // session the user did not have yet.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the button must return to its idle state',
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Sign in'),
            )
            .onPressed,
        isNotNull,
        reason: 'the user must be able to try again',
      );

      // The failure is held on the provider, which is what the error toast
      // renders from.
      expect(auth.hasError, isTrue);
      expect(auth.errorMessage, 'Invalid email or password');

      // ...and it is reported in exactly one place. The inline banner was
      // removed because `AuthProvider.signIn` already raises an error toast for
      // the same failure, so both said the same thing twice.
      expect(
        find.byType(AuthErrorBanner),
        findsNothing,
        reason: 'the toast is the single error surface on this screen',
      );
      expect(find.text('Invalid email or password'), findsNothing);
    },
  );
}
