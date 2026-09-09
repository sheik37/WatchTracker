import 'package:sqflite/sqflite.dart';

import 'watchtracker_database.dart';

/// Types d'actions possibles en queue
enum OfflineActionType {
  addToWatchlist,
  removeFromWatchlist,
  markEpisodeWatched,
  markEpisodeUnwatched,
  markMovieWatched,
  updateWatchStatus,
  updateWatchProgressTotal,
  deleteEpisodeWatchEvent,
  deleteMovieWatchEvent,
}

/// Représente une action en attente de synchronisation
class PendingAction {
  PendingAction({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastRetryAt,
  });

  final int id;
  final OfflineActionType actionType;
  final String payload; // JSON serialized
  final int createdAt; // milliseconds since epoch
  int retryCount;
  int? lastRetryAt;

  factory PendingAction.fromMap(Map<String, dynamic> map) {
    return PendingAction(
      id: map['id'] as int,
      actionType: OfflineActionType.values[map['action_type'] as int],
      payload: map['payload'] as String,
      createdAt: map['created_at'] as int,
      retryCount: map['retry_count'] as int? ?? 0,
      lastRetryAt: map['last_retry_at'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'action_type': actionType.index,
    'payload': payload,
    'created_at': createdAt,
    'retry_count': retryCount,
    'last_retry_at': lastRetryAt,
  };
}

/// Service pour gérer la queue d'actions hors-ligne
/// Persiste les actions quand le réseau est absent
/// Rejoue automatiquement quand la connexion revient
class OfflineSyncQueue {
  OfflineSyncQueue(this._database);

  final WatchTrackerDatabase _database;

  static const int maxRetries = 3;
  static const int retryDelaySeconds = 5;

  /// Ajoute une action à la queue
  Future<void> enqueueAction({
    required OfflineActionType actionType,
    required String payload,
  }) async {
    final db = await _database.database;
    await db.insert('pending_actions', {
      'action_type': actionType.index,
      'payload': payload,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retry_count': 0,
    });
  }

  /// Récupère toutes les actions en attente
  Future<List<PendingAction>> getPendingActions() async {
    final db = await _database.database;
    final results = await db.query('pending_actions');
    return results.map(PendingAction.fromMap).toList();
  }

  /// Récupère les actions prêtes à être retentées
  /// (basé sur retry_count et last_retry_at)
  Future<List<PendingAction>> getReadyToRetry() async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minRetryTime =
        now - (retryDelaySeconds * 1000); // retry pas trop fréquemment

    final results = await db.rawQuery(
      '''
      SELECT * FROM pending_actions
      WHERE retry_count < ?
      AND (last_retry_at IS NULL OR last_retry_at < ?)
      ORDER BY created_at ASC
    ''',
      [maxRetries, minRetryTime],
    );

    return results.map(PendingAction.fromMap).toList();
  }

  /// Marque une action comme retentée
  Future<void> markRetried(int actionId) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE pending_actions SET retry_count = retry_count + 1, last_retry_at = ? WHERE id = ?',
      [now, actionId],
    );
  }

  /// Supprime une action (succès de la synchro)
  Future<void> removeAction(int actionId) async {
    final db = await _database.database;
    await db.delete('pending_actions', where: 'id = ?', whereArgs: [actionId]);
  }

  /// Supprime une action après max retries
  Future<void> discardAction(int actionId) async {
    final db = await _database.database;
    await db.delete('pending_actions', where: 'id = ?', whereArgs: [actionId]);
  }

  /// Vide complètement la queue (debug/reset)
  Future<void> clearQueue() async {
    final db = await _database.database;
    await db.delete('pending_actions');
  }

  /// Compte le nombre d'actions en attente
  Future<int> getPendingCount() async {
    final db = await _database.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM pending_actions'),
    );
    return result ?? 0;
  }

  /// Récupère les stats de la queue
  Future<SyncQueueStats> getStats() async {
    final db = await _database.database;
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM pending_actions'),
        ) ??
        0;
    final failed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pending_actions WHERE retry_count >= ?',
            [maxRetries],
          ),
        ) ??
        0;

    return SyncQueueStats(
      totalPending: total,
      failedAfterRetries: failed,
      retryable: total - failed,
    );
  }
}

class SyncQueueStats {
  SyncQueueStats({
    required this.totalPending,
    required this.failedAfterRetries,
    required this.retryable,
  });

  final int totalPending;
  final int failedAfterRetries;
  final int retryable;

  bool get isEmpty => totalPending == 0;
  bool get hasFailed => failedAfterRetries > 0;
}
