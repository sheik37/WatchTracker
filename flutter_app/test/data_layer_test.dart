// Tests de caractérisation pour la couche données (MediaRepository et
// WatchTrackerDatabase), regroupés dans un seul fichier pour éviter toute
// interférence entre fichiers de test qui partageraient le même fichier
// SQLite physique ("watchtracker.db") lorsque `flutter test` exécute les
// fichiers de test en parallèle.
//
// Objectif : figer le comportement actuel de secours sur le cache local
// (getMovieDetails / getTvDetailsFast) quand l'appel réseau échoue, le
// comportement du préchargement des épisodes de saison
// (prefetchSeasonEpisodes), ainsi que la création du schéma (`onCreate`) et
// la migration (`onUpgrade`) de WatchTrackerDatabase, avant le refactor de la
// couche données.
import 'dart:convert';

import 'package:flutter_app/src/data/local/watchtracker_database.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_app/src/data/models/media_models.dart';
import 'package:flutter_app/src/data/remote/tmdb_api_client.dart';
import 'package:flutter_app/src/data/repositories/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _resetDatabaseFile() async {
  final dbPath = p.join(await getDatabasesPath(), 'watchtracker.db');
  await databaseFactory.deleteDatabase(dbPath);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(_resetDatabaseFile);
  tearDown(_resetDatabaseFile);

  group('getMovieDetails fallback', () {
    test(
      'falls back to the cached metadata when the network call fails',
      () async {
        final failingClient = MockClient((request) async {
          return http.Response('server error', 500);
        });
        final tmdbApi = TmdbApiClient(apiKey: 'key', client: failingClient);
        final database = WatchTrackerDatabase();
        final repository = MediaRepository(tmdbApi, null, database);

        const cachedDetails = MediaDetails(
          id: 1,
          title: 'Cached movie',
          overview: 'overview',
          posterPath: '/poster.jpg',
          backdropPath: null,
          releaseDate: '2020-01-01',
          voteAverage: 7.5,
          mediaType: MediaType.movie,
        );
        await repository.metadataCache.saveMediaMetadata(
          1,
          MediaType.movie.value,
          cachedDetails,
        );

        final result = await repository.getMovieDetails(1);

        expect(result.title, 'Cached movie');
        expect(result.voteAverage, 7.5);
        expect(repository.lastFetchWasFromCache, isTrue);
      },
    );

    test('returns network data and does not use the cache when the network '
        'call succeeds', () async {
      final successClient = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 2,
            'title': 'Fresh movie',
            'overview': 'fresh overview',
            'poster_path': null,
            'backdrop_path': null,
            'release_date': '2021-05-05',
            'vote_average': 8.1,
            'genres': <dynamic>[],
          }),
          200,
        );
      });
      final tmdbApi = TmdbApiClient(apiKey: 'key', client: successClient);
      final database = WatchTrackerDatabase();
      final repository = MediaRepository(tmdbApi, null, database);

      final result = await repository.getMovieDetails(2);

      expect(result.title, 'Fresh movie');
      expect(repository.lastFetchWasFromCache, isFalse);
    });
  });

  group('getTvDetailsFast fallback', () {
    test(
      'falls back to cached tv metadata and cached seasons when the network '
      'call fails',
      () async {
        final failingClient = MockClient((request) async {
          return http.Response('server error', 500);
        });
        final tmdbApi = TmdbApiClient(apiKey: 'key', client: failingClient);
        final database = WatchTrackerDatabase();
        final repository = MediaRepository(tmdbApi, null, database);

        const cachedDetails = MediaDetails(
          id: 10,
          title: 'Cached show',
          overview: 'overview',
          posterPath: null,
          backdropPath: null,
          releaseDate: '2019-03-03',
          voteAverage: 6.0,
          mediaType: MediaType.tv,
        );
        await repository.metadataCache.saveMediaMetadata(
          10,
          MediaType.tv.value,
          cachedDetails,
        );
        await repository.metadataCache.saveSeasonMetadata(10, const [
          Season(id: 100, name: 'Saison 1', seasonNumber: 1, episodeCount: 8),
          Season(id: 101, name: 'Saison 2', seasonNumber: 2, episodeCount: 6),
        ]);

        final result = await repository.getTvDetailsFast(10);

        expect(result.title, 'Cached show');
        expect(repository.lastFetchWasFromCache, isTrue);
        expect(result.seasons, hasLength(2));
        expect(result.seasons.map((s) => s.seasonNumber), [1, 2]);
      },
    );
  });

  group('prefetchSeasonEpisodes', () {
    test(
      'by default only prefetches the current and next season',
      () async {
        final requestedPaths = <String>[];
        final client = MockClient((request) async {
          requestedPaths.add(request.url.path);
          final match = RegExp(
            r'/season/(\d+)$',
          ).firstMatch(request.url.path);
          final seasonNumber = int.parse(match!.group(1)!);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': seasonNumber * 1000 + 1,
                  'name': 'Episode 1',
                  'overview': '',
                  'episode_number': 1,
                  'season_number': seasonNumber,
                  'still_path': null,
                },
              ],
            }),
            200,
          );
        });
        final tmdbApi = TmdbApiClient(apiKey: 'key', client: client);
        final database = WatchTrackerDatabase();
        final repository = MediaRepository(tmdbApi, null, database);

        const details = MediaDetails(
          id: 20,
          title: 'Show',
          overview: '',
          posterPath: null,
          backdropPath: null,
          releaseDate: null,
          voteAverage: 0,
          mediaType: MediaType.tv,
          seasons: [
            Season(id: 1, name: 'Spéciaux', seasonNumber: 0, episodeCount: 2),
            Season(id: 2, name: 'Saison 1', seasonNumber: 1, episodeCount: 10),
            Season(id: 3, name: 'Saison 2', seasonNumber: 2, episodeCount: 10),
            Season(id: 4, name: 'Saison 3', seasonNumber: 3, episodeCount: 10),
          ],
        );

        await repository.prefetchSeasonEpisodes(details);

        // Only the current (first) season and the next one are prefetched
        // by default.
        expect(
          requestedPaths,
          containsAll(<String>['/3/tv/20/season/1', '/3/tv/20/season/2']),
        );
        expect(
          requestedPaths.any((path) => path.contains('/season/3')),
          isFalse,
        );
        expect(
          requestedPaths.any((path) => path.contains('/season/0')),
          isFalse,
        );

        // Both prefetched seasons end up cached in memory, so a later call
        // does not hit the network again.
        requestedPaths.clear();
        await repository.getSeasonEpisodes(20, 1);
        await repository.getSeasonEpisodes(20, 2);
        expect(requestedPaths, isEmpty);
      },
    );

    test(
      'prefetchAllSeasons: true restores the previous behaviour and '
      'fetches every season',
      () async {
        final requestedPaths = <String>[];
        final client = MockClient((request) async {
          requestedPaths.add(request.url.path);
          final match = RegExp(
            r'/season/(\d+)$',
          ).firstMatch(request.url.path);
          final seasonNumber = int.parse(match!.group(1)!);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': seasonNumber * 1000 + 1,
                  'name': 'Episode 1',
                  'overview': '',
                  'episode_number': 1,
                  'season_number': seasonNumber,
                  'still_path': null,
                },
              ],
            }),
            200,
          );
        });
        final tmdbApi = TmdbApiClient(apiKey: 'key', client: client);
        final database = WatchTrackerDatabase();
        final repository = MediaRepository(tmdbApi, null, database);

        const details = MediaDetails(
          id: 20,
          title: 'Show',
          overview: '',
          posterPath: null,
          backdropPath: null,
          releaseDate: null,
          voteAverage: 0,
          mediaType: MediaType.tv,
          seasons: [
            Season(id: 1, name: 'Spéciaux', seasonNumber: 0, episodeCount: 2),
            Season(id: 2, name: 'Saison 1', seasonNumber: 1, episodeCount: 10),
            Season(id: 3, name: 'Saison 2', seasonNumber: 2, episodeCount: 10),
            Season(id: 4, name: 'Saison 3', seasonNumber: 3, episodeCount: 10),
          ],
        );

        await repository.prefetchSeasonEpisodes(
          details,
          prefetchAllSeasons: true,
        );

        // Season 0 (specials) is never prefetched.
        expect(
          requestedPaths,
          containsAll(<String>[
            '/3/tv/20/season/1',
            '/3/tv/20/season/2',
            '/3/tv/20/season/3',
          ]),
        );
        expect(
          requestedPaths.any((path) => path.contains('/season/0')),
          isFalse,
        );

        // All seasons end up cached in memory, so a later call does not hit
        // the network again.
        requestedPaths.clear();
        await repository.getSeasonEpisodes(20, 1);
        await repository.getSeasonEpisodes(20, 2);
        await repository.getSeasonEpisodes(20, 3);
        expect(requestedPaths, isEmpty);
      },
    );
  });

  group('season episodes in-memory cache (bounded LRU)', () {
    test(
      'evicts the least recently used season once the cache is full',
      () async {
        final requestedPaths = <String>[];
        final client = MockClient((request) async {
          requestedPaths.add(request.url.path);
          final match = RegExp(
            r'/season/(\d+)$',
          ).firstMatch(request.url.path);
          final seasonNumber = int.parse(match!.group(1)!);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'episodes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': seasonNumber * 1000 + 1,
                  'name': 'Episode 1',
                  'overview': '',
                  'episode_number': 1,
                  'season_number': seasonNumber,
                  'still_path': null,
                },
              ],
            }),
            200,
          );
        });
        final tmdbApi = TmdbApiClient(apiKey: 'key', client: client);
        final database = WatchTrackerDatabase();
        final repository = MediaRepository(tmdbApi, null, database);

        // Remplit le cache au-delà de sa capacité (20 entrées) pour forcer
        // une éviction de la saison la plus anciennement utilisée.
        for (var season = 1; season <= 21; season++) {
          await repository.getSeasonEpisodes(20, season);
        }

        requestedPaths.clear();

        // La saison 1 (la moins récemment utilisée) a été évincée : elle
        // doit redéclencher un appel réseau.
        await repository.getSeasonEpisodes(20, 1);
        expect(requestedPaths, contains('/3/tv/20/season/1'));

        requestedPaths.clear();

        // La saison 21 (la plus récemment utilisée) est toujours en cache.
        await repository.getSeasonEpisodes(20, 21);
        expect(requestedPaths, isEmpty);
      },
    );
  });

  group('WatchTrackerDatabase onCreate (fresh install, version 7)', () {
    test('creates every expected table', () async {
      final db = WatchTrackerDatabase();
      final database = await db.database;
      final tables = await _tableNames(database);

      expect(tables, containsAll(<String>[
        'watchlist',
        'episode_progress',
        'episode_watch_events',
        'movie_watch_events',
        'watchlist_tombstones',
        'episode_progress_tombstones',
        'sync_state',
        'media_metadata',
        'season_metadata',
        'episode_metadata',
        'pending_actions',
      ]));
    });

    test('creates watchlist with the updated_at column', () async {
      final db = WatchTrackerDatabase();
      final database = await db.database;
      final columns = await _columnNames(database, 'watchlist');
      expect(columns, contains('updated_at'));
    });

    test('creates episode_progress with the sync_updated_at column', () async {
      final db = WatchTrackerDatabase();
      final database = await db.database;
      final columns = await _columnNames(database, 'episode_progress');
      expect(columns, contains('sync_updated_at'));
    });

    test('creates the expected indexes', () async {
      final db = WatchTrackerDatabase();
      final database = await db.database;
      final rows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final names = rows.map((row) => row['name'] as String).toList();
      expect(
        names,
        containsAll(<String>[
          'idx_media_metadata_cached_at',
          'idx_media_metadata_last_accessed',
          'idx_episode_metadata_cached_at',
          'idx_pending_actions_created',
        ]),
      );
    });
  });

  group('WatchTrackerDatabase onUpgrade (migration from an old version)', () {
    Future<String> createLegacyV1Database() async {
      final dbPath = p.join(await getDatabasesPath(), 'watchtracker.db');
      final legacyDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
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
          },
        ),
      );
      await legacyDb.insert('watchlist', <String, Object?>{
        'id': 42,
        'title': 'Legacy show',
        'poster_path': null,
        'media_type': 'tv',
        'content_category': 'series',
        'content_status': 'watched',
        'total_episodes': 1,
        'added_at': 1000,
      });
      await legacyDb.insert('watchlist', <String, Object?>{
        'id': 99,
        'title': 'Legacy movie',
        'poster_path': null,
        'media_type': 'movie',
        'content_category': 'films',
        'content_status': 'watched',
        'total_episodes': 0,
        'added_at': 1000,
      });
      await legacyDb.insert('episode_progress', <String, Object?>{
        'media_id': 42,
        'season_number': 1,
        'episode_number': 1,
        'is_watched': 1,
        'updated_at': 1500,
      });
      await legacyDb.close();
      return dbPath;
    }

    test('adds every table/column introduced after version 1', () async {
      await createLegacyV1Database();

      final db = WatchTrackerDatabase();
      final database = await db.database;

      final tables = await _tableNames(database);
      expect(tables, containsAll(<String>[
        'watchlist_tombstones',
        'episode_progress_tombstones',
        'sync_state',
        'episode_watch_events',
        'movie_watch_events',
        'media_metadata',
        'season_metadata',
        'episode_metadata',
        'pending_actions',
      ]));

      final watchlistColumns = await _columnNames(database, 'watchlist');
      expect(watchlistColumns, contains('updated_at'));

      final episodeProgressColumns = await _columnNames(
        database,
        'episode_progress',
      );
      expect(episodeProgressColumns, contains('sync_updated_at'));
    });

    test(
      'backfills watch events from the pre-existing watched rows',
      () async {
        await createLegacyV1Database();

        final db = WatchTrackerDatabase();
        final database = await db.database;

        final episodeEvents = await database.query('episode_watch_events');
        expect(episodeEvents, hasLength(1));
        expect(episodeEvents.single['media_id'], 42);
        expect(episodeEvents.single['season_number'], 1);
        expect(episodeEvents.single['episode_number'], 1);

        final movieEvents = await database.query('movie_watch_events');
        expect(movieEvents, hasLength(1));
        expect(movieEvents.single['media_id'], 99);
      },
    );
  });

  group('WatchTrackerDatabase.close', () {
    test('closes the connection and allows a later reopen', () async {
      final db = WatchTrackerDatabase();
      final database = await db.database;
      expect(database.isOpen, isTrue);

      await db.close();
      expect(database.isOpen, isFalse);

      // A subsequent access transparently reopens a fresh connection.
      final reopened = await db.database;
      expect(reopened.isOpen, isTrue);
    });

    test('is a no-op when the database was never opened', () async {
      final db = WatchTrackerDatabase();
      await db.close();
    });
  });
}

Future<List<String>> _tableNames(dynamic db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_metadata'",
  );
  return rows.map<String>((row) => row['name'] as String).toList();
}

Future<List<String>> _columnNames(dynamic db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map<String>((row) => row['name'] as String).toList();
}
