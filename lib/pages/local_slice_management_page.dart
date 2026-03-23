import 'package:flutter/material.dart';
import 'package:golf_score_app/services/local_slice_repository.dart';
import 'package:golf_score_app/services/video_server_client.dart';
import 'package:intl/intl.dart';

/// 本地切片管理頁面
class LocalSliceManagementPage extends StatefulWidget {
  final int userId;

  const LocalSliceManagementPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<LocalSliceManagementPage> createState() => _LocalSliceManagementPageState();
}

class _LocalSliceManagementPageState extends State<LocalSliceManagementPage> {
  final _sliceRepository = LocalSliceRepository();
  final _serverClient = VideoServerClient();

  List<Map<String, dynamic>> _recordings = [];
  Map<String, Map<String, dynamic>> _recordingStats = {};
  bool _isLoading = true;
  String? _expandedRecordingId;
  Map<String, bool> _selectedSlices = {}; // 用於批量選擇

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    // 定期同步伺服器狀態
    _startPeriodicSync();
  }

  /// 加載所有本地錄影紀錄
  Future<void> _loadRecordings() async {
    try {
      final recordings = await _sliceRepository.getAllRecordings();
      
      // 為每個錄影計算統計信息
      final stats = <String, Map<String, dynamic>>{};
      for (final recording in recordings) {
        final recordingId = recording['id'] as String;
        stats[recordingId] = await _sliceRepository.getRecordingStats(recordingId);
      }

      setState(() {
        _recordings = recordings;
        _recordingStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Local Slice] Error loading recordings: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 開始定期同步伺服器狀態
  void _startPeriodicSync() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _syncServerStatus();
        _startPeriodicSync();
      }
    });
  }

  /// 同步伺服器狀態
  Future<void> _syncServerStatus() async {
    try {
      final response = await _serverClient.getVideos();
      if (!response['success']) return;

      final serverVideos = response['data']['data'] as List;
      
      // 比對本地和伺服器狀態，更新本地記錄
      for (final serverVideo in serverVideos) {
        if (serverVideo['slices'] is List) {
          for (final _ in serverVideo['slices']) {
            // 根據伺服器返回的 server_id 更新本地狀態
            // 這裡需要實現匹配邏輯
          }
        }
      }

      // 重新加載本地資料
      await _loadRecordings();
    } catch (e) {
      debugPrint('[Local Slice] Sync error: $e');
    }
  }

  /// 上傳選中的切片
  Future<void> _uploadSelectedSlices(String recordingId) async {
    final selectedSliceIds = _selectedSlices.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (selectedSliceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請選擇至少一個切片')),
      );
      return;
    }

    // 顯示進度對話框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UploadProgressDialog(
        recordingId: recordingId,
        selectedSliceIds: selectedSliceIds,
        sliceRepository: _sliceRepository,
        serverClient: _serverClient,
        userId: widget.userId,
        onComplete: () {
          Navigator.pop(context);
          _loadRecordings();
        },
      ),
    );
  }

  /// 顯示切片詳情
  void _showSliceDetails(String recordingId) async {
    final slices = await _sliceRepository.getSlicesByRecording(recordingId);
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => _SliceDetailsSheet(
        recordingId: recordingId,
        slices: slices,
        selectedSlices: _selectedSlices,
        onSliceSelected: (sliceId, isSelected) {
          setState(() {
            _selectedSlices[sliceId] = isSelected;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地切片管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暫無本地切片',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '錄製完畢後將自動生成切片',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    final recordingId = recording['id'] as String;
                    final stats = _recordingStats[recordingId] ?? {};
                    final isExpanded = _expandedRecordingId == recordingId;

                    return _RecordingCard(
                      recording: recording,
                      stats: stats,
                      isExpanded: isExpanded,
                      onExpanded: () {
                        setState(() {
                          _expandedRecordingId = isExpanded ? null : recordingId;
                        });
                      },
                      onViewDetails: () => _showSliceDetails(recordingId),
                      onUpload: () => _uploadSelectedSlices(recordingId),
                    );
                  },
                ),
    );
  }
}

/// 錄影卡片組件
class _RecordingCard extends StatelessWidget {
  final Map<String, dynamic> recording;
  final Map<String, dynamic> stats;
  final bool isExpanded;
  final VoidCallback onExpanded;
  final VoidCallback onViewDetails;
  final VoidCallback onUpload;

