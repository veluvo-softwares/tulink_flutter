import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/services/journey_location_service.dart';
import 'package:tulink_flutter/core/services/location_service.dart';
import 'package:tulink_flutter/features/maps/presentation/providers/navigation_provider.dart';
import 'package:tulink_flutter/features/maps/presentation/services/voice_instruction_service.dart';

class _TestVoiceInstructionService extends VoiceInstructionService {
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice navigation preference is restored and saved', () async {
    bool? savedValue;
    final provider = NavigationProvider(
      journeyLocationService: JourneyLocationService(
        const GeolocatorLocationService(),
      ),
      voiceService: _TestVoiceInstructionService(),
      loadVoiceEnabled: () async => false,
      saveVoiceEnabled: (enabled) async => savedValue = enabled,
    );

    await provider.initializePreferences();
    expect(provider.isVoiceEnabled, isFalse);

    provider.setVoiceEnabled(true);
    await Future<void>.delayed(Duration.zero);

    expect(provider.isVoiceEnabled, isTrue);
    expect(savedValue, isTrue);
    provider.dispose();
  });
}
