import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

class LearningHubPage extends StatelessWidget {
  const LearningHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final contents = _buildDemoContents(context);
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).learningTitle)),
      body: SafeArea(top: false, child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: contents.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == contents.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.update_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context).learningMoreComing,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            );
          }
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
                MaterialPageRoute(builder: (_) => _LearningDetailPage(content: c)),
              ),
            ),
          );
        },
      )),
    );
  }
}

class _LearningDetailPage extends StatelessWidget {
  final _LearningContent content;
  const _LearningDetailPage({required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(content.title)),
      body: SafeArea(top: false, child: Padding(
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
                        AppLocalizations.of(context).learningVideoComingSoon,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).learningKeyMarkers, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      )),
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

List<_LearningContent> _buildDemoContents(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return [
    _LearningContent(
      title: l10n.learnHubGoodSwingTitle,
      description: l10n.learnHubGoodSwingDesc,
      type: 'good',
      markers: [
        _Marker(time: 0.80, label: l10n.learnHubMarkerBackswingTop, note: l10n.learnHubMarkerBackswingTopNote),
        _Marker(time: 1.20, label: l10n.learnHubMarkerImpact, note: l10n.learnHubMarkerImpactNote),
        _Marker(time: 1.60, label: l10n.learnHubMarkerFinish, note: l10n.learnHubMarkerFinishNote),
      ],
    ),
    _LearningContent(
      title: l10n.learnHubEarlyReleaseTitle,
      description: l10n.learnHubEarlyReleaseDesc,
      type: 'error',
      markers: [
        _Marker(time: 0.70, label: l10n.learnHubMarkerBackswingTop, note: l10n.learnHubMarkerEarlyReleaseTopNote),
        _Marker(time: 1.05, label: l10n.learnHubMarkerPreImpact, note: l10n.learnHubMarkerPreImpactNote),
        _Marker(time: 1.40, label: l10n.learnHubMarkerFinish, note: l10n.learnHubMarkerEarlyReleaseFinishNote),
      ],
    ),
  ];
}
