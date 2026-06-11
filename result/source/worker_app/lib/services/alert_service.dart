import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

/// 음성 안내 + 부저음 알림 서비스
/// 스마트폰에서 직접 재생
class AlertService {
  static const String _stopWarningMessage =
      '장시간 정지가 감지되었습니다. 안전 여부를 확인해 주십시오.';

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // TTS 초기화
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.5);  // 느리게 - 현장 소음 고려
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _isInitialized = true;
  }

  /// 장시간 정지 감지 시 알림 (음성 + 삐용삐용 부저)
  Future<void> playStopAlert() async {
    await init();

    // 삐용삐용 부저 먼저 재생
    await _playBuzzer();

    // 잠시 후 음성 안내
    await Future.delayed(const Duration(milliseconds: 800));
    await _playVoiceGuide(_stopWarningMessage);
  }

  /// 부저음 재생 (삐용삐용 - 위험 신호)
  Future<void> _playBuzzer() async {
    try {
      // assets/sounds/buzzer_alert.mp3 파일 필요
      // 없을 경우 시스템 알람 사운드로 대체
      await _audioPlayer.play(AssetSource('sounds/buzzer_alert.mp3'));
    } catch (e) {
      // 파일 없을 때 fallback: 시스템 비프음
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    }
  }

  /// 음성 안내 재생
  Future<void> _playVoiceGuide(String message) async {
    await _tts.speak(message);
  }

  /// 커스텀 음성 메시지
  Future<void> playCustomVoice(String message) async {
    await init();
    await _tts.speak(message);
  }

  /// 정지 해제 안내
  Future<void> playResumedAlert() async {
    await init();
    await _playVoiceGuide('움직임이 감지되었습니다. 정상 상태로 전환합니다.');
  }

  void dispose() {
    _tts.stop();
    _audioPlayer.dispose();
  }
}
