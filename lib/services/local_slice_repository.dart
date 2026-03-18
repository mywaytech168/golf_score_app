import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 本地切片紀錄管理器
class LocalSliceRepository {
  static final LocalSliceRepository _instance = LocalSliceRepository._internal();
  static Database? _database;

  factory LocalSliceRepository() {
    return _instance;
  }

  LocalSliceRepository._internal();

  /// 取得資料庫實例
  Future<Database> get database async {
    _database ??= await _initializeDatabase();
    return _database!;
  }

  /// 初始化資料庫
  Future<Database> _initializeDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'local_slices.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 本地錄影紀錄表
        await db.execute('''
          CREATE TABLE local_recordings (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            total_slices INTEGER,
            sync_status TEXT DEFAULT 'local_only'
          )
        ''');

        // 本地切片紀錄表
        await db.execute('''
          CREATE TABLE local_slices (
            id TEXT PRIMARY KEY,
            recording_id TEXT NOT NULL,
            slice_index INTEGER,
            video_file_path TEXT NOT NULL,
            trajectory_csv_path TEXT,
            status TEXT DEFAULT 'pending',
            upload_time DATETIME,
            server_id TEXT,
            sync_timestamp DATETIME,
            FOREIGN KEY (recording_id) REFERENCES local_recordings(id),
            UNIQUE(recording_id, slice_index)
          )
        ''');

        // 建立索引便於查詢
        await db.execute(
          'CREATE INDEX idx_recording_id ON local_slices(recording_id)',
        );
        await db.execute(
          'CREATE INDEX idx_status ON local_slices(status)',
        );
        await db.execute(
          'CREATE INDEX idx_server_id ON local_slices(server_id)',
        );
      },
    );
  }

  /// 插入本地錄影紀錄
  Future<void> insertRecording({
    required String id,
    required String name,
    required int totalSlices,
  }) async {
    final db = await database;
    await db.insert(
      'local_recordings',
      {
        'id': id,
        'name': name,
        'total_slices': totalSlices,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'local_only',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 插入本地切片紀錄
  Future<void> insertSlice({
    required String sliceId,
    required String recordingId,
    required int sliceIndex,
    required String videoFilePath,
    required String trajectoryCSVPath,
  }) async {
    final db = await database;
    await db.insert(
      'local_slices',
      {
        'id': sliceId,
        'recording_id': recordingId,
        'slice_index': sliceIndex,
        'video_file_path': videoFilePath,
        'trajectory_csv_path': trajectoryCSVPath,
        'status': 'pending',
        'upload_time': null,
        'server_id': null,
        'sync_timestamp': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入切片
  Future<void> insertSlicesBatch(List<Map<String, dynamic>> slices) async {
    final db = await database;
    final batch = db.batch();

    for (final slice in slices) {
      batch.insert(
        'local_slices',
        slice,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit();
  }

  /// 更新切片狀態
  Future<void> updateSliceStatus(String sliceId, String status) async {
    final db = await database;
    await db.update(
      'local_slices',
      {
        'status': status,
        'upload_time': status == 'uploaded' ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [sliceId],
    );
  }

  /// 更新切片為已上傳且綁定伺服器 ID
  Future<void> markSliceAsUploaded(String sliceId, int serverId) async {
    final db = await database;
    await db.update(
      'local_slices',
      {
        'status': 'uploaded',
        'server_id': serverId.toString(),
        'upload_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sliceId],
    );
  }

  /// 同步切片狀態（來自伺服器）
  Future<void> syncSliceStatus(String sliceId, String serverStatus) async {
    final db = await database;
    await db.update(
      'local_slices',
      {
        'status': serverStatus,
        'sync_timestamp': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sliceId],
    );
  }

  /// 取得待上傳的切片
  Future<List<Map<String, dynamic>>> getPendingSlices(String recordingId) async {
    final db = await database;
    return await db.query(
      'local_slices',
      where: 'recording_id = ? AND status = ?',
      whereArgs: [recordingId, 'pending'],
      orderBy: 'slice_index ASC',
    );
  }

  /// 取得特定錄影的所有切片
  Future<List<Map<String, dynamic>>> getSlicesByRecording(String recordingId) async {
    final db = await database;
    return await db.query(
      'local_slices',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'slice_index ASC',
    );
  }

  /// 取得所有錄影紀錄
  Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    return await db.query(
      'local_recordings',
      orderBy: 'created_at DESC',
    );
  }

  /// 取得單個錄影的統計信息
  Future<Map<String, dynamic>> getRecordingStats(String recordingId) async {
    final db = await database;
    
    final slices = await db.query(
      'local_slices',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );

    final stats = {
      'total': slices.length,
      'pending': slices.where((s) => s['status'] == 'pending').length,
      'uploaded': slices.where((s) => s['status'] == 'uploaded').length,
      'processing': slices.where((s) => s['status'] == 'processing').length,
      'completed': slices.where((s) => s['status'] == 'completed').length,
      'failed': slices.where((s) => s['status'] == 'failed').length,
    };

    return stats;
  }

  /// 刪除錄影及其所有切片
  Future<void> deleteRecording(String recordingId) async {
    final db = await database;
    await db.delete(
      'local_slices',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
    await db.delete(
      'local_recordings',
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  /// 清空資料庫（測試用）
  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('local_slices');
    await db.delete('local_recordings');
  }
}
