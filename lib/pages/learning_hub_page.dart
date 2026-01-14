import 'package:flutter/material.dart';

class LearningHubPage extends StatelessWidget {
  const LearningHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final contents = _demoContents;
    return Scaffold(
      appBar: AppBar(title: const Text('揮桿學習')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: contents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final c = contents[index];
          return Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: c.type == 'good' ? Colors.green.shade100 : Colors.red.shade100,
                child: Icon(
                  c.type == 'good' ? Icons.thumb_up : Icons.error_outline,
                  color: c.type == 'good' ? Colors.green : Colors.red,
                ),
              ),
              title: Text(c.title),
              subtitle: Text(c.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LearningDetailPage(content: c)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LearningDetailPage extends StatelessWidget {
  final _LearningContent content;
  const LearningDetailPage({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(content.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content.description, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(Icons.movie, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '示範影片待補充，先提供重點與標記供對照學習。',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('關鍵標記', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: content.markers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final m = content.markers[idx];
                  return ListTile(
                    leading: Text('${m.time.toStringAsFixed(2)}s', style: const TextStyle(fontFeatures: [])),
                    title: Text(m.label),
                    subtitle: Text(m.note),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningContent {
  final String title;
  final String description;
  final String type; // good / error
  final List<_Marker> markers;
  const _LearningContent({required this.title, required this.description, required this.type, required this.markers});
}

class _Marker {
  final double time;
  final String label;
  final String note;
  const _Marker({required this.time, required this.label, required this.note});
}

final List<_LearningContent> _demoContents = [
  _LearningContent(
    title: '良好揮桿示範（Placeholder）',
    description: '節奏平順、重心穩定、擊球後收桿完整。',
    type: 'good',
    markers: const [
      _Marker(time: 0.80, label: '上桿頂點', note: '重心仍在腳中，桿身與手臂成直線'),
      _Marker(time: 1.20, label: '擊球瞬間', note: '手位在球前方，身體旋轉帶動擊球'),
      _Marker(time: 1.60, label: '收桿', note: '重心轉向前腳，身體保持平衡'),
    ],
  ),
  _LearningContent(
    title: '常見錯誤：提前釋放（Placeholder）',
    description: '手腕提前放鬆，導致桿頭加速度不足，球路弱/右曲。',
    type: 'error',
    markers: const [
      _Marker(time: 0.70, label: '上桿頂點', note: '手腕角度過早放鬆，桿頭落後'),
      _Marker(time: 1.05, label: '擊球前', note: '手部領先不足，重心偏後'),
      _Marker(time: 1.40, label: '收桿', note: '重心未移到前腳，平衡不佳'),
    ],
  ),
];
