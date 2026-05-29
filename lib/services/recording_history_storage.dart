import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/recording_history_entry.dart';

/// 錄影歷史儲存工具（sqflite 版本）
///
/// - 以 filePath 為 PRIMARY KEY，支援原子 upsert / delete
/// - 首次啟動時自動從舊版 recording_history.json 遷移資料
/// - 提供向下相容的 loadHistory() / saveHistory() API，
///   並新增精確操作 upsertEntry() / deleteEntry() 避免競態條件
class RecordingHistoryStorage {
  RecordingHistoryStorage._();

  static final RecordingHistoryStorage instance = RecordingHistoryStorage._();

  static const String _folderName  = 'golf_recordings';
  static const String _legacyJson  = 'recording_history.json';
  static const String _dbName      = 'recording_history.db';
  static const int    _dbVersion   = 6;
  static const String _table       = 'recordings';

  Database? _db;

  // ── 初始化 ────────────────────────────────────────────────────

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = p.join(docsDir.path, _folderName, _dbName);

    // 確保資料夾存在
    final dir = Directory(p.join(docsDir.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            filePath          TEXT PRIMARY KEY,
            roundIndex        INTEGER NOT NULL,
            recordedAt        TEXT NOT NULL,
            createdAt         TEXT,
            durationSeconds   INTEGER NOT NULL,
            customName        TEXT,
            thumbnailPath     TEXT,
            videoType         TEXT NOT NULL DEFAULT 'original',
            isClipped         INTEGER NOT NULL DEFAULT 0,
            isAnalyzed        INTEGER NOT NULL DEFAULT 0,
            hitSecond         REAL,
            startSecond       REAL,
            endSecond         REAL,
            audioCrispness    REAL,
            bestSpeedValue    REAL,
            goodShot          INTEGER,
            audioLabel        TEXT,
            sourceVideoPath   TEXT,
            audioTags         TEXT,
            shareCode         TEXT,
            shareExpiresAt    TEXT,
            sharerName        TEXT,
            hasAiCoachAnalysis  INTEGER NOT NULL DEFAULT 0,
            isUploaded          INTEGER NOT NULL DEFAULT 0,
            recordedAspectRatio TEXT,
            swingPostureLabel   TEXT,
            geminiPostureLabel  TEXT,
            postureAnalysisId   TEXT,
            audioPassCount      INTEGER,
            audioPasses         TEXT,
            audioFeatureValues  TEXT
          )
        ''');
        // 索引加速常用排序/篩選
        await db.execute('CREATE INDEX idx_recordedAt ON $_table (recordedAt DESC)');
        await db.execute('CREATE INDEX idx_sourceVideoPath ON $_table (sourceVideoPath)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE $_table ADD COLUMN recordedAspectRatio TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_table ADD COLUMN swingPostureLabel TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE $_table ADD COLUMN postureAnalysisId TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE $_table ADD COLUMN audioPassCount INTEGER');
          await db.execute('ALTER TABLE $_table ADD COLUMN audioPasses TEXT');
          await db.execute('ALTER TABLE $_table ADD COLUMN audioFeatureValues TEXT');
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE $_table ADD COLUMN geminiPostureLabel TEXT');
        }
      },
    );

    // 若表格是空的，嘗試從舊 JSON 遷移
    final count = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM $_table'),
    ) ?? 0;
    if (count == 0) {
      await _migrateFromJson(_db!);
    }

    return _db!;
  }

  /// 從舊版 JSON 遷移，成功後重命名 json 為 .bak 備份
  Future<void> _migrateFromJson(Database db) async {
    try {
      final docsDir  = await getApplicationDocumentsDirectory();
      final jsonFile = File(p.join(docsDir.path, _folderName, _legacyJson));
      if (!await jsonFile.exists()) return;

      final content = await jsonFile.readAsString();
      if (content.trim().isEmpty) return;

      final decoded = jsonDecode(content);
      if (decoded is! List || decoded.isEmpty) return;

      final entries = <RecordingHistoryEntry>[];
      for (final item in decoded) {
        try {
          final map = item is Map<String, dynamic>
              ? item
              : (item as Map).map((k, v) => MapEntry(k.toString(), v));
          entries.add(RecordingHistoryEntry.fromJson(map));
        } catch (_) {}
      }

      // 批次寫入（事務保原子性）
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final e in entries) {
          batch.insert(
            _table,
            _toRow(e),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

      // 重命名 JSON 為備份，不刪除避免意外
      await jsonFile.rename('${jsonFile.path}.bak');
    } catch (e) {
      debugPrint('⚠️ [RecordingHistoryStorage] JSON→SQLite 遷移失敗: $e');
    }
  }

  // ── 公開 API ──────────────────────────────────────────────────

  /// 讀取全部歷史（按 recordedAt 降冪），不再過濾遺失檔案
  /// 呼叫端若需要過濾，可自行使用 File(e.filePath).existsSync()
  Future<List<RecordingHistoryEntry>> loadHistory() async {
    try {
      final db   = await _openDb();
      final rows = await db.query(_table, orderBy: 'recordedAt DESC');
      final entries = rows.map(_fromRow).toList();
      // 清理孤兒 clip.mp4：若同一 session 目錄下已有 skeleton.mp4 或 final.mp4
      // 代表分析已完成但舊 clip.mp4 條目未被刪除（歷史 bug 殘留），自動移除
      await _purgeOrphanClips(db, entries);
      return (await db.query(_table, orderBy: 'recordedAt DESC')).map(_fromRow).toList();
    } catch (e) {
      debugPrint('❌ [RecordingHistoryStorage] loadHistory 失敗: $e');
      return [];
    }
  }

  /// 清理孤兒 clip.mp4 條目（分析後 clip.mp4 未被刪除的殘留）
  Future<void> _purgeOrphanClips(Database db, List<RecordingHistoryEntry> entries) async {
    // 取得所有已分析（isAnalyzed=1）且 filePath 非 clip.mp4 的 session 目錄
    final analyzedDirs = entries
        .where((e) => e.isAnalyzed && !e.filePath.endsWith('clip.mp4'))
        .map((e) => p.dirname(e.filePath))
        .toSet();

    // 找出同一目錄下還殘留的 clip.mp4 孤兒條目
    final orphans = entries.where((e) =>
        e.filePath.endsWith('clip.mp4') &&
        analyzedDirs.contains(p.dirname(e.filePath)));

    if (orphans.isEmpty) return;

    for (final o in orphans) {
      await db.delete(_table, where: 'filePath = ?', whereArgs: [o.filePath]);
      debugPrint('🧹 [RecordingHistoryStorage] 清理孤兒條目：${o.filePath}');
    }
  }

  /// 相容舊 API：整批寫入（先清除再插入）
  /// 建議逐步改用 upsertEntry() / deleteEntry() 以避免競態條件
  Future<void> saveHistory(List<RecordingHistoryEntry> entries) async {
    try {
      final db = await _openDb();
      await db.transaction((txn) async {
        // 刪除不在列表中的記錄
        if (entries.isNotEmpty) {
          final paths = entries.map((e) => e.filePath).toList();
          final placeholders = List.filled(paths.length, '?').join(',');
          await txn.rawDelete(
            'DELETE FROM $_table WHERE filePath NOT IN ($placeholders)',
            paths,
          );
        } else {
          await txn.delete(_table);
        }
        // Upsert 所有
        final batch = txn.batch();
        for (final e in entries) {
          batch.insert(
            _table,
            _toRow(e),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      debugPrint('❌ [RecordingHistoryStorage] saveHistory 失敗: $e');
    }
  }

  /// 精確插入或更新單筆記錄（原子操作，無競態風險）
  Future<void> upsertEntry(RecordingHistoryEntry entry) async {
    try {
      final db = await _openDb();
      await db.insert(
        _table,
        _toRow(entry),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('❌ [RecordingHistoryStorage] upsertEntry 失敗: $e');
    }
  }

  /// 精確刪除單筆記錄（原子操作）
  Future<void> deleteEntry(String filePath) async {
    try {
      final db = await _openDb();
      await db.delete(_table, where: 'filePath = ?', whereArgs: [filePath]);
    } catch (e) {
      debugPrint('❌ [RecordingHistoryStorage] deleteEntry 失敗: $e');
    }
  }

  // ── 序列化工具 ────────────────────────────────────────────────

  static Map<String, dynamic> _toRow(RecordingHistoryEntry e) => {
    'filePath':           e.filePath,
    'roundIndex':         e.roundIndex,
    'recordedAt':         e.recordedAt.toIso8601String(),
    'createdAt':          e.createdAt?.toIso8601String(),
    'durationSeconds':    e.durationSeconds,
    'customName':         e.customName,
    'thumbnailPath':      e.thumbnailPath,
    'videoType':          e.videoType.name,
    'isClipped':          e.isClipped    ? 1 : 0,
    'isAnalyzed':         e.isAnalyzed   ? 1 : 0,
    'hitSecond':          e.hitSecond,
    'startSecond':        e.startSecond,
    'endSecond':          e.endSecond,
    'audioCrispness':     e.audioCrispness,
    'bestSpeedValue':     e.bestSpeedValue,
    'goodShot':           e.goodShot == null ? null : (e.goodShot! ? 1 : 0),
    'audioLabel':         e.audioLabel,
    'sourceVideoPath':    e.sourceVideoPath,
    'audioTags':          e.audioTags != null ? jsonEncode(e.audioTags) : null,
    'shareCode':          e.shareCode,
    'shareExpiresAt':     e.shareExpiresAt?.toUtc().toIso8601String(),
    'sharerName':         e.sharerName,
    'hasAiCoachAnalysis':  e.hasAiCoachAnalysis  ? 1 : 0,
    'isUploaded':          e.isUploaded          ? 1 : 0,
    'recordedAspectRatio': e.recordedAspectRatio,
    'swingPostureLabel':   e.swingPostureLabel,
    'geminiPostureLabel':  e.geminiPostureLabel,
    'postureAnalysisId':   e.postureAnalysisId,
    'audioPassCount':      e.audioPassCount,
    'audioPasses':         e.audioPasses != null ? jsonEncode(e.audioPasses) : null,
    'audioFeatureValues':  e.audioFeatureValues != null ? jsonEncode(e.audioFeatureValues) : null,
  };

  static RecordingHistoryEntry _fromRow(Map<String, dynamic> row) {
    VideoType videoType = VideoType.original;
    final videoTypeStr = row['videoType'] as String?;
    if (videoTypeStr != null) {
      try {
        videoType = VideoType.values.byName(videoTypeStr);
      } catch (_) {}
    }

    List<String>? audioTags;
    final rawTags = row['audioTags'] as String?;
    if (rawTags != null && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) audioTags = decoded.whereType<String>().toList();
      } catch (_) {}
    }

    Map<String, bool>? audioPasses;
    final rawPasses = row['audioPasses'] as String?;
    if (rawPasses != null && rawPasses.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPasses);
        if (decoded is Map) {
          audioPasses = decoded.map((k, v) => MapEntry(k as String, (v as bool?) ?? false));
        }
      } catch (_) {}
    }

    Map<String, double>? audioFeatureValues;
    final rawFeatures = row['audioFeatureValues'] as String?;
    if (rawFeatures != null && rawFeatures.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFeatures);
        if (decoded is Map) {
          audioFeatureValues = decoded.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
        }
      } catch (_) {}
    }

    final rawThumb = (row['thumbnailPath'] as String?)?.trim();

    return RecordingHistoryEntry(
      filePath:           (row['filePath']          as String?) ?? '',
      roundIndex:         (row['roundIndex']         as int?)    ?? 1,
      recordedAt:         DateTime.tryParse(row['recordedAt'] as String? ?? '') ?? DateTime.now(),
      createdAt:          row['createdAt'] != null ? DateTime.tryParse(row['createdAt'] as String) : null,
      durationSeconds:    (row['durationSeconds']    as int?)    ?? 0,
      customName:         row['customName']          as String?,
      thumbnailPath:      rawThumb == null || rawThumb.isEmpty ? null : rawThumb,
      videoType:          videoType,
      isClipped:          (row['isClipped']          as int?)    == 1,
      isAnalyzed:         (row['isAnalyzed']         as int?)    == 1,
      hitSecond:          (row['hitSecond']          as num?)?.toDouble(),
      startSecond:        (row['startSecond']        as num?)?.toDouble(),
      endSecond:          (row['endSecond']          as num?)?.toDouble(),
      audioCrispness:     (row['audioCrispness']     as num?)?.toDouble(),
      bestSpeedValue:     (row['bestSpeedValue']     as num?)?.toDouble(),
      goodShot:           row['goodShot'] != null ? (row['goodShot'] as int) == 1 : null,
      audioLabel:         row['audioLabel']          as String?,
      sourceVideoPath:    row['sourceVideoPath']     as String?,
      audioTags:          audioTags,
      audioPassCount:     row['audioPassCount']       as int?,
      audioPasses:        audioPasses,
      audioFeatureValues: audioFeatureValues,
      shareCode:          row['shareCode']           as String?,
      shareExpiresAt:     row['shareExpiresAt'] != null
          ? DateTime.tryParse(row['shareExpiresAt'] as String)
          : null,
      sharerName:         row['sharerName']          as String?,
      hasAiCoachAnalysis:  (row['hasAiCoachAnalysis']  as int?) == 1,
      isUploaded:          (row['isUploaded']          as int?) == 1,
      recordedAspectRatio:  row['recordedAspectRatio']          as String?,
      swingPostureLabel:    row['swingPostureLabel']             as String?,
      geminiPostureLabel:   row['geminiPostureLabel']            as String?,
      postureAnalysisId:    row['postureAnalysisId']             as String?,
    );
  }
}
