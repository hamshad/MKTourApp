import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  AudioService._privateConstructor();
  static final AudioService instance = AudioService._privateConstructor();

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      // Configure audio context to play even when device is on silent/vibrate
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {
              AVAudioSessionOptions.duckOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('⚠️ [AudioService] Initialization error: $e');
    }
  }

  /// Play the app notification sound from assets (non-looping, low latency).
  Future<void> playNotification() async {
    try {
      await _ensureInitialized();
      debugPrint('🔊 [AudioService] Playing Ringtone.wav...');
      await _player.play(
        AssetSource('Ringtone.wav'),
      );
    } catch (e) {
      debugPrint('⚠️ [AudioService] Error playing audio: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
