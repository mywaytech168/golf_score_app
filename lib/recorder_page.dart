import 'dart:async';

import 'package:flutter/material.dart';
import 'models/recording_history_entry.dart';
import 'services/recording_history_storage.dart';

/// 簡化的錄影入口頁面 - 移除所有 IMU 相關功能
class RecorderPage extends StatefulWidget {
  final List<RecordingHistoryEntry> initialHistory;
  final ValueChanged<List<RecordingHistoryEntry>> onHistoryChanged;
  final String? userAvatarPath;

  const RecorderPage({
    super.key,
    required this.initialHistory,
    required this.onHistoryChanged,
    this.userAvatarPath,
  });

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  late final List<RecordingHistoryEntry> _recordingHistory =
      List<RecordingHistoryEntry>.from(widget.initialHistory);
  bool _isSessionPageVisible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restorePersistedHistory());
  }

  Future<void> _restorePersistedHistory() async {
    final stored = await RecordingHistoryStorage.instance.loadHistory();
    if (!mounted) return;

    if (stored.isEmpty) {
      return;
    }

    final currentPaths = _recordingHistory.map((e) => e.filePath).toList();
    final storedPaths = stored.map((e) => e.filePath).toList();
    final isSameLength = currentPaths.length == storedPaths.length;
    var isSameOrder = isSameLength;
    if (isSameOrder) {
      for (var i = 0; i < currentPaths.length; i++) {
        if (currentPaths[i] != storedPaths[i]) {
          isSameOrder = false;
          break;
        }
      }
    }

    if (isSameOrder) {
      return;
    }

    setState(() {
      _recordingHistory
        ..clear()
        ..addAll(stored);
    });
    widget
        .onHistoryChanged(List<RecordingHistoryEntry>.from(_recordingHistory));
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _startRecording() async {
    // RecordingSessionPage has been replaced with RecordScreen in MainShellPage
    // This method is now a placeholder - recording is handled through main navigation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use the Record tab in the main navigation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('開始錄影'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _startRecording,
              icon: const Icon(Icons.videocam),
              label: const Text('開始錄影'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '已錄製 ${_recordingHistory.length} 支影片',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
