import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'video_overlay_processor.dart';

/// High level service to generate a short highlight clip from a swing video.
///
/// This exposes `generateHighlight` which attempts to call a platform-native
/// implementation via MethodChannel `highlight_service`. If that is not
/// available (or on desktop), a best-effort ffmpeg-based fallback will be
/// executed (Windows/macOS/Linux) if `ffmpeg` is present on PATH.
class HighlightService {
  static const MethodChannel _ch = MethodChannel('highlight_service');

  /// Options for highlight generation.
  /// - segments: optional list of maps with 'start' and 'end' seconds to extract.
  /// - beforeMs/afterMs: fallback padding before/after detected impact in ms.
  /// - titleData: map of overlay text like name, course, speed values.
  static Future<String?> generateHighlight(
    String videoPath, {
    List<Map<String, dynamic>>? segments,
    int beforeMs = 3000,
    int afterMs = 3000,
    Map<String, String>? titleData,
    String? bgmPath,
    bool stabilize = true,
    bool addSlowMo = true,
  }) async {
    // shared debug buffer and writer used by both platform channel and fallback
    final StringBuffer _debugLog = StringBuffer();
    Future<void> _writeDebug() async {
      final String content = _debugLog.toString();
      // try write to app temp directory first (so Preview page can read it easily)
      try {
        final tempDir = await getTemporaryDirectory();
        final debugName = p.basenameWithoutExtension(videoPath) + '_highlight_debug.txt';
        final tempFile = File(p.join(tempDir.path, debugName));
        await tempFile.writeAsString(content);
      } catch (e) {
        // ignore write errors but try fallback below
      }

      // also attempt to write next to the original video file as a fallback for adb inspection
      try {
        final debugFile = File(p.join(p.dirname(videoPath), p.basenameWithoutExtension(videoPath) + '_highlight_debug.txt'));
        await debugFile.writeAsString(content);
      } catch (_) {}
    }

    // Try platform native first
    try {
      final Map<String, dynamic> args = {
        'videoPath': videoPath,
        'segments': segments,
        'beforeMs': beforeMs,
        'afterMs': afterMs,
        'titleData': titleData,
        'bgmPath': bgmPath,
        'stabilize': stabilize,
        'addSlowMo': addSlowMo,
      };
      final String? out = await _ch.invokeMethod<String>('generateHighlight', args);
      if (out != null && out.isNotEmpty) return out;
    } catch (e) {
      // Platform channel not implemented or failed, fall back to ffmpeg pipeline
      try {
        _debugLog.writeln('platform channel error: $e');
        await _writeDebug();
      } catch (_) {}
    }

  // Desktop fallback using ffmpeg if available

    if (!await _ffmpegAvailable()) {
      // On mobile, desktop ffmpeg won't exist. Try a simplified native overlay
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          // compose a simple caption from titleData
          String caption = '';
          if (titleData != null && titleData.isNotEmpty) {
            caption = titleData.entries.map((e) => '${e.key}: ${e.value}').join('  ');
          }
          final String? out = await VideoOverlayProcessor.process(
            inputPath: videoPath,
            attachAvatar: false,
            avatarPath: null,
            attachCaption: caption.isNotEmpty,
            caption: caption,
          );
          if (out != null && out.isNotEmpty) return out;
          _debugLog.writeln('mobile overlay fallback returned null');
          await _writeDebug();
        } catch (e) {
          try { _debugLog.writeln('mobile overlay fallback error: $e'); await _writeDebug(); } catch (_) {}
        }
      }
      try {
        _debugLog.writeln('ffmpeg not found on PATH; desktop fallback unavailable.');
        await _writeDebug();
      } catch (_) {}
      return null;
    }

    final String tmpDir = Directory.systemTemp.createTempSync('swing_highlight_').path;
  final String outPath = p.join(tmpDir, p.basenameWithoutExtension(videoPath) + '_highlight.mp4');

    try {
      // Decide segments: if segments provided, use them; otherwise take first segment from provided video center
      final List<Map<String, dynamic>> segs = segments ?? [
        {'start': 0.0, 'end': min(10.0, _getVideoDurationSync(videoPath) ?? 10.0)}
      ];

      // For simplicity we only process the first segment in this fallback
      final double start = (segs.first['start'] as num).toDouble();
      final double end = (segs.first['end'] as num).toDouble();
  // duration hint available via ffprobe if needed (not used here)

      // compute trim start/end with padding
      final double trimStart = max(0.0, start - beforeMs / 1000.0);
      final double trimEnd = end + afterMs / 1000.0;

      // intermediate file paths
      final String trimmed = p.join(tmpDir, 'trim.mp4');
      final String stabilized = p.join(tmpDir, 'stab.mp4');
      final String slowmo = p.join(tmpDir, 'slowmo.mp4');
      final String withAudio = p.join(tmpDir, 'withbgm.mp4');

      // 1) Trim
  final int rcTrim = await _runFFmpeg(['-y', '-ss', '$trimStart', '-i', videoPath, '-to', '${trimEnd - trimStart}', '-c', 'copy', trimmed], debugLog: _debugLog);
      _debugLog.writeln('trim rc=$rcTrim');
      if (rcTrim != 0) {
        await _writeDebug();
        return null;
      }

      // 2) Stabilize (use vidstabdetect + vidstabtransform if available)
      // We'll try a generic deshake filter if vidstab tools are not present
      bool didStab = false;
      if (stabilize) {
        // Try vidstab workflow (requires ffmpeg with vidstab)
  final int rc1 = await _runFFmpeg(['-y', '-i', trimmed, '-vf', 'vidstabdetect=shakiness=10:accuracy=15', '-f', 'null', '-'], workingDir: tmpDir, debugLog: _debugLog);
        _debugLog.writeln('vidstabdetect rc=$rc1');
        if (rc1 == 0) {
          final int rc2 = await _runFFmpeg(['-y', '-i', trimmed, '-vf', "vidstabtransform=input='transforms.trf':smoothing=30", '-c:v', 'libx264', '-preset', 'fast', '-crf', '23', stabilized], workingDir: tmpDir, debugLog: _debugLog);
          _debugLog.writeln('vidstabtransform rc=$rc2');
          didStab = rc2 == 0;
        } else {
          // fallback: deshake filter
          final int rc = await _runFFmpeg(['-y', '-i', trimmed, '-vf', 'deshake', '-c:v', 'libx264', '-preset', 'fast', '-crf', '23', stabilized], debugLog: _debugLog);
          _debugLog.writeln('deshake rc=$rc');
          didStab = rc == 0;
        }
      }
      final String stageInput = didStab ? stabilized : trimmed;

      // 3) Slow motion around impact: naive approach – slow down whole clip or insert a slowed 0.2x region
      if (addSlowMo) {
        // For the fallback, slow whole clip by 0.95x and create a 0.2x clone of a center portion
        // Find center time
        final double center = (trimStart + trimEnd) / 2.0;
        final double smStart = max(trimStart, center - 0.15); // 150ms before
        final double smEnd = min(trimEnd, center + 0.15); // 150ms after
        final String slowSeg = p.join(tmpDir, 'sm_segment.mp4');
        final String beforeSeg = p.join(tmpDir, 'before.mp4');
        final String afterSeg = p.join(tmpDir, 'after.mp4');

        // extract before, slow segment, after
  final int rcBefore = await _runFFmpeg(['-y', '-ss', '$trimStart', '-i', stageInput, '-to', '${smStart - trimStart}', '-c', 'copy', beforeSeg], debugLog: _debugLog);
  _debugLog.writeln('slowmo before rc=$rcBefore');
  if (rcBefore != 0) { await _writeDebug(); return null; }
  final int rcSlow = await _runFFmpeg(['-y', '-ss', '$smStart', '-i', stageInput, '-to', '${smEnd - smStart}', '-an', '-vf', 'setpts=5.0*PTS', slowSeg], debugLog: _debugLog); // 0.2x => setpts=5.0
  _debugLog.writeln('slowmo segment rc=$rcSlow');
  if (rcSlow != 0) { await _writeDebug(); return null; }
  final int rcAfter = await _runFFmpeg(['-y', '-ss', '$smEnd', '-i', stageInput, '-to', '${trimEnd - smEnd}', '-c', 'copy', afterSeg], debugLog: _debugLog);
  _debugLog.writeln('slowmo after rc=$rcAfter');
  if (rcAfter != 0) { await _writeDebug(); return null; }

        // concat them
        final String concatList = p.join(tmpDir, 'concat.txt');
        await File(concatList).writeAsString('file \'' + beforeSeg.replaceAll("'", "\\'") + "'\nfile '" + slowSeg.replaceAll("'", "\\'") + "'\nfile '" + afterSeg.replaceAll("'", "\\'") + "'\n");
  final int rcConcat = await _runFFmpeg(['-y', '-f', 'concat', '-safe', '0', '-i', concatList, '-c', 'copy', slowmo], debugLog: _debugLog);
  _debugLog.writeln('concat rc=$rcConcat');
  if (rcConcat != 0) { await _writeDebug(); return null; }
      } else {
        await File(stageInput).copy(slowmo);
      }

      // 4) Add background music: mix audio with ducking
      if (bgmPath != null && await File(bgmPath).exists()) {
        // ensure bgm length >= clip length by looping
  final int rcBgm = await _runFFmpeg(['-y', '-i', slowmo, '-stream_loop', '-1', '-i', bgmPath, '-filter_complex', '[1:a]volume=0.5[a1];[0:a][a1]amix=inputs=2:duration=first:dropout_transition=2[aout]', '-map', '0:v', '-map', '[aout]', '-c:v', 'copy', '-c:a', 'aac', withAudio], debugLog: _debugLog);
  _debugLog.writeln('bgm mix rc=$rcBgm');
  if (rcBgm != 0) { await _writeDebug(); return null; }
      } else {
        await File(slowmo).copy(withAudio);
      }

      // 5) Overlay text, logo
  // prepare drawtext args from titleData
  final List<String> vfParts = <String>[];
      if (titleData != null && titleData.isNotEmpty) {
        final double y = 20.0;
        int i = 0;
        for (final kv in titleData.entries) {
          final k = kv.key;
          final v = kv.value.replaceAll("'", "\\'");
          vfParts.add("drawtext=text='$k: $v':fontcolor=white:fontsize=24:x=10:y=${y + i * 28}");
          i++;
        }
      }

      // attempt to place logo if present in titleData as 'logo'
      if (titleData != null && titleData.containsKey('logo')) {
        final String logoPath = titleData['logo']!;
        if (await File(logoPath).exists()) {
          // logo overlay top-right
          final String logoOverlay = "movie=${logoPath},scale=80:-1[logo];[0:v][logo]overlay=W-w-10:10";
          vfParts.add(logoOverlay);
        }
      }

      String vf = vfParts.join(',');
      if (vf.isEmpty) vf = 'null';

  final int rc = await _runFFmpeg(['-y', '-i', withAudio, '-vf', vf, '-c:a', 'copy', outPath], debugLog: _debugLog);
      _debugLog.writeln('final overlay rc=$rc');
      if (rc != 0) {
        await _writeDebug();
        return null;
      }

      return outPath;
    } finally {
      // try cleanup of tmpDir
      try {
        Directory(tmpDir).deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static Future<bool> _ffmpegAvailable() async {
    try {
      final ProcessResult r = await Process.run('ffmpeg', ['-version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  

  static Future<int> _runFFmpeg(List<String> args, {String? workingDir, StringBuffer? debugLog}) async {
    try {
      final Process process = await Process.start('ffmpeg', args, workingDirectory: workingDir, runInShell: true);
      // capture stdout/stderr and forward to debugLog
      process.stdout.transform(SystemEncoding().decoder).listen((d) {
        stdout.write(d);
        try { debugLog?.writeln('[ffmpeg stdout] $d'); } catch (_) {}
      });
      process.stderr.transform(SystemEncoding().decoder).listen((d) {
        stderr.write(d);
        try { debugLog?.writeln('[ffmpeg stderr] $d'); } catch (_) {}
      });
      final int code = await process.exitCode;
      if (debugLog != null) debugLog.writeln('ffmpeg exitCode=$code');
      return code;
    } catch (e) {
      try { debugLog?.writeln('ffmpeg start error: $e'); } catch (_) {}
      return -1;
    }
  }

  

  static double? _getVideoDurationSync(String path) {
    try {
      // best-effort using ffprobe
      final pr = Process.runSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', path], runInShell: true);
      if (pr.exitCode == 0) {
        final out = pr.stdout.toString().trim();
        return double.tryParse(out);
      }
    } catch (_) {}
    return null;
  }
}
