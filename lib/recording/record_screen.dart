import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import 'test_video_selector_dialog.dart';

typedef RecordCompleteCallback = void Function({
  required String videoPath,
  required String csvPath,
  required String audioPath,
});

/// Simple golf swing recording screen with Camerawesome 2.0.1
/// 支援實時錄製和測試模式（從已導入的影片中選擇）
class RecordScreen extends StatefulWidget {
  final RecordCompleteCallback? onComplete;
  const RecordScreen({super.key, this.onComplete});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final PoseDetector _poseDetector;
  
  // Recording state
  bool _isRecording = false;
  bool _isTestMode = false; // 測試模式標誌
  final List<List<String>> _poseData = [];
  int _frameCount = 0;
  RecordingHistoryEntry? _selectedTestVideo; // 選中的測試影片
  
  // Video and audio paths
  late String _sessionId;
  String _videoPath = '';
  String _audioPath = '';
  String _csvPath = '';

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );
  }

  @override
  void dispose() {
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(_isTestMode ? '高爾夫揮桿錄製 (測試模式)' : '高爾夫揮桿錄製'),
        elevation: 0,
        actions: [
          // 測試模式切換按鈕
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: _isTestMode
                    ? Colors.orange.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isTestMode ? Colors.orange : Colors.grey,
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleTestMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        _isTestMode ? '🧪 測試' : '🎥 即時',
                        style: TextStyle(
                          color: _isTestMode ? Colors.orange : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // 使用不同的內容取決於模式
      body: _isTestMode ? _buildTestModeUI() : _buildRecordingModeUI(),
    );
  }

  /// 構建即時錄製模式的 UI
  Widget _buildRecordingModeUI() {
    return Stack(
      children: [
        CameraAwesomeBuilder.awesome(
          saveConfig: SaveConfig.video(),
          onImageForAnalysis: _onImageAnalysis,
        ),
        // Recording indicator
        if (_isRecording)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已錄製: $_frameCount 幀',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        // Record button
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: _isRecording ? Colors.white : Colors.red,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 構建測試模式的 UI
  Widget _buildTestModeUI() {
    if (_selectedTestVideo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library_outlined,
                color: Colors.orange,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '測試模式',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '從已導入的影片中選擇一支\n作為測試錄製',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _showTestVideoSelector,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('選擇影片'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final duration = Duration(seconds: _selectedTestVideo!.durationSeconds);
    final durationStr =
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.videocam,
              color: Colors.white54,
              size: 60,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _selectedTestVideo!.displayTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '⏱️ $durationStr • Round ${_selectedTestVideo!.roundIndex}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedTestVideo = null;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _completeTestMode,
                icon: const Icon(Icons.check),
                label: const Text('完成'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (!_isRecording) {
        _saveRecordingData();
      } else {
        _frameCount = 0;
        _poseData.clear();
        // Add CSV header for pose landmarks
        _poseData.add([
          'frame',
          'timestamp',
          'nose_x', 'nose_y',
          'left_shoulder_x', 'left_shoulder_y',
          'right_shoulder_x', 'right_shoulder_y',
          'left_elbow_x', 'left_elbow_y',
          'right_elbow_x', 'right_elbow_y',
          'left_wrist_x', 'left_wrist_y',
          'right_wrist_x', 'right_wrist_y',
          'left_hip_x', 'left_hip_y',
          'right_hip_x', 'right_hip_y',
          'left_knee_x', 'left_knee_y',
          'right_knee_x', 'right_knee_y',
          'left_ankle_x', 'left_ankle_y',
          'right_ankle_x', 'right_ankle_y',
        ]);
      }
    });
  }

  /// 切換測試模式與即時錄製模式
  void _toggleTestMode() {
    setState(() {
      _isTestMode = !_isTestMode;
      _selectedTestVideo = null;
      _isRecording = false;
    });
  }

  /// 顯示測試影片選擇對話框
  Future<void> _showTestVideoSelector() async {
    final selected = await showDialog<RecordingHistoryEntry>(
      context: context,
      builder: (_) => const TestVideoSelectorDialog(),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedTestVideo = selected;
      });
    }
  }

  /// 完成測試模式：複製選定的影片並返回結果
  Future<void> _completeTestMode() async {
    if (_selectedTestVideo == null) return;

    try {
      // 建立新的測試工作階段
      final dir = await getApplicationDocumentsDirectory();
      final testSessionId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testDir = Directory(p.join(dir.path, 'golf_recordings', testSessionId));
      await testDir.create(recursive: true);

      // 複製選定的影片到測試目錄
      final sourceFile = File(_selectedTestVideo!.filePath);
      final testVideoPath = p.join(testDir.path, 'swing.mp4');
      await sourceFile.copy(testVideoPath);

      // 建立簡單的 CSV 檔案（標題只）
      final testCsvPath = p.join(testDir.path, 'pose_landmarks.csv');
      final poseHeader = [
        'frame',
        'timestamp',
        'nose_x', 'nose_y',
        'left_shoulder_x', 'left_shoulder_y',
        'right_shoulder_x', 'right_shoulder_y',
        'left_elbow_x', 'left_elbow_y',
        'right_elbow_x', 'right_elbow_y',
        'left_wrist_x', 'left_wrist_y',
        'right_wrist_x', 'right_wrist_y',
        'left_hip_x', 'left_hip_y',
        'right_hip_x', 'right_hip_y',
        'left_knee_x', 'left_knee_y',
        'right_knee_x', 'right_knee_y',
        'left_ankle_x', 'left_ankle_y',
        'right_ankle_x', 'right_ankle_y',
      ];
      final csv = const ListToCsvConverter().convert([poseHeader]);
      final csvFile = File(testCsvPath);
      await csvFile.writeAsString(csv);

      // 建立空的音訊檔案
      final testAudioPath = p.join(testDir.path, 'audio.aac');
      final audioFile = File(testAudioPath);
      await audioFile.writeAsBytes([]);

      debugPrint('[測試模式] ✅ 測試錄製完成: $testVideoPath');

      // 回呼並返回結果
      widget.onComplete?.call(
        videoPath: testVideoPath,
        csvPath: testCsvPath,
        audioPath: testAudioPath,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[測試模式] ❌ 測試錄製失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('測試錄製失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _onImageAnalysis(AnalysisImage image) async {
    if (!_isRecording) return;
    
    try {
      // Process each frame for pose detection
      // Note: AnalysisImage to InputImage conversion may be needed here
      // For now, we capture every Nth frame to reduce processing load
      if (_frameCount % 3 != 0) {
        _frameCount++;
        return;
      }
      
      // TODO: Convert AnalysisImage to InputImage for pose detection
      // This requires proper access to image byte data from camerawesome 2.5.0
      _frameCount++;
    } catch (e) {
      debugPrint('[Camera] Error: $e');
    }
  }

  Future<void> _saveRecordingData() async {
    try {
      // Initialize paths just-in-time
      final dir = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${dir.path}/golf_recordings/$_sessionId');
      await sessionDir.create(recursive: true);
      
      _csvPath = '${sessionDir.path}/pose_landmarks.csv';
      _audioPath = '${sessionDir.path}/audio.aac';
      _videoPath = '${sessionDir.path}/swing.mp4';
      
      // Save pose data to CSV
      if (_poseData.length > 1) {
        final csv = const ListToCsvConverter().convert(_poseData);
        final csvFile = File(_csvPath);
        await csvFile.writeAsString(csv);
        debugPrint('CSV saved: $_csvPath');
      }
      
      // Call completion callback with paths
      widget.onComplete?.call(
        videoPath: _videoPath,
        csvPath: _csvPath,
        audioPath: _audioPath,
      );
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[Recording] Error saving data: $e');
    }
  }
}
