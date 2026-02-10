import 'package:audioplayers/audioplayers.dart';

class AudioService {
  AudioService._privateConstructor();
  static final AudioService instance = AudioService._privateConstructor();

  final AudioPlayer _player = AudioPlayer();

  /// Play the app notification sound from assets (non-looping, low latency).
  Future<void> playNotification() async {
    try {
      await _player.play(AssetSource('assets/Ringtone.wav'),
          mode: PlayerMode.lowLatency);
    } catch (e) {
      // ignore errors silently for now
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
