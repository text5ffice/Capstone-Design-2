import 'package:flutter/material.dart';
import '../models/alert_model.dart';

class HomeScreen extends StatelessWidget {
  // 가짜 데이터 리스트 (나중에 Flask에서 받아올 데이터)
  final List<AlertModel> dummyAlerts = [
    AlertModel(id: '1', workerName: '최용석', type: '경고', time: '10:30', imageUrl: 'https://via.placeholder.com/150'),
    AlertModel(id: '2', workerName: '김철수', type: '주의', time: '11:05', imageUrl: 'https://via.placeholder.com/150'),
  ];

  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('현장 안전 모니터링')),
      body: ListView.builder(
        itemCount: dummyAlerts.length,
        itemBuilder: (context, index) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.warning, color: dummyAlerts[index].type == '경고' ? Colors.red : Colors.orange),
              title: Text('${dummyAlerts[index].workerName} - ${dummyAlerts[index].type}'),
              subtitle: Text('발생 시간: ${dummyAlerts[index].time}'),
              onTap: () {
                // 상세 페이지 이동 로직 (추후 구현)
              },
            ),
          );
        },
      ),
    );
  }
}