  const _RecordingCard({
    required this.recording,
    required this.stats,
    required this.isExpanded,
    required this.onExpanded,
    required this.onViewDetails,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final name = recording['name'] as String? ?? '未命名';
    final createdAt = DateTime.parse(recording['created_at'] as String? ?? DateTime.now().toIso8601String());
    final total = stats['total'] as int? ?? 0;
    final pending = stats['pending'] as int? ?? 0;
    final uploaded = stats['uploaded'] as int? ?? 0;
    final processing = stats['processing'] as int? ?? 0;
    final completed = stats['completed'] as int? ?? 0;
    final failed = stats['failed'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.video_library),
            title: Text(name),
            subtitle: Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(createdAt)),
            trailing: IconButton(
              icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: onExpanded,
            ),
            onTap: onExpanded,
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 統計信息
                  Text(
                    '切片統計',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _StatItem(label: '總數', value: total.toString(), color: Colors.blue),
                      _StatItem(label: '待上傳', value: pending.toString(), color: Colors.orange),
                      _StatItem(label: '已上傳', value: uploaded.toString(), color: Colors.green),
                      _StatItem(label: '處理中', value: processing.toString(), color: Colors.yellow),
                      _StatItem(label: '已完成', value: completed.toString(), color: Colors.teal),
                      if (failed > 0)
                        _StatItem(label: '失敗', value: failed.toString(), color: Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 進度條
                  if (total > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '上傳進度: ${uploaded + completed}/$total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (uploaded + completed) / total,
                          minHeight: 8,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            completed > 0 ? Colors.teal : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  // 按鈕
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onViewDetails,
                        icon: const Icon(Icons.list),
                        label: const Text('詳情'),
                      ),
                      ElevatedButton.icon(
                        onPressed: pending > 0 ? onUpload : null,
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('上傳'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 統計項目組件
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// 切片詳情底部工作表
class _SliceDetailsSheet extends StatefulWidget {
  final String recordingId;
  final List<Map<String, dynamic>> slices;
  final Map<String, bool> selectedSlices;
  final Function(String, bool) onSliceSelected;

  const _SliceDetailsSheet({
    required this.recordingId,
    required this.slices,
    required this.selectedSlices,
    required this.onSliceSelected,
  });

  @override
  State<_SliceDetailsSheet> createState() => _SliceDetailsSheetState();
}

class _SliceDetailsSheetState extends State<_SliceDetailsSheet> {
  late Map<String, bool> _localSelected;

  @override
  void initState() {
    super.initState();
    _localSelected = Map.from(widget.selectedSlices);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 標題欄
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '切片列表',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 切片列表
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: widget.slices.length,
              itemBuilder: (context, index) {
                final slice = widget.slices[index];
                final sliceId = slice['id'] as String;
                final sliceIndex = slice['slice_index'] as int? ?? index;
                final status = slice['status'] as String? ?? 'unknown';
                final isSelected = _localSelected[sliceId] ?? false;

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      _localSelected[sliceId] = value ?? false;
                    });
                  },
                  title: Text('切片 #$sliceIndex'),
                  subtitle: Text(_getStatusLabel(status)),
                  secondary: _getStatusIcon(status),
                  enabled: status == 'pending',
                );
              },
            ),
          ),
          // 底部按鈕
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    for (final slice in widget.slices) {
                      final sliceId = slice['id'] as String;
                      if (slice['status'] == 'pending') {
                        _localSelected[sliceId] = true;
                      }
                    }
                    setState(() {});
                  },
                  child: const Text('全選待上傳'),
                ),
                ElevatedButton(
                  onPressed: () {
                    _localSelected.clear();
                    setState(() {});
                  },
                  child: const Text('全不選'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return '待上傳';
      case 'uploaded':
        return '已上傳';
      case 'processing':
        return '處理中';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失敗';
      default:
        return '未知';
    }
  }

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return const Icon(Icons.schedule, color: Colors.orange);
      case 'uploaded':
        return const Icon(Icons.cloud_done, color: Colors.green);
      case 'processing':
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'completed':
        return const Icon(Icons.check_circle, color: Colors.teal);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.help);
    }
  }
}

/// 上傳進度對話框
class _UploadProgressDialog extends StatefulWidget {
  final String recordingId;
  final List<String> selectedSliceIds;
  final LocalSliceRepository sliceRepository;
  final VideoServerClient serverClient;
  final int userId;
  final VoidCallback onComplete;

  const _UploadProgressDialog({
    required this.recordingId,
    required this.selectedSliceIds,
    required this.sliceRepository,
    required this.serverClient,
    required this.userId,
    required this.onComplete,
  });

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  int _uploadedCount = 0;
  String? _currentSliceId;
  String _statusMessage = '準備上傳...';
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startUpload();
  }

  Future<void> _startUpload() async {
    for (int i = 0; i < widget.selectedSliceIds.length; i++) {
      final sliceId = widget.selectedSliceIds[i];
      
      setState(() {
        _currentSliceId = sliceId;
        _statusMessage = '上傳中 (${i + 1}/${widget.selectedSliceIds.length})...';
      });

      try {
        // TODO: 實現實際上傳邏輯
        // 暫時模擬延遲
        await Future.delayed(const Duration(milliseconds: 500));

        setState(() {
          _uploadedCount = i + 1;
          _statusMessage = '已上傳 (${i + 1}/${widget.selectedSliceIds.length})';
        });
      } catch (e) {
        setState(() {
          _hasError = true;
          _errorMessage = '上傳切片 $sliceId 失敗：$e';
        });
      }
    }

    // 上傳完成
    setState(() {
      _statusMessage = '上傳完成！';
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.selectedSliceIds.isEmpty
        ? 0.0
        : _uploadedCount / widget.selectedSliceIds.length;

    return AlertDialog(
      title: const Text('上傳進度'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 16),
          Text(_statusMessage),
          if (_currentSliceId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '切片 ID: $_currentSliceId',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          if (_hasError && _errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.red,
                    ),
              ),
            ),
        ],
      ),
      actions: [
        if (_uploadedCount == widget.selectedSliceIds.length)
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onComplete();
            },
            child: const Text('完成'),
          ),
      ],
    );
  }
}
