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

import 'package:flutter/foundation.dart';
import 'package:flutter_app/src/data/local/watchtracker_database.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_app/src/data/models/media_models.dart';
import 'package:flutter_app/src/data/remote/tmdb_api_client.dart';
import 'package:flutter_app/src/data/remote/tvdb_api_client.dart';
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

class _TvdbFixture extends TvdbApiClient {
  _TvdbFixture(this.counts) : super(apiKey: 'key');

  final Map<int, int> counts;
  final calls = <String>[];
  bool offline = false;

  @override
  Future<List<Season>> getSeasonsWithCounts(int tvdbId) async {
    calls.add('seasons');
    if (offline) throw StateError('TVDB offline');
    return [
      for (final entry in counts.entries)
        Season(
          id: entry.key + 900,
          name: 'TVDB ${entry.key}',
          seasonNumber: entry.key,
          episodeCount: entry.value,
        ),
    ];
  }

  @override
  Future<List<Episode>> getSeasonEpisodes(int tvdbId, int seasonNumber) async {
    calls.add('episodes/$seasonNumber');
    if (offline) throw StateError('TVDB offline');
    return [
      for (var n = 1; n <= (counts[seasonNumber] ?? 0); n++)
        Episode(
          id: 90000 + seasonNumber * 100 + n,
          name: 'TVDB name',
          overview: 'TVDB overview',
          episodeNumber: n,
          seasonNumber: seasonNumber,
          stillPath: 'TVDB image',
          airDate: '1900-01-01',
          runtime: 99,
        ),
    ];
  }
}

