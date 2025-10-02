import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../recorder_page.dart';

/// 首頁提供快速導覽與進入錄影頁面的按鈕
class HomePage extends StatelessWidget {
  final String userEmail; // 使用者登入後的電子郵件
  final List<CameraDescription> cameras; // 傳入鏡頭資訊供後續錄影使用

  const HomePage({super.key, required this.userEmail, required this.cameras});

  // ---------- UI 建構區 ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首頁'),
        backgroundColor: const Color(0xFF1E88E5),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFF90CAF9),
                  child: Icon(Icons.person, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '歡迎回來！',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        userEmail,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '快速功能',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '使用錄影功能記錄揮桿畫面，系統將自動保存影片並協助分析。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // 透過 Navigator 導向原本的 RecorderPage
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RecorderPage(cameras: cameras),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF1E88E5),
                        ),
                        icon: const Icon(Icons.videocam),
                        label: const Text('前往錄影'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
