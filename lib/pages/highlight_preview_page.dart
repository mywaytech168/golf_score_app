import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
// ...existing code...

class HighlightPreviewPage extends StatefulWidget {
  final String videoPath;
  final String? avatarPath;
  final String? debugText;
  const HighlightPreviewPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.debugText,
  });

  @override
  State<HighlightPreviewPage> createState() => _HighlightPreviewPageState();
}

class _HighlightPreviewPageState extends State<HighlightPreviewPage> {
  VideoPlayerController? _ctrl;
  final bool _isProcessingShare = false;
  final List<String> _generatedTempFiles = [];

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.videoPath))..initialize().then((_) { setState(() {}); _ctrl!.play(); });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    for (final f in _generatedTempFiles) {
      try { File(f).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.highlightTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _ctrl != null && _ctrl!.value.isInitialized
                  ? AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!))
                  : const CircularProgressIndicator(),
            ),
          ),
          // share UI: system share only
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: Text(l10n.highlightShareSystem),
              onPressed: _isProcessingShare ? null : _shareSystem,
            ),
          )
        ,
        if (widget.debugText != null && widget.debugText!.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Text(widget.debugText!, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
            ),
          )
        ,
        if (widget.debugText != null && widget.debugText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(
                      l10n.highlightExportDebug,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _exportDebugToDownloads(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 16),
                    label: Text(
                      l10n.highlightShareDebug,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _shareDebugFile(),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _shareSystem() async {
    final sharePath = await _prepareShareFile();
    if (sharePath == null) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await Share.shareXFiles([XFile(sharePath)], text: l10n.highlightShareText);
  }

  Future<String?> _prepareShareFile() async {
    // 直接返回原影片路径，不進行任何處理
    return widget.videoPath;
  }

  Future<File?> _ensureDebugTempFile() async {
    if (widget.debugText == null || widget.debugText!.isEmpty) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final name = '${p.basenameWithoutExtension(widget.videoPath)}_highlight_debug.txt';
      final f = File(p.join(tempDir.path, name));
      await f.writeAsString(widget.debugText!, flush: true);
      return f;
    } catch (e) {
      return null;
    }
  }

  Future<void> _shareDebugFile() async {
    final f = await _ensureDebugTempFile();
    if (f == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightDebugFileError)));
      }
      return;
    }
    await Share.shareXFiles([XFile(f.path)], text: 'Highlight debug log');
  }

  Future<void> _exportDebugToDownloads() async {
    final f = await _ensureDebugTempFile();
    if (f == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightDebugFileError)));
      }
      return;
    }

    // iOS has no public Downloads folder — route through share sheet so the
    // user can save to Files, Mail, AirDrop, etc.
    if (Platform.isIOS) {
      await Share.shareXFiles([XFile(f.path)], text: 'Highlight debug log');
      return;
    }

    try {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted && !status.isLimited) {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightStoragePermissionRequired)));
          }
          return;
        }
      }

      final downloadsDir = await _getDownloadsDirectory();
      if (downloadsDir == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightDownloadsDirNotFound)));
        }
        return;
      }
      final dest = File(p.join(downloadsDir.path, p.basename(f.path)));
      await f.copy(dest.path);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightSavedTo(dest.path))));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.highlightExportFailed(e.toString()))));
      }
    }
  }

  Future<Directory?> _getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        final directory = Directory('/storage/emulated/0/Download');
        if (await directory.exists()) return directory;
        return await getExternalStorageDirectory();
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return await getDownloadsDirectory();
      }
    } catch (_) {}
    return null;
  }
}
