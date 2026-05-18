import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/share_service.dart';

/// 分享上傳 Dialog：壓縮 → 上傳 → 顯示分享碼
///
/// 使用方式：
///   ShareUploadDialog.show(context, sessionDir: '...', title: '第 3 輪');
class ShareUploadDialog extends StatefulWidget {
  final String sessionDir;
  final String title;

  const ShareUploadDialog({
    super.key,
    required this.sessionDir,
    required this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionDir,
    required String title,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShareUploadDialog(sessionDir: sessionDir, title: title),
    );
  }

  @override
  State<ShareUploadDialog> createState() => _ShareUploadDialogState();
}

class _ShareUploadDialogState extends State<ShareUploadDialog> {
  _Phase _phase = _Phase.compressing;
  double _uploadProgress = 0;
  String? _shareCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      // 1. 壓縮
      final zipPath = await ShareService.compressSession(widget.sessionDir);
      final zipSize = File(zipPath).lengthSync();

      // 2. 取得 pre-signed URL
      if (mounted) setState(() => _phase = _Phase.uploading);
      final prepare = await ShareService.prepare(
        title: widget.title,
        sizeBytes: zipSize,
      );

      // 3. 直傳 B2
      await ShareService.uploadToB2(
        uploadUrl: prepare.uploadUrl,
        zipPath: zipPath,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      // 4. 確認
      await ShareService.confirm(prepare.shareCode);

      // 清理暫存 zip
      try { File(zipPath).deleteSync(); } catch (_) {}

      if (mounted) setState(() { _phase = _Phase.done; _shareCode = prepare.shareCode; });
    } catch (e) {
      if (mounted) setState(() { _phase = _Phase.error; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _Phase.done || _phase == _Phase.error,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('分享連結', style: TextStyle(color: Colors.white)),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _Phase.compressing:
        return _buildProgress('壓縮中…', null);
      case _Phase.uploading:
        return _buildProgress('上傳中…', _uploadProgress);
      case _Phase.done:
        return _buildResult();
      case _Phase.error:
        return Text(_error ?? '未知錯誤', style: const TextStyle(color: Colors.redAccent));
    }
  }

  Widget _buildProgress(String label, double? value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.white12,
          color: const Color(0xFF1E8E5A),
        ),
        const SizedBox(height: 12),
        Text(
          value != null ? '$label  ${(value * 100).toStringAsFixed(0)}%' : label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final code = _shareCode!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('分享碼（有效 1 天）', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white54, size: 20),
                tooltip: '複製',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已複製分享碼'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget>? _buildActions() {
    if (_phase == _Phase.done) {
      return [
        TextButton(
          onPressed: () {
            Share.share('高爾夫揮桿分享碼：$_shareCode\n（有效 1 天，請在 App 中輸入此碼取得影片）');
          },
          child: const Text('系統分享', style: TextStyle(color: Color(0xFF1E8E5A))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉', style: TextStyle(color: Colors.white54)),
        ),
      ];
    }
    if (_phase == _Phase.error) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉', style: TextStyle(color: Colors.white54)),
        ),
      ];
    }
    return null;
  }
}

enum _Phase { compressing, uploading, done, error }
