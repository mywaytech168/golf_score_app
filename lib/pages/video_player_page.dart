import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:golf_score_app/services/audio_analysis_service.dart';
import 'dart:convert';

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
  });

  final String videoPath;
  final String? avatarPath;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  String? _errorMessage;
  String? _classificationLabel;
  Map<String, double?> _classificationFeatures = {};
  bool _isAnalyzing = false;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    final file = File(widget.videoPath);
    if (!file.existsSync()) {
      setState(() {
        _errorMessage = 'Video file not found.';
      });
      return;
    }

    final controller = VideoPlayerController.file(file);
    setState(() {
      _controller = controller;
      _initializeFuture = controller.initialize().then((_) {
        controller.setLooping(true);
        controller.play();
        // Attempt to load existing per-video classification for display (fire-and-forget)
        _loadClassificationForVideo();
        // Also re-run analysis on the stored video so playback always shows fresh results.
        _reAnalyze();
      }).catchError((error) {
        setState(() {
          _errorMessage = 'Unable to play this video: $error';
        });
      });
    });
  }

  String _mapPredToLabel(String pred) {
  final p = pred.toLowerCase().trim();
  if (p.isEmpty) return 'Unknown';
  // Accept both canonical class tokens and human-friendly feedback strings
  if (p.contains('pro')) return 'Pro';
  if (p.contains('sweet') || p.contains('good')) return 'Sweet';
  if (p.contains('bad') || p.contains('keep') || p.contains('try')) return 'Try again';
  return pred.trim();
  }

  Future<void> _loadClassificationForVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) return;
      final parent = file.parent;
      // Check batch file first
      final batchFile = File('${parent.path}${Platform.pathSeparator}batch_classify.csv');
      String? pred;
      if (await batchFile.exists()) {
        final lines = await batchFile.readAsLines();
        for (var i = 1; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.isEmpty) continue;
          if (cols[0].trim() == file.uri.pathSegments.last) {
            pred = cols.length > 1 ? cols[1].trim() : null;
            break;
          }
        }
      }
      // Look for per-video classify report and parse robustly
      final per = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_classify_report.csv');
      if (await per.exists()) {
        final lines = await per.readAsLines();
        final Map<String, String> kv = {};
        for (final raw in lines) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final parsed = _splitCsvLine(line);
          if (parsed.isEmpty) continue;
          final key = parsed[0].trim();
          if (key.toLowerCase() == 'label') {
            final lab = parsed.length > 1 ? parsed[1].trim() : null;
            if (lab != null && lab.isNotEmpty) {
              pred = lab;
            }
            continue;
          }
          if (key.startsWith('__') || key.toLowerCase().contains('feature') || key.toLowerCase().contains('title')) continue;
          final value = parsed.length > 1 ? parsed[1].trim() : '';
          kv[key] = value;
        }
        final wanted = ['rms_dbfs','spectral_centroid','sharpness_hfxloud','highband_amp','peak_dbfs'];
        final Map<String, double?> picked = {};
        for (final k in wanted) picked[k] = kv.containsKey(k) ? double.tryParse(kv[k]!) : null;
        if (mounted) setState(() => _classificationFeatures = picked);
      } else {
        // fallback: check analysis debug JSON written by analyzer
        final debugFile = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_analysis_debug.json');
        if (await debugFile.exists()) {
          try {
            final content = await debugFile.readAsString();
            final Map<String, dynamic> json = content.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(content)) : {};
            final summary = json['summary'] as Map<String, dynamic>?;
            if (summary != null) {
              final Map<String, double?> picked = {
                'rms_dbfs': _toDouble(summary['rms_dbfs']),
                'spectral_centroid': _toDouble(summary['spectral_centroid']),
                'sharpness_hfxloud': _toDouble(summary['sharpness_hfxloud']),
                'highband_amp': _toDouble(summary['highband_amp']),
                'peak_dbfs': _toDouble(summary['peak_dbfs']),
              };
              if (mounted) setState(() => _classificationFeatures = picked);
              if (summary.containsKey('audio_class')) pred = summary['audio_class']?.toString();
            }
          } catch (_) {}
        }
      }

      if (pred != null && pred.isNotEmpty) {
        final label = _mapPredToLabel(pred);
        if (mounted) setState(() => _classificationLabel = label);
      }
    } catch (e) {
      // ignore
    }
  }

    // Small CSV parser for simple lines (handles quoted fields)
    List<String> _splitCsvLine(String line) {
      final List<String> out = [];
      final sb = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            // escaped quote
            sb.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (ch == ',' && !inQuotes) {
          out.add(sb.toString());
          sb.clear();
        } else {
          sb.write(ch);
        }
      }
      out.add(sb.toString());
      return out;
    }

  Future<void> _reAnalyze() async {
    if (_isAnalyzing) return;
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });
    try {
      final result = await AudioAnalysisService.analyzeVideo(widget.videoPath);
      // Debug: log the full result for troubleshooting
      try {
        print('Audio analysis result for ${widget.videoPath}: $result');
      } catch (_) {}
      final Map<String, dynamic>? summary = result['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        final Map<String, double?> feats = <String, double?>{
          'rms_dbfs': _toDouble(summary['rms_dbfs']),
          'spectral_centroid': _toDouble(summary['spectral_centroid']),
          'sharpness_hfxloud': _toDouble(summary['sharpness_hfxloud']),
          'highband_amp': _toDouble(summary['highband_amp']),
          'peak_dbfs': _toDouble(summary['peak_dbfs']),
        };
        String? pred;
        if (summary.containsKey('audio_class')) {
          pred = summary['audio_class']?.toString();
        } else if (summary.containsKey('audio_feedback')) {
          pred = summary['audio_feedback']?.toString();
        }

        if (mounted) {
          setState(() {
            _classificationFeatures = feats;
            if (pred != null) _classificationLabel = _mapPredToLabel(pred);
          });
        }

        // Persist per-video CSV so future loads can read the values without re-analysis.
        try {
          final file = File(widget.videoPath);
          if (await file.exists()) {
            final csvFile = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_classify_report.csv');
            final List<String> rows = <String>[];
            rows.add('feature,target,weight');
            feats.forEach((k, v) {
              rows.add('$k,${v == null ? '' : v.toString()},1.0');
            });
            if (pred != null && pred.isNotEmpty) {
              rows.add('label,${pred.toString()},1.0');
            }
            await csvFile.writeAsString(rows.join('\n'));
          }
        } catch (_) {
          // ignore persistence errors
        }
        // Also write a debug JSON next to the video to inspect analyzer output.
        try {
          final debugFile = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_analysis_debug.json');
          await debugFile.writeAsString(jsonEncode(result));
        } catch (_) {}
      }
    } catch (e) {
      // show error, then attempt to load existing CSV as fallback
      if (mounted) {
        setState(() => _analysisError = 'Analysis failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
      // log error
      try { print('Audio analysis error for ${widget.videoPath}: $e'); } catch (_) {}
      // Try fallback to existing per-video CSV
      await _loadClassificationForVideo();
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _showAnalysisFilesDebug() async {
    final file = File(widget.videoPath);
    if (!await file.exists()) {
      if (mounted) _showSnack('找不到影片檔案以檢查分析檔案');
      return;
    }
    final base = widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '');
    final csvFile = File(base + '_classify_report.csv');
    final debugFile = File(base + '_analysis_debug.json');
    String message = '';
    if (await csvFile.exists()) {
      try {
        final txt = await csvFile.readAsString();
        message += '=== classify_report.csv ===\n';
        message += (txt.length > 200 ? txt.substring(0, 200) + '...' : txt) + '\n\n';
      } catch (e) {
        message += 'Error reading classify_report.csv: $e\n\n';
      }
    } else {
      message += 'classify_report.csv not found\n\n';
    }

    if (await debugFile.exists()) {
      try {
        final txt = await debugFile.readAsString();
        message += '=== analysis_debug.json ===\n';
        message += (txt.length > 200 ? txt.substring(0, 200) + '...' : txt) + '\n\n';
      } catch (e) {
        message += 'Error reading analysis_debug.json: $e\n\n';
      }
    } else {
      message += 'analysis_debug.json not found\n\n';
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analysis files'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  // Small helper to show a SnackBar from anywhere in this state class.
  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Review'),
        actions: [
          if (widget.avatarPath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: CircleAvatar(
                backgroundImage: FileImage(File(widget.avatarPath!)),
              ),
            ),
        ],
      ),
      body: Center(
        child: _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              )
            : controller == null
                ? const CircularProgressIndicator()
                : FutureBuilder<void>(
                    future: _initializeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          controller.value.isInitialized) {
                        return Column(
                          children: [
                            AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller),
                            ),
          // Analysis result card under the video (always visible)
          Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
            // Also show a small debug button so the user can inspect analysis files on-device
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showAnalysisFilesDebug(),
                icon: const Icon(Icons.bug_report, size: 18),
                label: const Text('檢查分析檔'),
              ),
            ),
            Text('評分：${_classificationLabel ?? '--'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_classificationFeatures.isNotEmpty)
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 6,
                                        children: [
                                          Text('rms: ${_classificationFeatures['rms_dbfs'] == null ? '--' : _classificationFeatures['rms_dbfs']!.toStringAsFixed(2)}'),
                                          Text('sc: ${_classificationFeatures['spectral_centroid'] == null ? '--' : _classificationFeatures['spectral_centroid']!.toStringAsFixed(1)}'),
                                          Text('sh: ${_classificationFeatures['sharpness_hfxloud'] == null ? '--' : _classificationFeatures['sharpness_hfxloud']!.toStringAsFixed(2)}'),
                                          Text('highband: ${_classificationFeatures['highband_amp'] == null ? '--' : _classificationFeatures['highband_amp']!.toStringAsFixed(2)}'),
                                          Text('peak: ${_classificationFeatures['peak_dbfs'] == null ? '--' : _classificationFeatures['peak_dbfs']!.toStringAsFixed(2)}'),
                                        ],
                                      ),
                                    if (_classificationFeatures.isEmpty) const Text('No analysis available yet.'),
                                    // Legend explaining labels
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text('Legend:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                          SizedBox(height: 2),
                                          Text('Pro → Pro', style: TextStyle(fontSize: 12)),
                                          Text('Sweet → Good', style: TextStyle(fontSize: 12)),
                                          Text('Keep going! → Try again', style: TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    if (_analysisError != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(_analysisError!, style: const TextStyle(color: Colors.redAccent)),
                                      ),
            const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: _isAnalyzing ? null : _reAnalyze,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Re-run analysis'),
                                        ),
                                        const SizedBox(width: 12),
                                        if (_isAnalyzing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Unable to load video: ${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return const CircularProgressIndicator();
                    },
                  ),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                if (!controller.value.isInitialized) {
                  return;
                }
                setState(() {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                });
              },
              child: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }
}
