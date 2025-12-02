import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../services/video_overlay_processor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// ...existing code...

class HighlightPreviewPage extends StatefulWidget {
  final String videoPath;
  final String? avatarPath;
  final String? debugText;
  const HighlightPreviewPage({super.key, required this.videoPath, this.avatarPath, this.debugText});

  @override
  State<HighlightPreviewPage> createState() => _HighlightPreviewPageState();
}

class _HighlightPreviewPageState extends State<HighlightPreviewPage> {
  VideoPlayerController? _ctrl;
  final TextEditingController _captionController = TextEditingController();
  bool _attachAvatar = false;
  bool _isProcessingShare = false;
  final List<String> _generatedTempFiles = [];
  static const MethodChannel _shareChannel = MethodChannel('share_intent_channel');

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.videoPath))..initialize().then((_) { setState(() {}); _ctrl!.play(); });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _captionController.dispose();
    for (final f in _generatedTempFiles) {
      try { File(f).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Highlight 預覽')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _ctrl != null && _ctrl!.value.isInitialized
                  ? AspectRatio(aspectRatio: _ctrl!.value.aspectRatio, child: VideoPlayer(_ctrl!))
                  : const CircularProgressIndicator(),
            ),
          ),
          // share UI: caption, avatar toggle, targeted share buttons and system share
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _captionController,
                  maxLines: 2,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '說明文字（可選）'),
                ),
                const SizedBox(height: 8),
                if (widget.avatarPath != null && widget.avatarPath!.isNotEmpty && File(widget.avatarPath!).existsSync())
                  SwitchListTile(
                    title: const Text('加入頭像'),
                    value: _attachAvatar,
                    onChanged: (v) => setState(() => _attachAvatar = v),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.camera),
                        label: const Text('Instagram'),
                        onPressed: _isProcessingShare ? null : () => _shareToTarget('com.instagram.android'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.facebook),
                        label: const Text('Facebook'),
                        onPressed: _isProcessingShare ? null : () => _shareToTarget('com.facebook.katana'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.chat),
                        label: const Text('Line'),
                        onPressed: _isProcessingShare ? null : () => _shareToTarget('jp.naver.line.android'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('系統分享'),
                  onPressed: _isProcessingShare ? null : _shareSystem,
                ),
              ],
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
                    icon: const Icon(Icons.download),
                    label: const Text('匯出 debug 檔到下載'),
                    onPressed: () => _exportDebugToDownloads(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('分享 debug 檔'),
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
    await Share.shareXFiles([XFile(sharePath)], text: '我的揮桿 Highlight');
  }

  Future<void> _shareToTarget(String packageName) async {
    if (_isProcessingShare) return;
    setState(() => _isProcessingShare = true);
    try {
      final sharePath = await _prepareShareFile();
      if (sharePath == null) return;
      bool sharedByPackage = false;
      if (Platform.isAndroid) {
        try {
          final result = await _shareChannel.invokeMethod<bool>('shareToPackage', {
            'packageName': packageName,
            'filePath': sharePath,
            'mimeType': 'video/*',
            'text': '分享我的 TekSwing 揮桿影片',
          });
          sharedByPackage = result ?? false;
        } on PlatformException catch (_) {}
      }
      if (!sharedByPackage) {
        await Share.shareXFiles([XFile(sharePath)], text: '分享我的 TekSwing 揮桿影片');
      }
    } finally {
      if (mounted) setState(() => _isProcessingShare = false);
    }
  }

  Future<String?> _prepareShareFile() async {
    final bool wantsAvatar = _attachAvatar;
    final String caption = _captionController.text.trim();
    final bool wantsCaption = caption.isNotEmpty;
    if (wantsAvatar) {
      if (widget.avatarPath == null || widget.avatarPath!.isEmpty || !File(widget.avatarPath!).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到個人頭像檔案')));
        return null;
      }
    }
    final result = await VideoOverlayProcessor.process(
      inputPath: widget.videoPath,
      attachAvatar: wantsAvatar,
      avatarPath: wantsAvatar ? widget.avatarPath : null,
      attachCaption: wantsCaption,
      caption: caption,
    );
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('處理影片失敗')));
      return null;
    }
    if (result != widget.videoPath) _generatedTempFiles.add(result);
    return result;
  }

  Future<File?> _ensureDebugTempFile() async {
    if (widget.debugText == null || widget.debugText!.isEmpty) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final name = p.basenameWithoutExtension(widget.videoPath) + '_highlight_debug.txt';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法建立 debug 檔')));
      return;
    }
    await Share.shareXFiles([XFile(f.path)], text: 'Highlight debug log');
  }

  Future<void> _exportDebugToDownloads() async {
    final f = await _ensureDebugTempFile();
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法建立 debug 檔')));
      return;
    }

    try {
      // Android requires storage permission for writing to public folders on older API levels.
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted && !status.isLimited) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要儲存權限以匯出至下載資料夾')));
          return;
        }
      }

      final downloadsDir = await _getDownloadsDirectory();
      if (downloadsDir == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到下載資料夾')));
        return;
      }
      final dest = File(p.join(downloadsDir.path, p.basename(f.path)));
      await f.copy(dest.path);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已另存至：${dest.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
    }
  }

  Future<Directory?> _getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        // On Android, use external storage public Downloads (documented fallback)
        final directory = Directory('/storage/emulated/0/Download');
        if (await directory.exists()) return directory;
        return await getExternalStorageDirectory();
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return await getDownloadsDirectory();
      } else if (Platform.isIOS) {
        // iOS sandbox: use app Documents as best-effort
        return await getApplicationDocumentsDirectory();
      }
    } catch (_) {}
    return null;
  }
}
