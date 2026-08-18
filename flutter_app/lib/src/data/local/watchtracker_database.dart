import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/media_models.dart';

class WatchTrackerDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      path.join(dbPath, 'watchtracker.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE watchlist(
            id INTEGER NOT NULL,
            title TEXT NOT NULL,
            poster_path TEXT,
            media_type TEXT NOT NULL,
            content_category TEXT NOT NULL,
            content_status TEXT NOT NULL,
            total_episodes INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(id, media_type, content_category)
          )
        ''');
        await db.execute('''
          CREATE TABLE episode_progress(
            media_id INTEGER NOT NULL,
            season_number INTEGER NOT NULL,
            episode_number INTEGER NOT NULL,
            is_watched INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(media_id, season_number, episode_number)
          )
        ''');
        await db.execute('''
          CREATE TABLE watchlist_tombstones(
            id INTEGER NOT NULL,
            media_type TEXT NOT NULL,
            content_category TEXT NOT NULL,
            deleted_at INTEGER NOT NULL,
            PRIMARY KEY(id, media_type, content_category)
          )
        ''');
        await db.execute('''
          CREATE TABLE episode_progress_tombstones(
            media_id INTEGER NOT NULL,
            season_number INTEGER NOT NULL,
            episode_number INTEGER NOT NULL,
            deleted_at INTEGER NOT NULL,
            PRIMARY KEY(media_id, season_number, episode_number)
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_state(
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE watchlist ADD COLUMN updated_at INTEGER',
          );
          await db.execute(
            'UPDATE watchlist SET updated_at = added_at WHERE updated_at IS NULL',
          );
          await db.execute('''
            CREATE TABLE IF NOT EXISTS watchlist_tombstones(
              id INTEGER NOT NULL,
              media_type TEXT NOT NULL,
              content_category TEXT NOT NULL,
              deleted_at INTEGER NOT NULL,
              PRIMARY KEY(id, media_type, content_category)
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS episode_progress_tombstones(
              media_id INTEGER NOT NULL,
              season_number INTEGER NOT NULL,
              episode_number INTEGER NOT NULL,
              deleted_at INTEGER NOT NULL,
              PRIMARY KEY(media_id, season_number, episode_number)
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_state(
              key TEXT PRIMARY KEY,
              value INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> addToWatchlist({
    required int id,
    required String title,
    required String? posterPath,
    required MediaType mediaType,
    required WatchCategory category,
    required WatchStatus status,
    required int totalEpisodes,
    int? addedAtMillis,
    int? updatedAtMillis,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('watchlist', <String, Object?>{
      'id': id,
      'title': title,
      'poster_path': posterPath,
      'media_type': mediaType.value,
      'content_category': category.value,
      'content_status': status.value,
      'total_episodes': totalEpisodes,
      'added_at': addedAtMillis ?? now,
      'updated_at': updatedAtMillis ?? now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete(
      'watchlist_tombstones',
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
    );
  }

  Future<void> removeFromWatchlist({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
  }) async {
    final db = await database;
    await db.insert('watchlist_tombstones', <String, Object?>{
      'id': id,
      'media_type': mediaType.value,
      'content_category': category.value,
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete(
      'watchlist',
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
    );
  }

  Future<void> applyRemoteWatchlistDeletion({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
    required int deletedAtMillis,
  }) async {
    final db = await database;
    await db.insert('watchlist_tombstones', <String, Object?>{
      'id': id,
      'media_type': mediaType.value,
      'content_category': category.value,
      'deleted_at': deletedAtMillis,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete(
      'watchlist',
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
    );
  }

  Future<void> updateWatchStatus({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
    required WatchStatus status,
  }) async {
    final db = await database;
    await db.update(
      'watchlist',
      <String, Object?>{
        'content_status': status.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
    );
  }

  Future<void> updateWatchTotal({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
    required int totalEpisodes,
  }) async {
    final db = await database;
    await db.update(
      'watchlist',
      <String, Object?>{
        'total_episodes': totalEpisodes,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
    );
  }

  Future<bool> isInWatchlist({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
  }) async {
    final db = await database;
    final rows = await db.query(
      'watchlist',
      columns: <String>['id'],
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<WatchStatus?> getWatchStatus({
    required int id,
    required MediaType mediaType,
    required WatchCategory category,
  }) async {
    final db = await database;
    final rows = await db.query(
      'watchlist',
      columns: <String>['content_status'],
      where: 'id = ? AND media_type = ? AND content_category = ?',
      whereArgs: <Object>[id, mediaType.value, category.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WatchStatus.fromString(rows.first['content_status'] as String?);
  }

  Future<List<WatchCategory>> trackedCategoriesForMedia({
    required int id,
    required MediaType mediaType,
  }) async {
    final db = await database;
    final rows = await db.query(
      'watchlist',
      columns: <String>['content_category'],
      where: 'id = ? AND media_type = ?',
      whereArgs: <Object>[id, mediaType.value],
    );
    return rows
        .map((r) => WatchCategory.fromString(r['content_category'] as String?))
        .toList();
  }

  Future<List<Map<String, Object?>>> allWatchlist() async {
    final db = await database;
    return db.query('watchlist', orderBy: 'added_at DESC');
  }

  Future<List<Map<String, Object?>>> allWatchlistTombstones() async {
    final db = await database;
    return db.query('watchlist_tombstones', orderBy: 'deleted_at DESC');
  }

  Future<List<Map<String, Object?>>> watchlistByCategory(
    WatchCategory category,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        w.id,
        w.title,
        w.poster_path,
        w.media_type,
        w.content_category,
        w.content_status,
        w.total_episodes,
        w.added_at,
        COUNT(CASE WHEN p.is_watched = 1 THEN 1 END) AS watched_episodes,
        MAX(CASE WHEN p.is_watched = 1 THEN p.updated_at END) AS last_watched_at
      FROM watchlist w
      LEFT JOIN episode_progress p ON p.media_id = w.id
      WHERE w.content_category = ?
      GROUP BY w.id, w.title, w.poster_path, w.media_type, w.content_category, w.content_status, w.total_episodes, w.added_at
      ORDER BY w.added_at DESC
    ''',
      [category.value],
    );
  }

  Future<List<Map<String, Object?>>> episodeProgress(int mediaId) async {
    final db = await database;
    return db.query(
      'episode_progress',
      where: 'media_id = ?',
      whereArgs: <Object>[mediaId],
    );
  }

  Future<List<Map<String, Object?>>> allEpisodeProgress() async {
    final db = await database;
    return db.query('episode_progress');
  }

  Future<void> upsertEpisodeProgress({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
    required bool isWatched,
    int? updatedAtMillis,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('episode_progress', <String, Object?>{
      'media_id': mediaId,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'is_watched': isWatched ? 1 : 0,
      'updated_at': updatedAtMillis ?? now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> applyRemoteEpisodeProgressDeletion({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
    required int deletedAtMillis,
  }) async {
    final db = await database;
    await db.insert('episode_progress_tombstones', <String, Object?>{
      'media_id': mediaId,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'deleted_at': deletedAtMillis,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete(
      'episode_progress',
      where: 'media_id = ? AND season_number = ? AND episode_number = ?',
      whereArgs: <Object>[mediaId, seasonNumber, episodeNumber],
    );
  }

  Future<void> upsertEpisodeProgressBatch({
    required int mediaId,
    required List<Map<String, Object?>> updates,
  }) async {
    if (updates.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final update in updates) {
        final updatedAt = (update['updated_at'] as int?) ??
            DateTime.now().millisecondsSinceEpoch;
        await txn.insert('episode_progress', <String, Object?>{
          'media_id': mediaId,
          'season_number': update['season_number']!,
          'episode_number': update['episode_number']!,
          'is_watched': update['is_watched']!,
          'updated_at': updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> clearSessionData() async {
    final db = await database;
    await db.delete('watchlist');
    await db.delete('episode_progress');
    await db.delete('watchlist_tombstones');
    await db.delete('episode_progress_tombstones');
    await db.delete('sync_state');
  }

  Future<int?> getSyncState(String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_state',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['value'] as num).toInt();
  }

  Future<void> setSyncState(String key, int value) async {
    final db = await database;
    await db.insert('sync_state', <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
