import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../recorder_page.dart';

/// 首頁提供完整儀表板，呈現揮桿統計、影片庫與分析摘要
class HomePage extends StatefulWidget {
  final String userEmail; // 使用者登入後的電子郵件
  final List<CameraDescription> cameras; // 傳入鏡頭資訊供後續錄影使用

  const HomePage({super.key, required this.userEmail, required this.cameras});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------- 狀態管理區 ----------
  int _currentIndex = 2; // 底部導覽預設聚焦在 Quick Start

  // ---------- 方法區 ----------
  /// 建立統計資訊卡片，方便重複使用與維持一致風格
  Widget _buildStatCard({
    required String title,
    required String value,
    required String subTitle,
    required Color highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF7D8B9A))),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: highlightColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(subTitle, style: const TextStyle(fontSize: 13, color: Color(0xFF1E1E1E))),
        ],
      ),
    );
  }

  /// 建立影片縮圖方塊，模擬設計稿中的 Video Library
  Widget _buildVideoTile(_VideoCardData data) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [data.baseColor, data.baseColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [data.baseColor.withOpacity(0.95), data.baseColor.withOpacity(0.55)],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
                child: const Align(
                  alignment: Alignment.center,
                  child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white24),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.dateLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    data.speedLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(data.stabilityLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF1E8E5A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 處理底部導覽點擊，若選擇錄影則立即導向 RecorderPage
  void _onBottomNavTap(int index) {
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecorderPage(cameras: widget.cameras),
        ),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ---------- 假資料區 ----------
    final videoList = [
      _VideoCardData(
        dateLabel: 'Apr 8',
        speedLabel: '96 MPH',
        stabilityLabel: '穩定度 81%',
        baseColor: const Color(0xFF123B70),
      ),
      _VideoCardData(
        dateLabel: 'Apr 3',
        speedLabel: '94 MPH',
        stabilityLabel: '穩定度 79%',
        baseColor: const Color(0xFF0A5E5A),
      ),
      _VideoCardData(
        dateLabel: 'Mar 28',
        speedLabel: '92 MPH',
        stabilityLabel: '穩定度 75%',
        baseColor: const Color(0xFF4C2A9A),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF5F7FB),
        toolbarHeight: 88,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E5A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.golf_course_rounded, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TekSwing',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0B2A2E),
                  ),
                ),
                Text(
                  widget.userEmail,
                  style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6E7B87)),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF0B2A2E)),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 650;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Last 8 Months',
                          value: '124',
                          subTitle: 'Total Swings',
                          highlightColor: const Color(0xFF1E8E5A),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Average Speed',
                          value: '89.5 MPH',
                          subTitle: 'Stability 80%',
                          highlightColor: const Color(0xFF2E8EFF),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Sweet Spot',
                          value: '80 %',
                          subTitle: '命中率',
                          highlightColor: const Color(0xFF8E4AF4),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildStatCard(
                      title: 'Last 8 Months',
                      value: '124',
                      subTitle: 'Total Swings',
                      highlightColor: const Color(0xFF1E8E5A),
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      title: 'Average Speed',
                      value: '89.5 MPH',
                      subTitle: 'Stability 80%',
                      highlightColor: const Color(0xFF2E8EFF),
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      title: 'Sweet Spot',
                      value: '80 %',
                      subTitle: '命中率',
                      highlightColor: const Color(0xFF8E4AF4),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Video Library', actionLabel: 'See all', onTap: () {}),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: videoList.length,
                itemBuilder: (context, index) => _buildVideoTile(videoList[index]),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'Analytics', actionLabel: '詳情報告', onTap: () {}),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Avg Speed', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '89.5 MPH',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text('Stability', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '80 %',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E8EFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 140,
                        width: 140,
                        child: CustomPaint(
                          painter: _RadarChartPainter(values: const [0.9, 0.75, 0.85, 0.7, 0.95]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'Comparison', actionLabel: '查看歷史', onTap: () {}),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Before', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '86.3 MPH',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDA4E5D),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Feb 14  •  60%', style: TextStyle(color: Color(0xFF7D8B9A))),
                          ],
                        ),
                      ),
                      Container(
                        height: 80,
                        width: 1,
                        color: const Color(0xFFE4E8F0),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('After', style: TextStyle(color: Color(0xFF7D8B9A))),
                            SizedBox(height: 6),
                            Text(
                              '90.1 MPH',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E8E5A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Apr 8  •  82%', style: TextStyle(color: Color(0xFF7D8B9A))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _onBottomNavTap(2),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E5A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('立即開始錄影'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 自訂底部導覽列，模擬設計稿中的五個項目並保留 Quick Start 強調樣式
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: _currentIndex == 0,
            onTap: () => _onBottomNavTap(0),
          ),
          _BottomNavItem(
            icon: Icons.calendar_today_rounded,
            label: 'Today Info',
            isActive: _currentIndex == 1,
            onTap: () => _onBottomNavTap(1),
          ),
          _QuickStartNavItem(
            onTap: () => _onBottomNavTap(2),
          ),
          _BottomNavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Data Metrics',
            isActive: _currentIndex == 3,
            onTap: () => _onBottomNavTap(3),
          ),
          _BottomNavItem(
            icon: Icons.workspace_premium_rounded,
            label: 'Upgrade',
            isActive: _currentIndex == 4,
            onTap: () => _onBottomNavTap(4),
          ),
        ],
      ),
    );
  }
}

