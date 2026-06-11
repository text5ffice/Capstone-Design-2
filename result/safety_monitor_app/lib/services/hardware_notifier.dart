import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// 현장 하드웨어 장치 알림 서비스
/// 라즈베리파이/아두이노 등 현장 장치에 HTTP 신호 전송
class HardwareNotifier {
  final String hardwareBaseUrl; // 예: 'http://192.168.1.100:5000'

  static const Duration _timeout = Duration(seconds: 3);

  HardwareNotifier({required this.hardwareBaseUrl});

  /// 장시간 정지 이벤트를 현장 하드웨어에 전송
  /// → 현장 장치에서 적색 부저 + 삐용삐용 울림
  Future<bool> sendStopAlert({
    required String workerId,
    required Position position,
    required int stopDurationSeconds,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$hardwareBaseUrl/alert/stop'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event_type': 'long_stop',
              'worker_id': workerId,
              'stop_duration_seconds': stopDurationSeconds,
              'location': {
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracy': position.accuracy,
              },
              'timestamp': DateTime.now().toIso8601String(),
              'alert_type': 'red_buzzer_siren', // 삐용삐용 적색 부저
            }),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      // 네트워크 오류 시 로그만 남기고 계속 진행
      print('[HardwareNotifier] 하드웨어 전송 실패: $e');
      return false;
    }
  }

  /// 정지 해제 신호 전송 (부저 중지)
  Future<bool> sendStopResolved({required String workerId}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$hardwareBaseUrl/alert/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event_type': 'long_stop_resolved',
              'worker_id': workerId,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      print('[HardwareNotifier] 해제 신호 전송 실패: $e');
      return false;
    }
  }
}
