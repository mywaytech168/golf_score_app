import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class HomePage extends StatelessWidget {
  final String userEmail;
  final List<CameraDescription> cameras;
  final Map<String, dynamic> todaySwingData; // 新增今日揮桿資料

  const HomePage({
    super.key,
    required this.userEmail,
    required this.cameras,
    required this.todaySwingData, // 接收今日揮桿資料
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Welcome, $userEmail'),
            const SizedBox(height: 16),
            Text(
              'Today\'s Swing Data:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            if (todaySwingData.isNotEmpty)
              ...todaySwingData.entries.map((entry) => Text('${entry.key}: ${entry.value}'))
            else
              const Text('No data available for today.'),
          ],
        ),
      ),
    );
  }
}