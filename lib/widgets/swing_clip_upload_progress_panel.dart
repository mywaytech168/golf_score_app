import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/swing_clip_upload_manager.dart';

/// 切片上傳進度面板 UI 組件
/// 
/// 功能：
/// 1. 顯示當前上傳項目的詳細信息
/// 2. 顯示上傳進度條與百分比
/// 3. 顯示整個隊列的統計信息
/// 4. 提供暫停/繼續/取消操作按鈕
class SwingClipUploadProgressPanel extends StatelessWidget {
  /// 上傳管理器實例
  final SwingClipUploadManager uploadManager;

  /// 自訂樣式
  final Color progressColor;
  final Color backgroundColor;
  final double borderRadius;

  const SwingClipUploadProgressPanel({
    Key? key,
    required this.uploadManager,
    this.progressColor = Colors.blue,
    this.backgroundColor = Colors.grey,
    this.borderRadius = 12.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: uploadManager,
      builder: (context, _) {
        final stats = uploadManager.getStatistics();
        final current = uploadManager.currentItem;
        final isUploading = uploadManager.isUploading;
        final isPaused = uploadManager.isPaused;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題欄
            _buildHeader(context, stats),

            // 當前項目信息
            if (current != null)
              _buildCurrentItemInfo(context, current)
            else if (!isUploading)
              _buildIdleState(context, stats)
            else
              _buildWaitingState(context),

            // 隊列統計
            _buildQueueStats(context, stats),

            // 操作按鈕
            _buildActionButtons(context),
          ],
        );
      },
    );
  }

  /// 標題欄
  Widget _buildHeader(BuildContext context, Map<String, dynamic> stats) {
    final theme = Theme.of(context);
    final isActive = uploadManager.isUploading && !uploadManager.isPaused;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(borderRadius),
          topRight: Radius.circular(borderRadius),
        ),
      ),
      child: Row(
        children: [
          // 狀態圖標
          if (isActive)
            Icon(Icons.cloud_upload, color: Colors.blue)
          else if (uploadManager.isPaused)
            Icon(Icons.pause_circle, color: Colors.orange)
          else
            Icon(Icons.upload_file, color: Colors.grey),
          const SizedBox(width: 12),
          // 標題與狀態
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '切片上傳隊列',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isActive
                      ? '上傳中...'
                      : uploadManager.isPaused
                          ? '已暫停'
                          : '待命',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isActive
                        ? Colors.blue
                        : uploadManager.isPaused
                            ? Colors.orange
                            : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          // 總進度百分比
          Text(
            '${((uploadManager.totalProgress) * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  /// 當前項目信息
  Widget _buildCurrentItemInfo(
    BuildContext context,
    UploadQueueItem current,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 項目標籤
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  current.metadata['tag'] ?? 'Unknown',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '擊棒: ${(current.metadata['hitSecond'] ?? 0).toStringAsFixed(2)}s',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current.uploadProgress,
              minHeight: 8,
              backgroundColor: backgroundColor.withAlpha(100),
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 8),
          // 進度文本
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(current.uploadProgress * 100).toStringAsFixed(1)}% 完成',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                _getStatusLabel(current.uploadStatus),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _getStatusColor(current.uploadStatus),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 空閒狀態
  Widget _buildIdleState(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final theme = Theme.of(context);
    final totalItems = stats['total'] as int? ?? 0;

    if (totalItems == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.inbox,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              '隊列為空',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        '準備上傳 $totalItems 個切片',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 等待狀態
  Widget _buildWaitingState(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.blue.shade300),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '準備下一項...',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// 隊列統計信息
  Widget _buildQueueStats(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final theme = Theme.of(context);
    final local = stats['local'] as int? ?? 0;
    final uploading = stats['uploading'] as int? ?? 0;
    final uploaded = stats['uploaded'] as int? ?? 0;
    final failed = stats['failed'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            label: '待上傳',
            count: local,
            color: Colors.blue,
            icon: Icons.cloud_upload,
          ),
          _buildStatItem(
            label: '上傳中',
            count: uploading,
            color: Colors.orange,
            icon: Icons.sync,
          ),
          _buildStatItem(
            label: '已上傳',
            count: uploaded,
            color: Colors.green,
            icon: Icons.check_circle,
          ),
          _buildStatItem(
            label: '失敗',
            count: failed,
            color: Colors.red,
            icon: Icons.error,
          ),
        ],
      ),
    );
  }

  /// 單個統計項
  Widget _buildStatItem({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// 操作按鈕
  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (uploadManager.isUploading && !uploadManager.isPaused)
            ElevatedButton.icon(
              onPressed: () => uploadManager.pauseProcessing(),
              icon: const Icon(Icons.pause),
              label: const Text('暫停'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            )
          else if (uploadManager.isPaused)
            ElevatedButton.icon(
              onPressed: () => uploadManager.resumeProcessing(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('繼續'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _showCancelDialog(context),
            icon: const Icon(Icons.close),
            label: const Text('取消全部'),
          ),
        ],
      ),
    );
  }

  /// 確認取消對話框
  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消所有上傳'),
        content: const Text('確定要取消隊列中的所有上傳嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('保持'),
          ),
          TextButton(
            onPressed: () {
              uploadManager.cancelAll();
              Navigator.pop(dialogContext);
            },
            child: const Text('取消全部', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 取得狀態標籤
  String _getStatusLabel(UploadStatus status) {
    switch (status) {
      case UploadStatus.local:
        return '待上傳';
      case UploadStatus.uploading:
        return '上傳中';
      case UploadStatus.uploaded:
        return '已完成';
      case UploadStatus.failed:
        return '上傳失敗';
    }
  }

  /// 取得狀態顏色
  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.local:
        return Colors.blue;
      case UploadStatus.uploading:
        return Colors.orange;
      case UploadStatus.uploaded:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
    }
  }
}
