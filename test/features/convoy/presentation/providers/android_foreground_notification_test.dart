import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';

void main() {
  test('foreground location service uses TuLink launcher resource', () {
    const icon = ConvoyProvider.androidForegroundNotificationIcon;

    expect(icon.name, 'launcher_icon');
    expect(icon.defType, 'mipmap');

    final resourceFiles = Directory('android/app/src/main/res')
        .listSync()
        .whereType<Directory>()
        .where((directory) => directory.path.contains('mipmap-'))
        .map((directory) => File('${directory.path}/${icon.name}.png'));

    expect(resourceFiles, isNotEmpty);
    expect(resourceFiles.every((file) => file.existsSync()), isTrue);
  });

  test('FCM default notification uses the same shipped icon', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_icon'),
    );
    expect(manifest, contains('android:resource="@mipmap/launcher_icon"'));
  });

  test('conventional native notification icon aliases the shipped icon', () {
    final aliases = File(
      'android/app/src/main/res/values/notification_resources.xml',
    ).readAsStringSync();

    expect(aliases, contains('name="ic_launcher" type="mipmap"'));
    expect(aliases, contains('@mipmap/launcher_icon'));
  });
}
