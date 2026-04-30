import 'package:flutter/material.dart';
import 'dart:async';
import '../services/stop_detection_controller.dart';
import '../services/push_notifier.dart';

class StopDetectionScreen extends StatefulWidget {
  final String workerId;
  final String workerName;

  const StopDetectionScreen({
    super.key,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<StopDetectionScreen> createState() => _StopDetectionScreenState();
}

class _StopDetectionScreenState extends State<StopDetectionScreen>
    with SingleTickerProviderStateMixin {
  late StopDetectionController _controller;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isRunning = false;
  bool _isAlertActive = false;
  int _stopSeconds = 0;
  StopAlertEvent? _lastAlert;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _controller = StopDetectionController(
      workerId: widget.workerId,
      workerName: widget.workerName,
      hardwareUrl: 'http://192.168.1.108:5000', // TODO: 실제 주소로 변경
      pushNotifier: MockPushNotifier(), // TODO: FcmPushNotifier로 교체
      onAlertTriggered: (event) {
        setState(() {
          _isAlertActive = true;
          _lastAlert = event;
        });
        _pulseController.repeat(reverse: true);
      },
      onMovementResumed: () {
        setState(() {
          _isAlertActive = false;
          _stopSeconds = 0;
        });
        _pulseController.stop();
        _pulseController.reset();
      },
    );
  }

  @override
  void dispose() {
    _controller.stop();
    _pulseController.dispose();
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    try {
      await _controller.start();
      setState(() => _isRunning = true);

      // UI 타이머: 정지 시간 실시간 업데이트
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _stopSeconds = _controller.currentStopDurationSeconds;
          });
        }
      });
    } catch (e) {
      _showErrorDialog(e.toString());
    }
  }

  void _stopMonitoring() {
    _controller.stop();
    _uiTimer?.cancel();
    setState(() {
      _isRunning = false;
      _isAlertActive = false;
      _stopSeconds = 0;
    });
    _pulseController.stop();
    _pulseController.reset();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isAlertActive ? const Color(0xFFB71C1C) : Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          '장시간 정지 감지',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 작업자 정보
              _buildWorkerInfo(),

              // 중앙 상태 표시
              _buildStatusDisplay(),

              // 하단 컨트롤
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Text(
            '${widget.workerName}  |  ID: ${widget.workerId}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDisplay() {
    if (!_isRunning) {
      return Column(
        children: [
          Icon(Icons.sensors_off, color: Colors.grey[600], size: 80),
          const SizedBox(height: 16),
          Text(
            '모니터링 비활성',
            style: TextStyle(color: Colors.grey[500], fontSize: 18),
          ),
        ],
      );
    }

    return Column(
      children: [
        // 경고 상태 표시
        if (_isAlertActive) ...[
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red[700],
                border: Border.all(color: Colors.red[300]!, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_rounded, color: Colors.white, size: 60),
                  Text(
                    '정지 감지!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_lastAlert != null)
            _buildAlertInfo(_lastAlert!),
        ] else ...[
          // 정상 상태
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green[800],
              border: Border.all(color: Colors.green[400]!, width: 3),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 60),
                Text(
                  '정상',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 정지 시간 게이지
          _buildStopTimer(),
        ],
      ],
    );
  }

  Widget _buildStopTimer() {
    final progress = (_stopSeconds / 60).clamp(0.0, 1.0);
    final remaining = (60 - _stopSeconds).clamp(0, 60);

    return Column(
      children: [
        Text(
          '정지 시간: ${_stopSeconds}초',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[700],
            valueColor: AlwaysStoppedAnimation<Color>(
              progress > 0.8 ? Colors.red : progress > 0.5 ? Colors.orange : Colors.green,
            ),
            minHeight: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          progress >= 1.0 ? '경고 발생!' : '${remaining}초 후 경고',
          style: TextStyle(
            color: progress > 0.8 ? Colors.orange[300] : Colors.grey[500],
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertInfo(StopAlertEvent event) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ 관리자에게 알림 전송됨',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '정지 시간: ${event.stopDurationSeconds}초',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            '위치: ${event.position.latitude.toStringAsFixed(5)}, '
            '${event.position.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            '시각: ${_formatTime(event.timestamp)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isRunning ? _stopMonitoring : _startMonitoring,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isRunning ? Colors.grey[700] : Colors.blue[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
        label: Text(
          _isRunning ? '모니터링 중지' : '모니터링 시작',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
