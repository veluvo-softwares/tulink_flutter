import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/entities/maneuver.dart';

/// Speaks turn-by-turn instructions aloud using the device's text-to-speech
/// engine.
///
/// Tracks which announcement thresholds have fired for the current maneuver
/// so the same warning isn't spoken twice. Resets when the current maneuver
/// changes.
class VoiceInstructionService {
  final FlutterTts _tts = FlutterTts();

  bool _isInitialised = false;
  int? _currentManeuverIndex;
  bool _warned500m = false;
  bool _warned100m = false;
  bool _spokenArrival = false;

  /// Whether voice instructions are enabled. Defaults to true.
  bool isEnabled = true;

  /// Initialise the TTS engine. Must be called once before any [announce]
  /// invocation. Safe to call repeatedly; subsequent calls are no-ops.
  Future<void> init() async {
    if (_isInitialised) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _isInitialised = true;
    print('🎙️ VoiceInstructionService initialised');
  }

  /// Speak an announcement for the given maneuver if a distance threshold
  /// is crossed. Each threshold fires at most once per maneuver.
  Future<void> announce({
    required Maneuver maneuver,
    required double distanceToManeuverMetres,
    required bool isFinalManeuver,
  }) async {
    if (!isEnabled || !_isInitialised) return;

    if (_currentManeuverIndex != maneuver.index) {
      _currentManeuverIndex = maneuver.index;
      _warned500m = false;
      _warned100m = false;
      _spokenArrival = false;
    }

    if (isFinalManeuver && distanceToManeuverMetres < 50 && !_spokenArrival) {
      _spokenArrival = true;
      await _speak('You have arrived at your destination.');
      return;
    }

    if (distanceToManeuverMetres < 500 &&
        distanceToManeuverMetres >= 100 &&
        !_warned500m) {
      _warned500m = true;
      await _speak('In 500 metres, ${maneuver.instruction}');
      return;
    }

    if (distanceToManeuverMetres < 100 && !_warned100m) {
      _warned100m = true;
      await _speak(maneuver.instruction);
      return;
    }
  }

  /// Force an immediate spoken message regardless of thresholds. Used
  /// for reroute notifications and convoy events.
  Future<void> speakImmediate(String message) async {
    if (!isEnabled || !_isInitialised) return;
    await _speak(message);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
      print('🎙️ Spoke: "$text"');
    } catch (e) {
      print('⚠️ TTS speak failed: $e');
    }
  }

  /// Stop any in-progress utterance and clear queued announcements.
  Future<void> stop() async {
    if (!_isInitialised) return;
    await _tts.stop();
    _currentManeuverIndex = null;
    _warned500m = false;
    _warned100m = false;
    _spokenArrival = false;
  }

  /// Release the TTS engine. Called on app shutdown.
  Future<void> dispose() async {
    await _tts.stop();
    _isInitialised = false;
  }
}
