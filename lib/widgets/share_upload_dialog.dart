import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recording_history_entry.dart';
import '../providers/user_provider.dart';
import '../services/share_service.dart';
import '../services/recording_history_storage.dart';
import '../theme/app_theme.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 分享上傳 Dialog：
/// - 若 entry 已有有效分享碼 → 直接顯示，不重新上傳
/// - 否則 壓縮 → 上傳 → confirm → 顯示新分享碼，並回存到 entry
class ShareUploadDialog extends StatefulWidget {
  final RecordingHistoryEntry entry;
  final String? sharerName;

  /// 上傳完成後，將更新後的 entry 回傳給呼叫端（用於更新歷史列表）
  final void Function(RecordingHistoryEntry updated)? onShareSaved;

  const ShareUploadDialog({
    super.key,
    required this.entry,
    this.sharerName,
    this.onShareSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required RecordingHistoryEntry entry,
    void Function(RecordingHistoryEntry updated)? onShareSaved,
  }) {
    final sharerName = context.read<UserProvider>().displayName;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShareUploadDialog(entry: entry, sharerName: sharerName, onShareSaved: onShareSaved),
    );
  }

  @override
  State<ShareUploadDialog> createState() => _ShareUploadDialogState();
}

class _ShareUploadDialogState extends State<ShareUploadDialog> {
  _Phase _phase = _Phase.checking;
  double _uploadProgress = 0;
  String? _shareCode;
  bool _isReused = false;
  String? _error;

  String get _sessionDir =>
      widget.entry.filePath.replaceAll(RegExp(r'[^/\\]*$'), '');

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    // 1. 檢查是否有尚未過期的分享碼
    if (widget.entry.isShareValid) {
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _shareCode = widget.entry.shareCode;
          _isReused = true;
        });
      }
      return;
    }

    // 2. 需要重新上傳
    try {
      if (mounted) setState(() => _phase = _Phase.compressing);

      // 壓縮前先寫入 session_meta.json（含完整 entry 資訊）
      final metaFile = File('$_sessionDir/session_meta.json');
      metaFile.writeAsStringSync(jsonEncode(widget.entry.toJson()));

      final zipPath = await ShareService.compressSession(_sessionDir);
      final zipSize = File(zipPath).lengthSync();

      if (mounted) setState(() => _phase = _Phase.uploading);

      final prepare = await ShareService.prepare(
        title: widget.entry.displayTitle,
        sizeBytes: zipSize,
        sharerName: widget.sharerName,
      );

      await ShareService.uploadToB2(
        uploadUrl: prepare.uploadUrl,
        zipPath: zipPath,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      await ShareService.confirm(prepare.shareCode);

      try { File(zipPath).deleteSync(); } catch (_) {}

      // 3. 將新分享碼存回 entry
      final expiresAt = DateTime.now().toUtc().add(const Duration(days: 1));
      final updated = widget.entry.copyWith(
        shareCode: prepare.shareCode,
        shareExpiresAt: expiresAt,
      );
      await _persistEntry(updated);
      widget.onShareSaved?.call(updated);

      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _shareCode = prepare.shareCode;
          _isReused = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _phase = _Phase.error; _error = e.toString(); });
    }
  }

  /// 將 entry 更新寫入持久化儲存
  Future<void> _persistEntry(RecordingHistoryEntry updated) async {
    await RecordingHistoryStorage.instance.upsertEntry(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: _phase == _Phase.done || _phase == _Phase.error,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.shareUploadTitle, style: const TextStyle(color: Colors.white)),
        content: _buildContent(l10n),
        actions: _buildActions(l10n),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (_phase) {
      case _Phase.checking:
        return _buildSpinner(l10n.shareUploadChecking);
      case _Phase.compressing:
        return _buildSpinner(l10n.shareUploadCompressing);
      case _Phase.uploading:
        return _buildUploadProgress(l10n);
      case _Phase.done:
        return _buildResult(l10n);
      case _Phase.error:
        return Text(_error ?? l10n.shareUploadUnknownError, style: const TextStyle(color: Colors.redAccent));
    }
  }

  Widget _buildSpinner(String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: null, backgroundColor: Colors.white12, color: kBrandPrimary),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _buildUploadProgress(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: _uploadProgress,
          backgroundColor: Colors.white12,
          color: kBrandPrimary,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.shareUploadUploading((_uploadProgress * 100).toStringAsFixed(0)),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildResult(AppLocalizations l10n) {
    final code = _shareCode!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _isReused ? l10n.shareUploadCodeReused : l10n.shareUploadCodeNew,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (_isReused) ...[
              const SizedBox(width: 6),
              const Icon(Icons.recycling, color: kBrandPrimary, size: 14),
            ],
          ],
        ),
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
                tooltip: l10n.shareUploadCopy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.shareUploadCopied), duration: const Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget>? _buildActions(AppLocalizations l10n) {
    if (_phase == _Phase.done) {
      return [
        TextButton(
          onPressed: () {
            Share.share(l10n.shareUploadShareText(_shareCode!));
          },
          child: Text(l10n.shareUploadSystemShare, style: const TextStyle(color: kBrandPrimary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose, style: const TextStyle(color: Colors.white54)),
        ),
      ];
    }
    if (_phase == _Phase.error) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose, style: const TextStyle(color: Colors.white54)),
        ),
      ];
    }
    return null;
  }
}

enum _Phase { checking, compressing, uploading, done, error }
