// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:tulink_flutter/core/di/service_locator.dart';
import 'package:tulink_flutter/features/auth/data/models/user_model.dart';
import 'package:tulink_flutter/main.dart';

void main() {
  group('App Tests', () {
    setUpAll(() async {
      // Initialize test environment
      await Hive.initFlutter();
      Hive.registerAdapter(UserModelAdapter());
    });

    testWidgets('App should build without errors', (WidgetTester tester) async {
      // Initialize service locator for testing
      final serviceLocator = ServiceLocator();
      await serviceLocator.init();

      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(serviceLocator: serviceLocator));

      // Wait for initialization to complete
      await tester.pumpAndSettle();

      // Verify that the app builds and shows the home page
      expect(find.text('TuLink Flutter'), findsOneWidget);
      expect(find.text('Clean Architecture Demo'), findsOneWidget);
    });
  });
}
