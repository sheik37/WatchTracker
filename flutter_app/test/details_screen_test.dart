import 'package:flutter/material.dart';
import 'package:flutter_app/src/data/local/watchtracker_database.dart';
import 'package:flutter_app/src/data/models/backend_models.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_app/src/data/models/media_models.dart';
import 'package:flutter_app/src/data/remote/tmdb_api_client.dart';
import 'package:flutter_app/src/data/remote/tvdb_api_client.dart';
import 'package:flutter_app/src/data/repositories/media_repository.dart';
import 'package:flutter_app/src/presentation/screens/details_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final episodes = [
    Episode(
      id: 1,
      name: 'Le premier pas',
      overview: 'Un épisode fondateur.',
      episodeNumber: 1,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-01',
      runtime: 42,
    ),
    Episode(
      id: 2,
      name: 'Le second souffle',
      overview: 'Les choses se compliquent.',
      episodeNumber: 2,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-08',
      runtime: 45,
    ),
    Episode(
      id: 3,
      name: 'Épisode futur',
      overview: 'Pas encore diffusé.',
      episodeNumber: 3,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2099-01-01',
      runtime: null,
    ),
  ];

  final crossSeasonEpisodes = [
    Episode(
      id: 10,
      name: 'Fin de saison 1',
      overview: 'Dernier épisode S1.',
      episodeNumber: 3,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-01',
      runtime: 42,
    ),
    Episode(
      id: 11,
      name: 'Début de saison 2',
      overview: 'Premier épisode S2.',
      episodeNumber: 1,
      seasonNumber: 2,
      stillPath: null,
      airDate: '2025-02-01',
      runtime: 44,
    ),
  ];

  const defaultOffsets = {1: 0};
  const defaultSeriesTitle = 'Ma Série';
  const emptyWatchedAt = <String, int>{};
  const titleMedia = Media(
    id: 100,
    title: 'Série swipe',
    posterPath: null,
    backdropPath: null,
    overview: 'Résumé de test',
    releaseDate: '2024-01-01',
    voteAverage: 8,
    mediaType: MediaType.tv,
  );
  const titleDetails = MediaDetails(
    id: 100,
    title: 'Série swipe',
    overview: 'Résumé de test',
    posterPath: null,
    backdropPath: null,
    releaseDate: '2024-01-01',
    voteAverage: 8,
    mediaType: MediaType.tv,
    tvStatus: TvStatus.returningSeries,
    seasons: [
      Season(id: 200, name: 'Saison 1', seasonNumber: 1, episodeCount: 2),
    ],
  );
  final titleSeasonEpisodes = [
    Episode(
      id: 201,
      name: 'Pilote',
      overview: 'Premier épisode',
      episodeNumber: 1,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2024-01-01',
      runtime: 42,
    ),
    Episode(
      id: 202,
      name: 'Suite',
      overview: 'Deuxième épisode',
      episodeNumber: 2,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2024-01-08',
      runtime: 43,
    ),
  ];
  const movieMedia = Media(
    id: 301,
    title: 'Film test',
    posterPath: null,
    backdropPath: null,
    overview: 'Résumé film test',
    releaseDate: '2024-02-01',
    voteAverage: 7.5,
    mediaType: MediaType.movie,
  );
  const movieDetails = MediaDetails(
    id: 301,
    title: 'Film test',
    overview: 'Résumé film test',
    posterPath: null,
    backdropPath: null,
    releaseDate: '2024-02-01',
    voteAverage: 7.5,
    mediaType: MediaType.movie,
    seasons: [],
  );

  Widget buildPage({
    int mediaId = 100,
    MediaRepository? repository,
    int initialIndex = 0,
    Set<String> watchedEpisodes = const {},
    Map<String, int> episodeWatchedAt = emptyWatchedAt,
    Map<String, int> episodeViewCounts = const {},
    bool Function(Episode)? isReleasedCheck,
    Future<void> Function(Episode, bool)? onToggleWatched,
    List<Episode>? episodeList,
    Map<int, int>? seasonOffsets,
    String? seriesTitle,
    ({
      Set<String> watched,
      Map<String, int> watchedAt,
      Map<String, int> viewCounts,
    })
    Function()?
    getProgress,
  }) {
    final repo =
        repository ??
        _FakeMediaRepository(
          details: titleDetails,
          tracked: true,
          status: WatchStatus.watched,
          progress: const [],
          episodeViewCounts: episodeViewCounts,
          seasonEpisodes: {},
        );
    return MaterialApp(
      home: EpisodeDetailPage(
        episodes: episodeList ?? episodes,
        initialIndex: initialIndex,
        mediaId: mediaId,
        repository: repo,
        watchedEpisodes: watchedEpisodes,
        episodeWatchedAt: episodeWatchedAt,
        episodeViewCounts: episodeViewCounts,
        seasonOffsets: seasonOffsets ?? defaultOffsets,
        seriesTitle: seriesTitle ?? defaultSeriesTitle,
        isReleasedCheck: isReleasedCheck ?? (ep) => ep.airDate != '2099-01-01',
        onToggleWatched: onToggleWatched ?? (_, _) async {},
        getProgress:
            getProgress ??
            () => (
              watched: watchedEpisodes,
              watchedAt: episodeWatchedAt,
              viewCounts: episodeViewCounts,
            ),
      ),
    );
  }

  Widget buildTitlePage({
    Set<String> watchedEpisodes = const {'1_1'},
    List<Episode>? seasonEpisodes,
    Map<String, int> episodeViewCounts = const {},
  }) {
    return MaterialApp(
      home: DetailsScreen(
        repository: _FakeMediaRepository(
          details: titleDetails,
          tracked: true,
          status: WatchStatus.inProgress,
          progress: watchedEpisodes
              .map(
                (key) => RemoteEpisodeProgress(
                  mediaId: titleDetails.id,
                  seasonNumber: int.parse(key.split('_')[0]),
                  episodeNumber: int.parse(key.split('_')[1]),
                  isWatched: true,
                  updatedAtMillis: 0,
                ),
              )
              .toList(),
          episodeViewCounts: episodeViewCounts,
          seasonEpisodes: {1: seasonEpisodes ?? titleSeasonEpisodes},
        ),
        media: titleMedia,
      ),
    );
  }

  Widget buildMovieTitlePage({
    WatchStatus status = WatchStatus.notWatched,
    int movieViewCount = 0,
    int? firstWatchedAtMillis,
  }) {
    return MaterialApp(
      home: DetailsScreen(
        repository: _FakeMediaRepository(
          details: movieDetails,
          tracked: true,
          status: status,
          progress: const [],
          episodeViewCounts: const {},
          seasonEpisodes: const {},
          movieViewCount: movieViewCount,
          movieFirstWatchedAt: firstWatchedAtMillis,
        ),
        media: movieMedia,
      ),
    );
  }

  testWidgets('displays episode number below banner', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    // AppBar has no title — episode ref is shown below the banner in the body
    expect(find.textContaining('S01 | E01'), findsOneWidget);
  });

  testWidgets('shows watch date chip when episode is watched', (tester) async {
    // 2025-03-15 00:00:00 UTC = 1741996800000 ms
    final millis = DateTime(2025, 3, 15).millisecondsSinceEpoch;
    await tester.pumpWidget(
      buildPage(watchedEpisodes: {'1_1'}, episodeWatchedAt: {'1_1': millis}),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Vu le'), findsOneWidget);
    expect(find.textContaining('15/03/2025'), findsOneWidget);
  });

  testWidgets('shows Vu chip without date when watched but no timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(watchedEpisodes: {'1_1'}));
    await tester.pumpAndSettle();
    expect(find.text('Vu'), findsOneWidget);
    expect(find.textContaining('Vu le'), findsNothing);
  });

  testWidgets('no watch date chip when episode is not watched', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.textContaining('Vu le'), findsNothing);
    expect(find.text('Vu'), findsNothing);
  });

  testWidgets('displays series title on the page', (tester) async {
    await tester.pumpWidget(buildPage(seriesTitle: 'Breaking Bad'));
    await tester.pumpAndSettle();
    expect(find.text('Breaking Bad'), findsOneWidget);
  });

  testWidgets('displays global episode number', (tester) async {
    await tester.pumpWidget(buildPage(seasonOffsets: {1: 5}));
    await tester.pumpAndSettle();
    // global = offset(5) + episodeNumber(1) = 6 → "Ép. 06"
    expect(find.textContaining('Ép. 06'), findsOneWidget);
  });

  testWidgets(
    'tap sur le numéro ouvre la bottom sheet avec les épisodes de la saison',
    (tester) async {
      await tester.pumpWidget(buildPage(initialIndex: 0));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('S01 | E01'));
      await tester.pumpAndSettle();

      expect(find.text('E01'), findsOneWidget);
      expect(find.text('E02'), findsOneWidget);
      expect(find.text('E03'), findsOneWidget);
    },
  );

  testWidgets('bottom sheet permet de naviguer entre saisons', (tester) async {
    await tester.pumpWidget(
      buildPage(
        episodeList: crossSeasonEpisodes,
        initialIndex: 0,
        seasonOffsets: {1: 0, 2: 1},
      ),
    );
    await tester.pumpAndSettle();

    // Ouvre la bottom sheet sur S1
    await tester.tap(find.textContaining('S01 | E03'));
    await tester.pumpAndSettle();

    expect(find.text('Saison 1'), findsOneWidget);
    expect(find.text('E03'), findsOneWidget);

    // Avance à la saison 2
    await tester.tap(find.byIcon(Icons.arrow_forward_ios_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('Saison 2'), findsOneWidget);
    expect(find.text('E01'), findsOneWidget);
  });

  testWidgets('navigates to next episode via arrow button', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E01'), findsOneWidget);

    await tester.tap(find.byTooltip('Épisode suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E02'), findsOneWidget);
  });

  testWidgets('navigates to previous episode via arrow button', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E02'), findsOneWidget);

    await tester.tap(find.byTooltip('Épisode précédent'));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E01'), findsOneWidget);
  });

  testWidgets('cross-season navigation: next from last ep of S1 shows S2 E1', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        episodeList: crossSeasonEpisodes,
        initialIndex: 0,
        seasonOffsets: {1: 0, 2: 3},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E03'), findsOneWidget);

    await tester.tap(find.byTooltip('Épisode suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('S02 | E01'), findsOneWidget);
  });

  testWidgets('flèche précédent désactivée sur le premier épisode', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(initialIndex: 0));
    await tester.pumpAndSettle();

    final prevBtn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_back_ios_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(prevBtn.onPressed, isNull);
  });

  testWidgets('flèche suivant désactivée sur le dernier épisode', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(initialIndex: 2));
    await tester.pumpAndSettle();

    final nextBtn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_forward_ios_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(nextBtn.onPressed, isNull);
  });

  testWidgets('bouton affiche Marquer comme vu quand épisode non vu', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.text('Marquer comme vu'), findsOneWidget);
    expect(find.text('Marquer non vu'), findsNothing);
  });

  testWidgets('bouton affiche Marquer non vu quand épisode vu', (tester) async {
    await tester.pumpWidget(buildPage(watchedEpisodes: {'1_1'}));
    await tester.pump();

    expect(find.text('Marquer non vu'), findsOneWidget);
    expect(find.text('Marquer comme vu'), findsNothing);
  });

  testWidgets('sur épisode déjà vu, choisir Revoir garde la coche active', (
    tester,
  ) async {
    bool? toggledValue;

    await tester.pumpWidget(
      buildPage(
        watchedEpisodes: {'1_1'},
        onToggleWatched: (_, value) async {
          toggledValue = value;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marquer non vu'));
    await tester.pumpAndSettle();
    expect(find.text('Épisode déjà vu'), findsOneWidget);

    await tester.tap(find.text('Revoir (+1 vue)'));
    await tester.pumpAndSettle();

    expect(toggledValue, isTrue);
  });

  testWidgets('sur épisode déjà vu, choisir Marquer non vu décoche', (
    tester,
  ) async {
    bool? toggledValue;

    await tester.pumpWidget(
      buildPage(
        watchedEpisodes: {'1_1'},
        onToggleWatched: (_, value) async {
          toggledValue = value;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marquer non vu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marquer non vu').last);
    await tester.pumpAndSettle();

    expect(toggledValue, isFalse);
  });

  testWidgets('le bouton appelle le callback au tap', (tester) async {
    Episode? toggledEpisode;
    bool? toggledValue;

    await tester.pumpWidget(
      buildPage(
        onToggleWatched: (ep, value) async {
          toggledEpisode = ep;
          toggledValue = value;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Marquer comme vu'));
    await tester.pump();

    expect(toggledValue, isTrue);
    expect(toggledEpisode?.episodeNumber, 1);
  });

  testWidgets('le bouton est désactivé pour les épisodes non diffusés', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(initialIndex: 2));
    await tester.pump();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('supports back navigation', (tester) async {
    final fakeRepo = _FakeMediaRepository(
      details: titleDetails,
      tracked: true,
      status: WatchStatus.watched,
      progress: const [],
      episodeViewCounts: const {},
      seasonEpisodes: {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EpisodeDetailPage(
                    episodes: episodes,
                    initialIndex: 0,
                    mediaId: 100,
                    repository: fakeRepo,
                    watchedEpisodes: const {},
                    episodeWatchedAt: const {},
                    episodeViewCounts: const {},
                    seasonOffsets: defaultOffsets,
                    seriesTitle: defaultSeriesTitle,
                    isReleasedCheck: (_) => true,
                    onToggleWatched: (_, _) async {},
                    getProgress: () => (
                      watched: const {},
                      watchedAt: const {},
                      viewCounts: const {},
                    ),
                  ),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeDetailPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets(
    'watch date appears on previous episode after getProgress is called',
    (tester) async {
      final millis = DateTime(2025, 6, 10).millisecondsSinceEpoch;
      // Mutable state simulating the parent
      var watched = <String>{};
      var watchedAt = <String, int>{};
      var viewCounts = <String, int>{};

      await tester.pumpWidget(
        buildPage(
          initialIndex: 1,
          watchedEpisodes: watched,
          episodeWatchedAt: watchedAt,
          episodeViewCounts: viewCounts,
          getProgress: () =>
              (watched: watched, watchedAt: watchedAt, viewCounts: viewCounts),
          onToggleWatched: (ep, target) async {
            // Simulate parent marking ep2 AND ep1 (batch)
            watched = {'1_1', '1_2'};
            watchedAt = {'1_1': millis, '1_2': millis};
            viewCounts = {'1_1': 1, '1_2': 1};
          },
        ),
      );
      await tester.pumpAndSettle();

      // No watch date chip yet
      expect(find.textContaining('Vu le'), findsNothing);

      // Trigger toggle on ep2 (current)
      await tester.tap(find.text('Marquer comme vu'));
      await tester.pumpAndSettle();

      // Ep2 is current — should show the date
      expect(find.textContaining('Vu le'), findsOneWidget);
      expect(find.textContaining('10/06/2025'), findsOneWidget);

      // Navigate to previous episode (ep1, marked in the same batch)
      await tester.tap(find.byTooltip('Épisode précédent'));
      await tester.pumpAndSettle();

      // Ep1 should also show the same date without leaving the page
      expect(find.textContaining('Vu le'), findsOneWidget);
      expect(find.textContaining('10/06/2025'), findsOneWidget);
    },
  );

  testWidgets('la revue conserve la date du premier visionnage', (
    tester,
  ) async {
    final firstWatchMillis = DateTime(2024, 2, 10).millisecondsSinceEpoch;
    var watched = <String>{'1_1'};
    var watchedAt = <String, int>{'1_1': firstWatchMillis};
    var viewCounts = <String, int>{'1_1': 1};

    await tester.pumpWidget(
      buildPage(
        watchedEpisodes: watched,
        episodeWatchedAt: watchedAt,
        episodeViewCounts: viewCounts,
        getProgress: () =>
            (watched: watched, watchedAt: watchedAt, viewCounts: viewCounts),
        onToggleWatched: (_, target) async {
          if (target) {
            watched = {'1_1'};
            watchedAt = {'1_1': firstWatchMillis};
            viewCounts = {'1_1': 2};
          }
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('10/02/2024'), findsOneWidget);

    await tester.tap(find.text('Marquer non vu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoir (+1 vue)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10/02/2024'), findsOneWidget);
  });

  testWidgets(
    'affiche une étiquette xN vues sur la page épisode pour une revue',
    (tester) async {
      await tester.pumpWidget(
        buildPage(
          watchedEpisodes: const {'1_1'},
          episodeViewCounts: const {'1_1': 3},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('x3 vues'), findsOneWidget);
    },
  );

  testWidgets('n’affiche pas l’étiquette xN vues pour un premier visionnage', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        watchedEpisodes: const {'1_1'},
        episodeViewCounts: const {'1_1': 1},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('vues'), findsNothing);
  });

  testWidgets('swipe horizontal change entre À propos et Épisodes', (
    tester,
  ) async {
    await tester.pumpWidget(buildTitlePage());
    await tester.pumpAndSettle();

    expect(find.text('Informations sur la série'), findsOneWidget);
    expect(find.text('Saison 1'), findsNothing);

    await tester.drag(
      find.text('Informations sur la série'),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saison 1'), findsOneWidget);
    expect(find.text('Informations sur la série'), findsNothing);

    await tester.drag(find.text('Saison 1'), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Informations sur la série'), findsOneWidget);
  });

  testWidgets('changement d’onglet sans superposition temporaire des vues', (
    tester,
  ) async {
    await tester.pumpWidget(buildTitlePage());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tv-tab-about')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-tab-episodes')), findsNothing);

    await tester.tap(find.text('Épisodes'));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const ValueKey('tv-tab-about')), findsNothing);
    expect(find.byKey(const ValueKey('tv-tab-episodes')), findsOneWidget);
  });

  testWidgets('bouton prochain épisode se compacte après scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 700);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTitlePage());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('next-episode-fab')), findsOneWidget);
    expect(
      tester
              .getSize(find.byKey(const ValueKey('next-episode-fab-container')))
              .width >
          150,
      isTrue,
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      1800,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('next-episode-fab')), findsOneWidget);
    expect(
      tester
              .getSize(find.byKey(const ValueKey('next-episode-fab-container')))
              .width <
          70,
      isTrue,
    );
  });

  testWidgets(
    'bouton prochain épisode ouvre Episodes et positionne la saison cible',
    (tester) async {
      await tester.pumpWidget(buildTitlePage());
      await tester.pumpAndSettle();

      expect(find.text('Informations sur la série'), findsOneWidget);
      expect(find.textContaining('S01 | E02'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('next-episode-fab')));
      await tester.pumpAndSettle();

      expect(find.text('Saison 1'), findsOneWidget);
      expect(find.textContaining('S01 | E02'), findsOneWidget);
      expect(find.text('Informations sur la série'), findsNothing);
    },
  );

  testWidgets(
    'bouton prochain épisode scrolle jusqu\'à un épisode plus bas dans la saison',
    (tester) async {
      final longSeasonEpisodes = List<Episode>.generate(
        20,
        (index) => Episode(
          id: 300 + index,
          name: 'Episode ${index + 1}',
          overview: 'Description ${index + 1}',
          episodeNumber: index + 1,
          seasonNumber: 1,
          stillPath: null,
          airDate: '2024-01-01',
          runtime: 42,
        ),
      );

      await tester.pumpWidget(
        buildTitlePage(
          watchedEpisodes: {for (var i = 1; i <= 7; i++) '1_$i'},
          seasonEpisodes: longSeasonEpisodes,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('next-episode-fab')));
      await tester.pumpAndSettle();

      expect(find.textContaining('S01 | E08'), findsOneWidget);
      final episodeCenter = tester.getCenter(find.textContaining('S01 | E08'));
      final viewportCenter =
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
      expect((episodeCenter.dy - viewportCenter).abs(), lessThan(170));
    },
  );

  testWidgets('une saison vide affiche un état vide explicite', (tester) async {
    await tester.pumpWidget(buildTitlePage(seasonEpisodes: []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saison 1'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun épisode chargé'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('la liste des épisodes utilise le nouveau toggle rond', (
    tester,
  ) async {
    await tester.pumpWidget(buildTitlePage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saison 1'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });

  testWidgets('le toggle épisode affiche xN quand il y a des revues', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTitlePage(
        watchedEpisodes: const {'1_1'},
        episodeViewCounts: const {'1_1': 3},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saison 1'));
    await tester.pumpAndSettle();

    expect(find.text('x3'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('le toggle saison affiche xN quand toute la saison est revue', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTitlePage(
        watchedEpisodes: const {'1_1', '1_2'},
        episodeViewCounts: const {'1_1': 2, '1_2': 4},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();

    expect(find.text('x2'), findsOneWidget);
  });

  testWidgets('sur film la case utilise le même toggle rond que les séries', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMovieTitlePage(
        status: WatchStatus.watched,
        movieViewCount: 1,
        firstWatchedAtMillis: DateTime(2024, 3, 10).millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('movie-watched-toggle')), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('sur film le toggle affiche xN quand il y a des revues', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMovieTitlePage(
        status: WatchStatus.watched,
        movieViewCount: 3,
        firstWatchedAtMillis: DateTime(2024, 3, 10).millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('x3'), findsOneWidget);
  });

  testWidgets('sur film revoir (+1 vue) garde le statut vu et incrémente xN', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMovieTitlePage(
        status: WatchStatus.watched,
        movieViewCount: 1,
        firstWatchedAtMillis: DateTime(2024, 3, 10).millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('movie-watched-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Déjà vu'), findsOneWidget);

    await tester.tap(find.text('Revoir (+1 vue)'));
    await tester.pumpAndSettle();

    expect(find.text('x2'), findsOneWidget);
  });

  testWidgets('la barre de progression de saison utilise une piste teintée', (
    tester,
  ) async {
    await tester.pumpWidget(buildTitlePage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('season-progress-1')),
    );
    expect(progress.backgroundColor, isNot(equals(Colors.white)));
  });

  testWidgets('sur saison déjà vue, le dialogue propose la revue de saison', (
    tester,
  ) async {
    await tester.pumpWidget(buildTitlePage(watchedEpisodes: {'1_1', '1_2'}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Épisodes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('season-toggle-1')));
    await tester.pumpAndSettle();

    expect(find.text('Saison déjà vue'), findsOneWidget);
    expect(find.text('Revoir la saison (+1 vue)'), findsOneWidget);
  });
}

class _FakeMediaRepository extends MediaRepository {
  _FakeMediaRepository({
    required this.details,
    required this.tracked,
    required this.status,
    required this.progress,
    required this.episodeViewCounts,
    required this.seasonEpisodes,
    this.movieViewCount = 0,
    this.movieFirstWatchedAt,
  }) : super(
         TmdbApiClient(apiKey: ''),
         TvdbApiClient(apiKey: ''),
         WatchTrackerDatabase(),
       ) {
    _movieViewCount = movieViewCount;
  }

  final MediaDetails details;
  final bool tracked;
  final WatchStatus? status;
  final List<RemoteEpisodeProgress> progress;
  final Map<String, int> episodeViewCounts;
  final Map<int, List<Episode>> seasonEpisodes;
  final int movieViewCount;
  final int? movieFirstWatchedAt;
  late int _movieViewCount;

  @override
  Future<MediaDetails> getMovieDetails(int id) async => details;

  @override
  Future<MediaDetails> getTvDetails(int id) async => details;

  @override
  Future<void> prefetchSeasonEpisodes(MediaDetails details) async {}

  @override
  Future<bool> isInWatchlist(
    int id,
    MediaType type,
    WatchCategory category,
  ) async => tracked;

  @override
  Future<WatchStatus?> getWatchStatus(
    int id,
    MediaType type,
    WatchCategory category,
  ) async => status;

  @override
  Future<List<RemoteEpisodeProgress>> getEpisodeProgress(int mediaId) async =>
      progress;

  @override
  Future<Map<String, int>> getEpisodeViewCounts(int mediaId) async =>
      episodeViewCounts;

  @override
  Future<int?> getMovieFirstWatchedAt(int mediaId) async => movieFirstWatchedAt;

  @override
  Future<int> getMovieViewCount(int mediaId) async => _movieViewCount;

  @override
  Future<List<int>> getEpisodeWatchDates({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
  }) async => const [];

  @override
  Future<List<int>> getMovieWatchDates(int mediaId) async => const [];

  @override
  Future<void> markMovieWatched(
    Media media,
    WatchCategory category, {
    bool rewatch = false,
    int? watchedAtMillis,
  }) async {
    _movieViewCount = (_movieViewCount <= 0) ? 1 : _movieViewCount + 1;
  }

  @override
  Future<void> markMovieUnwatched(Media media, WatchCategory category) async {
    _movieViewCount = 0;
  }

  @override
  Future<void> addToWatchlist(
    Media media,
    WatchCategory category,
    WatchStatus status,
    int totalEpisodes,
  ) async {}

  @override
  Future<void> updateWatchStatus(
    Media media,
    WatchCategory category,
    WatchStatus status,
  ) async {}

  @override
  Future<List<Episode>> getSeasonEpisodes(int tvId, int seasonNumber) async =>
      seasonEpisodes[seasonNumber] ?? const [];
}