class _ProviderFixture {
  _ProviderFixture({
    this.anime = true,
    this.tmdbCounts = const {0: 2, 1: 3, 2: 4, 3: 5},
    Map<int, int> tvdbCounts = const {0: 2, 1: 2, 2: 3, 3: 7},
  }) : tvdb = _TvdbFixture(tvdbCounts) {
    tmdb = TmdbApiClient(
      apiKey: 'key',
      client: MockClient((request) async {
        final path = request.url.path;
        paths.add(path);
        if (offline) return http.Response('offline', 503);
        if (path.endsWith('/external_ids')) {
          return http.Response(
            jsonEncode({'tvdb_id': noMapping ? null : 900}),
            200,
          );
        }
        final match = RegExp(r'/season/(\d+)$').firstMatch(path);
        if (match != null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final season = int.parse(match.group(1)!);
          final offset = tmdbCounts.entries
              .where((e) => e.key > 0 && e.key < season)
              .fold<int>(0, (sum, e) => sum + e.value);
          return http.Response(
            jsonEncode({
              'episodes': [
                for (var n = 1; n <= (tmdbCounts[season] ?? 0); n++)
                  if (!missingEpisodes.contains('$season/$n'))
                    {
                      'id': season * 100 + n,
                      'name': season == 0 ? 'Special $n' : 'TMDB ${offset + n}',
                      'overview': 'TMDB overview $season/$n',
                      'episode_number': n,
                      'season_number': season,
                      'still_path': '/tmdb-$season-$n.jpg',
                      'air_date': '2020-01-0$n',
                      'runtime': 20 + n,
                    },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 70,
            'name': 'Show',
            'overview': 'TMDB show',
            'genres': [
              {'name': anime ? 'Animation' : 'Drama'},
            ],
            'seasons': [
              for (final entry in tmdbCounts.entries)
                {
                  'id': entry.key + 100,
                  'name': 'TMDB ${entry.key}',
                  'season_number': entry.key,
                  'episode_count': entry.value,
                },
            ],
          }),
          200,
        );
      }),
    );
  }

  final bool anime;
  final Map<int, int> tmdbCounts;
  final _TvdbFixture tvdb;
  late final TmdbApiClient tmdb;
  final paths = <String>[];
  final missingEpisodes = <String>{};
  bool offline = false;
  bool noMapping = false;

  MediaRepository repository(WatchTrackerDatabase db) =>
      MediaRepository(tmdb, tvdb, db);

  List<String> get seasonPaths =>
      paths.where((p) => p.contains('/season/')).toList();
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

  group('deterministic episode providers', () {
    test(
      'series use only TMDB even when episodes are requested first',
      () async {
        final fixture = _ProviderFixture(anime: false);
        final repository = fixture.repository(WatchTrackerDatabase());
        final episodes = await repository.getSeasonEpisodes(70, 2);
        final details = await repository.getTvDetails(70);
        expect(
          details.seasons.map((s) => s.name),
          everyElement(startsWith('TMDB')),
        );
        expect(episodes.first.name, 'TMDB 4');
        expect(episodes.first.id, 201);
        expect(fixture.tvdb.calls, isEmpty);
        expect(fixture.paths.any((p) => p.endsWith('/external_ids')), isFalse);
      },
    );

    test(
      'anime use TVDB slots and all TMDB fields across season boundaries',
      () async {
        final fixture = _ProviderFixture();
        final repository = fixture.repository(WatchTrackerDatabase());
        final episodes = await repository.getSeasonEpisodes(70, 2);
        expect(episodes.map((e) => e.name), ['TMDB 3', 'TMDB 4', 'TMDB 5']);
        expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
        expect(episodes.map((e) => e.seasonNumber), everyElement(2));
        expect(episodes.first.id, 90201);
        expect(episodes.first.overview, 'TMDB overview 1/3');
        expect(
          episodes.first.stillPath,
          'https://image.tmdb.org/t/p/w300/tmdb-1-3.jpg',
        );
        expect(episodes.first.airDate, '2020-01-03');
        expect(episodes.first.runtime, 23);
        expect(fixture.seasonPaths, ['/3/tv/70/season/1', '/3/tv/70/season/2']);
        final details = await repository.getTvDetails(70);
        expect(details.seasons.map((s) => s.episodeCount), [2, 2, 3, 7]);
        expect(
          (await repository.getSeasonEpisodes(70, 2)).first.name,
          'TMDB 3',
        );
        expect(fixture.seasonPaths, hasLength(2));
      },
    );

    test('TVDB S2E1 can be TMDB S1E25 by global order', () async {
      final fixture = _ProviderFixture(
        tmdbCounts: {0: 7, 1: 25, 2: 2, 3: 5},
        tvdbCounts: {0: 10, 1: 24, 2: 3},
      );
      final repository = fixture.repository(WatchTrackerDatabase());
      final episodes = await repository.getSeasonEpisodes(70, 2);
      expect(episodes.map((e) => e.name), ['TMDB 25', 'TMDB 26', 'TMDB 27']);
      expect(episodes.first.episodeNumber, 1);
      expect(fixture.seasonPaths, ['/3/tv/70/season/1', '/3/tv/70/season/2']);
    });

    test('later TVDB seasons do not download preceding TMDB seasons', () async {
      final fixture = _ProviderFixture();
      final episodes = await fixture
          .repository(WatchTrackerDatabase())
          .getSeasonEpisodes(70, 3);
      expect(episodes.map((e) => e.name), [
        'TMDB 6',
        'TMDB 7',
        'TMDB 8',
        'TMDB 9',
        'TMDB 10',
        'TMDB 11',
        'TMDB 12',
      ]);
      expect(fixture.seasonPaths, ['/3/tv/70/season/2', '/3/tv/70/season/3']);
    });

    test('specials stay isolated and never offset regular episodes', () async {
      final fixture = _ProviderFixture();
      final repository = fixture.repository(WatchTrackerDatabase());
      final specials = await repository.getSeasonEpisodes(70, 0);
      expect(specials.map((e) => e.name), ['Special 1', 'Special 2']);
      expect(specials.map((e) => e.seasonNumber), everyElement(0));
      expect(fixture.seasonPaths, ['/3/tv/70/season/0']);
      final regular = await repository.getSeasonEpisodes(70, 2);
      expect(regular.first.name, 'TMDB 3');
    });

    test(
      'missing TMDB episode keeps its TVDB slot without shifting others',
      () async {
        final fixture = _ProviderFixture()..missingEpisodes.add('2/1');
        final episodes = await fixture
            .repository(WatchTrackerDatabase())
            .getSeasonEpisodes(70, 2);
        expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
        expect(episodes[0].name, 'TMDB 3');
        expect(episodes[1].name, contains('informations TMDB indisponibles'));
        expect(episodes[1].id, 90202);
        expect(episodes[1].overview, isEmpty);
        expect(episodes[1].stillPath, isNull);
        expect(episodes[1].airDate, isNull);
        expect(episodes[1].runtime, isNull);
        expect(episodes[2].name, 'TMDB 5');
      },
    );

    test('missing TMDB season counts never borrow another episode', () async {
      final fixture = _ProviderFixture(tmdbCounts: {});
      final episodes = await fixture
          .repository(WatchTrackerDatabase())
          .getSeasonEpisodes(70, 2);
      expect(episodes, hasLength(3));
      expect(
        episodes.map((e) => e.name),
        everyElement(contains('informations TMDB indisponibles')),
      );
      expect(fixture.seasonPaths, isEmpty);
    });

    test(
      'offline restart keeps provider split and TVDB progression identity',
      () async {
        final fixture = _ProviderFixture();
        final db = WatchTrackerDatabase();
        final online = fixture.repository(db);
        final original = await online.getTvDetails(70);
        await online.addToWatchlist(
          original.toMedia(),
          WatchCategory.anime,
          WatchStatus.inProgress,
          12,
        );
        await online.updateEpisodeProgress(
          mediaId: 70,
          seasonNumber: 2,
          episodeNumber: 1,
          isWatched: true,
        );
        await online.getSeasonEpisodes(70, 2);
        fixture.offline = true;
        fixture.tvdb.offline = true;
        final offline = fixture.repository(db);
        final details = await offline.getTvDetails(70);
        final episodes = await offline.getSeasonEpisodes(70, 2);
        expect(details.seasons.map((s) => s.episodeCount), [2, 2, 3, 7]);
        expect(episodes.map((e) => e.name), ['TMDB 3', 'TMDB 4', 'TMDB 5']);
        expect(episodes.first.id, 90201);
        expect(offline.lastFetchWasFromCache, isTrue);
        expect(await offline.getWatchlist(WatchCategory.anime), hasLength(1));
        final progress = await offline.getEpisodeProgress(70);
        expect(progress.single.seasonNumber, 2);
        expect(progress.single.episodeNumber, 1);
        expect(progress.single.isWatched, isTrue);
      },
    );

    test('missing TVDB association explicitly falls back to TMDB', () async {
      final fixture = _ProviderFixture()..noMapping = true;
      final repository = fixture.repository(WatchTrackerDatabase());
      final diagnostics = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) diagnostics.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);
      final details = await repository.getTvDetails(70);
      final episodes = await repository.getSeasonEpisodes(70, 2);
      expect(details.seasons.map((s) => s.episodeCount), [2, 3, 4, 5]);
      expect(episodes.first.name, 'TMDB 4');
      expect(episodes.first.id, 201);
      expect(fixture.tvdb.calls, isEmpty);
      expect(diagnostics, contains(contains('Association TMDB/TVDB absente')));
      fixture.noMapping = false;
      final recovered = await repository.getSeasonEpisodes(70, 2);
      expect(recovered.first.name, 'TMDB 3');
      expect(recovered.first.id, 90201);
    });

    test('TVDB outage without its cached layout falls back to TMDB', () async {
      final fixture = _ProviderFixture();
      fixture.tvdb.offline = true;
      final repository = fixture.repository(WatchTrackerDatabase());
      final details = await repository.getTvDetails(70);
      expect(details.seasons.map((s) => s.episodeCount), [2, 3, 4, 5]);
      expect((await repository.getSeasonEpisodes(70, 2)).first.name, 'TMDB 4');
    });

    test(
      'offline anime can use cached layout with no configured TVDB client',
      () async {
        final fixture = _ProviderFixture();
        final db = WatchTrackerDatabase();
        final online = fixture.repository(db);
        await online.getTvDetails(70);
        await online.getSeasonEpisodes(70, 2);
        fixture.offline = true;
        final offline = MediaRepository(fixture.tmdb, null, db);
        expect((await offline.getTvDetails(70)).seasons[2].episodeCount, 3);
        final episodes = await offline.getSeasonEpisodes(70, 2);
        expect(episodes.map((e) => e.name), ['TMDB 3', 'TMDB 4', 'TMDB 5']);
        expect(episodes.first.id, 90201);
      },
    );

    test(
      'provider cache clearing includes snapshots but not progression',
      () async {
        final fixture = _ProviderFixture();
        final db = WatchTrackerDatabase();
        final repository = fixture.repository(db);
        await repository.getTvDetails(70);
        await repository.getSeasonEpisodes(70, 2);
        await repository.updateEpisodeProgress(
          mediaId: 70,
          seasonNumber: 2,
          episodeNumber: 1,
          isWatched: true,
        );
        expect(await repository.getCacheMaxSizeBytes(), greaterThan(0));
        expect(
          await repository.metadataCache.getCacheSizeForUI(),
          greaterThan(0),
        );
        await repository.clearMetadataCache();
        expect(await repository.metadataCache.getCacheSizeForUI(), 0);
        expect(await repository.getEpisodeProgress(70), hasLength(1));
        fixture.offline = true;
        final offline = fixture.repository(db);
        await expectLater(offline.getSeasonEpisodes(70, 2), throwsA(anything));
      },
    );

    test(
      'overlapping anime requests share necessary TMDB season loads',
      () async {
        final fixture = _ProviderFixture();
        final repository = fixture.repository(WatchTrackerDatabase());
        await repository.getTvDetails(70);
        final results = await Future.wait([
          repository.getSeasonEpisodes(70, 1),
          repository.getSeasonEpisodes(70, 2),
          repository.getSeasonEpisodes(70, 2),
        ]);
        expect(results[1].map((e) => e.name), results[2].map((e) => e.name));
        expect(
          fixture.seasonPaths.where((p) => p.endsWith('/1')),
          hasLength(1),
        );
        expect(
          fixture.seasonPaths.where((p) => p.endsWith('/2')),
          hasLength(1),
        );
        expect(fixture.seasonPaths, hasLength(2));
      },
    );

    test(
      'unversioned TVDB caches cannot masquerade as TMDB metadata',
      () async {
        final fixture = _ProviderFixture(anime: false);
        final db = WatchTrackerDatabase();
        final repository = fixture.repository(db);
        await repository.getTvDetailsFast(70);
        await repository.metadataCache.saveSeasonMetadata(70, const [
          Season(id: 999, name: 'Old TVDB', seasonNumber: 99, episodeCount: 99),
        ]);
        await repository.metadataCache.saveEpisodeMetadata(70, 2, const [
          Episode(
            id: 999,
            name: 'Old TVDB',
            overview: 'wrong',
            episodeNumber: 1,
            seasonNumber: 2,
            stillPath: 'wrong',
          ),
        ]);
        fixture.offline = true;
        final offline = fixture.repository(db);
        final details = await offline.getTvDetailsFast(70);
        expect(details.seasons.map((s) => s.seasonNumber), [0, 1, 2, 3]);
        await expectLater(offline.getSeasonEpisodes(70, 2), throwsA(anything));
        final connection = await db.database;
        await connection.delete('provider_metadata_v2');
        expect((await offline.getTvDetailsFast(70)).seasons, isEmpty);
        expect(await offline.getWatchlist(WatchCategory.series), isEmpty);
      },
    );
  });

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
    test('falls back to cached tv metadata and cached seasons when the network '
        'call fails', () async {
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
      await repository.metadataCache.saveProviderSnapshot(
        10,
        'tmdb-seasons',
        -1,
        [
          {
            'id': 100,
            'name': 'Saison 1',
            'season_number': 1,
            'episode_count': 8,
          },
          {
            'id': 101,
            'name': 'Saison 2',
            'season_number': 2,
            'episode_count': 6,
          },
        ],
      );

      final result = await repository.getTvDetailsFast(10);

      expect(result.title, 'Cached show');
      expect(repository.lastFetchWasFromCache, isTrue);
      expect(result.seasons, hasLength(2));
      expect(result.seasons.map((s) => s.seasonNumber), [1, 2]);
    });
  });

  group('prefetchSeasonEpisodes', () {
    test('by default only prefetches the current and next season', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        final match = RegExp(r'/season/(\d+)$').firstMatch(request.url.path);
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
      expect(requestedPaths.any((path) => path.contains('/season/3')), isFalse);
      expect(requestedPaths.any((path) => path.contains('/season/0')), isFalse);

      // Both prefetched seasons end up cached in memory, so a later call
      // does not hit the network again.
      requestedPaths.clear();
      await repository.getSeasonEpisodes(20, 1);
      await repository.getSeasonEpisodes(20, 2);
      expect(requestedPaths, isEmpty);
    });

    test('prefetchAllSeasons: true restores the previous behaviour and '
        'fetches every season', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        final match = RegExp(r'/season/(\d+)$').firstMatch(request.url.path);
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
      expect(requestedPaths.any((path) => path.contains('/season/0')), isFalse);

      // All seasons end up cached in memory, so a later call does not hit
      // the network again.
      requestedPaths.clear();
      await repository.getSeasonEpisodes(20, 1);
      await repository.getSeasonEpisodes(20, 2);
      await repository.getSeasonEpisodes(20, 3);
      expect(requestedPaths, isEmpty);
    });
  });

  group('season episodes in-memory cache (bounded LRU)', () {
    test(
      'evicts the least recently used season once the cache is full',
      () async {
        final requestedPaths = <String>[];
        final client = MockClient((request) async {
          requestedPaths.add(request.url.path);
          final match = RegExp(r'/season/(\d+)$').firstMatch(request.url.path);
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

      expect(
        tables,
        containsAll(<String>[
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
        ]),
      );
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
      expect(
        tables,
        containsAll(<String>[
          'watchlist_tombstones',
          'episode_progress_tombstones',
          'sync_state',
          'episode_watch_events',
          'movie_watch_events',
          'media_metadata',
          'season_metadata',
          'episode_metadata',
          'pending_actions',
        ]),
      );

      final watchlistColumns = await _columnNames(database, 'watchlist');
      expect(watchlistColumns, contains('updated_at'));

      final episodeProgressColumns = await _columnNames(
        database,
        'episode_progress',
      );
      expect(episodeProgressColumns, contains('sync_updated_at'));
    });

    test('backfills watch events from the pre-existing watched rows', () async {
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
    });
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