/// Video Library 中的假資料模型
class _VideoCardData {
  final String dateLabel;
  final String speedLabel;
  final String stabilityLabel;
  final Color baseColor;

  const _VideoCardData({
    required this.dateLabel,
    required this.speedLabel,
    required this.stabilityLabel,
    required this.baseColor,
  });
}

/// 雷達圖繪製器，呈現五個指標的相對表現
class _RadarChartPainter extends CustomPainter {
  final List<double> values; // 介於 0 到 1 的比例值

  const _RadarChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.85;
    final paint = Paint()
      ..color = const Color(0xFF2E8EFF).withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF2E8EFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final angleStep = 2 * math.pi / values.length;
    for (var i = 0; i < values.length; i++) {
      final angle = -math.pi / 2 + angleStep * i;
      final pointRadius = radius * values[i].clamp(0.0, 1.0);
      final offset = Offset(
        center.dx + pointRadius * math.cos(angle),
        center.dy + pointRadius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFE4E8F0)
      ..style = PaintingStyle.stroke;

    // 繪製背景網格，提供視覺上的比例參考
    for (var layer = 1; layer <= 4; layer++) {
      final layerRadius = radius * layer / 4;
      final gridPath = Path();
      for (var i = 0; i < values.length; i++) {
        final angle = -math.pi / 2 + angleStep * i;
        final offset = Offset(
          center.dx + layerRadius * math.cos(angle),
          center.dy + layerRadius * math.sin(angle),
        );
        if (i == 0) {
          gridPath.moveTo(offset.dx, offset.dy);
        } else {
          gridPath.lineTo(offset.dx, offset.dy);
        }
      }
      gridPath.close();
      canvas.drawPath(gridPath, gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => !listEquals(oldDelegate.values, values);
}

/// 一般底部導覽按鈕元件
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? const Color(0xFF1E8E5A) : const Color(0xFF7D8B9A)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF1E8E5A) : const Color(0xFF7D8B9A),
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 快速開始按鈕獨立元件，採用圓形浮起樣式凸顯互動焦點
class _QuickStartNavItem extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickStartNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF1E8E5A),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.flash_on_rounded, color: Colors.white),
            SizedBox(height: 4),
            Text(
              'Quick\nStart',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// 區塊標題元件，集中管理標題與右側操作按鈕
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0B2A2E),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Text(
            actionLabel,
            style: const TextStyle(color: Color(0xFF1E8E5A), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
