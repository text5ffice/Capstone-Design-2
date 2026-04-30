class AlertModel {
  final String id;
  final String workerName;
  final String type; // 주의, 경고, 차단
  final String time;
  final String imageUrl;

  AlertModel({
    required this.id,
    required this.workerName,
    required this.type,
    required this.time,
    required this.imageUrl,
  });
}