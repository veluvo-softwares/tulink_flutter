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
import 'package:tulink_flutter/main.dart';

@GenerateMocks([AuthRepository])
import 'auth_flow_regression_test.mocks.dart';

void main() {
  testWidgets(
    'failed sign in keeps credentials mounted and shows a durable error',
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

      expect(find.text('driver@example.com'), findsOneWidget);
      expect(find.text('wrong-password'), findsOneWidget);
      expect(find.text('Invalid email or password'), findsOneWidget);
    },
  );
}
