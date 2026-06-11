import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// 푸시 알림 인터페이스 (나중에 FCM 외 서비스로 교체 가능)
abstract class PushNotifier {
  Future<bool> sendStopAlert({
    required String workerId,
    required String workerName,
    required Position position,
    required int stopDurationSeconds,
  });
}

/// FCM 기반 푸시 알림 구현체
/// 백엔드 서버를 통해 관리자 앱에 푸시 전송
class FcmPushNotifier implements PushNotifier {
  final String backendUrl; // 예: 'https://your-backend.com/api'
  final String authToken;  // 백엔드 인증 토큰

  FcmPushNotifier({
    required this.backendUrl,
    required this.authToken,
  });

  @override
  Future<bool> sendStopAlert({
    required String workerId,
    required String workerName,
    required Position position,
    required int stopDurationSeconds,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/notifications/stop-alert'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({
              'event_type': 'long_stop',
              'worker_id': workerId,
              'worker_name': workerName,
              'stop_duration_seconds': stopDurationSeconds,
              'location': {
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracy': position.accuracy,
              },
              'timestamp': DateTime.now().toIso8601String(),
              'notification': {
                'title': '⚠️ 장시간 정지 감지',
                'body':
                    '$workerName 작업자가 ${stopDurationSeconds}초 이상 정지 상태입니다.',
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('[PushNotifier] 푸시 알림 전송 실패: $e');
      return false;
    }
  }
}

/// 테스트용 Mock 구현체 (백엔드 없을 때 사용)
class MockPushNotifier implements PushNotifier {
  @override
  Future<bool> sendStopAlert({
    required String workerId,
    required String workerName,
    required Position position,
    required int stopDurationSeconds,
  }) async {
    print('[MockPush] 관리자 알림 전송:');
    print('  작업자: $workerName ($workerId)');
    print('  정지 시간: ${stopDurationSeconds}초');
    print('  위치: ${position.latitude}, ${position.longitude}');
    return true;
  }
}
