import 'package:geolocator/geolocator.dart';
import 'stop_detection_service.dart';
import 'alert_service.dart';
import 'hardware_notifier.dart';
import 'push_notifier.dart';

/// 장시간 정지 기능 통합 컨트롤러
/// StopDetectionService + AlertService + HardwareNotifier + PushNotifier 조율
class StopDetectionController {
  final String workerId;
  final String workerName;

  late final StopDetectionService _detectionService;
  late final AlertService _alertService;
  late final HardwareNotifier _hardwareNotifier;
  late final PushNotifier _pushNotifier;

  // 상태 콜백
  final void Function(StopAlertEvent event)? onAlertTriggered;
  final void Function()? onMovementResumed;
  final void Function(int seconds)? onStopDurationUpdated;

  StopDetectionController({
    required this.workerId,
    required this.workerName,
    required String hardwareUrl,
    required PushNotifier pushNotifier,
    this.onAlertTriggered,
    this.onMovementResumed,
    this.onStopDurationUpdated,
  }) {
    _alertService = AlertService();
    _hardwareNotifier = HardwareNotifier(hardwareBaseUrl: hardwareUrl);
    _pushNotifier = pushNotifier;

    _detectionService = StopDetectionService(
      onStopDetected: _handleStopDetected,
      onMovementResumed: _handleMovementResumed,
    );
  }

  Future<void> start() async {
    // 위치 권한 확인
    await _checkLocationPermission();
    await _detectionService.start();
  }

  void stop() {
    _detectionService.stop();
    _alertService.dispose();
  }

  Future<void> _handleStopDetected(Position position) async {
    final duration = _detectionService.currentStopDurationSeconds;

    final event = StopAlertEvent(
      workerId: workerId,
      workerName: workerName,
      position: position,
      stopDurationSeconds: duration,
      timestamp: DateTime.now(),
    );

    onAlertTriggered?.call(event);

    // 병렬 실행: 음성/부저 + 하드웨어 알림 + 푸시 알림
    await Future.wait([
      // 1. 스마트폰 음성 안내 + 부저음
      _alertService.playStopAlert(),

      // 2. 현장 하드웨어 장치 알림 (삐용삐용 적색 부저)
      _hardwareNotifier.sendStopAlert(
        workerId: workerId,
        position: position,
        stopDurationSeconds: duration,
      ),

      // 3. 관리자 푸시 알림 + 정지 위치 전송
      _pushNotifier.sendStopAlert(
        workerId: workerId,
        workerName: workerName,
        position: position,
        stopDurationSeconds: duration,
      ),
    ]);
  }

  Future<void> _handleMovementResumed() async {
    onMovementResumed?.call();

    await Future.wait([
      _alertService.playResumedAlert(),
      _hardwareNotifier.sendStopResolved(workerId: workerId),
    ]);
  }

  Future<void> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('위치 권한이 거부되었습니다. 설정에서 허용해주세요.');
    }
  }

  int get currentStopDurationSeconds =>
      _detectionService.currentStopDurationSeconds;
  bool get isStopDetected => _detectionService.isStopDetected;
  bool get isRunning => _detectionService.isRunning;
}

/// 정지 감지 이벤트 데이터 모델
class StopAlertEvent {
  final String workerId;
  final String workerName;
  final Position position;
  final int stopDurationSeconds;
  final DateTime timestamp;

  StopAlertEvent({
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.stopDurationSeconds,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'worker_id': workerId,
        'worker_name': workerName,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'stop_duration_seconds': stopDurationSeconds,
        'timestamp': timestamp.toIso8601String(),
      };
}
