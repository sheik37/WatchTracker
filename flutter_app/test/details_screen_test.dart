import 'package:flutter/material.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
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

  Widget buildPage({
    int initialIndex = 0,
    Set<String> watchedEpisodes = const {},
    Map<String, int> episodeWatchedAt = emptyWatchedAt,
    bool Function(Episode)? isReleasedCheck,
    Future<void> Function(Episode, bool)? onToggleWatched,
    List<Episode>? episodeList,
    Map<int, int>? seasonOffsets,
    String? seriesTitle,
    ({Set<String> watched, Map<String, int> watchedAt}) Function()? getProgress,
  }) {
    return MaterialApp(
      home: EpisodeDetailPage(
        episodes: episodeList ?? episodes,
        initialIndex: initialIndex,
        watchedEpisodes: watchedEpisodes,
        episodeWatchedAt: episodeWatchedAt,
        seasonOffsets: seasonOffsets ?? defaultOffsets,
        seriesTitle: seriesTitle ?? defaultSeriesTitle,
        isReleasedCheck: isReleasedCheck ?? (ep) => ep.airDate != '2099-01-01',
        onToggleWatched: onToggleWatched ?? (_, __) async {},
        getProgress:
            getProgress ??
            () => (watched: watchedEpisodes, watchedAt: episodeWatchedAt),
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

  testWidgets('navigates to next episode via arrow button', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E01'), findsOneWidget);

    await tester.tap(find.byTooltip('Épisode suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('S01 | E02'), findsOneWidget);
  });

  testWidgets('navigates to previous episode via arrow button', (
    tester,
  ) async {
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

  testWidgets('flèche précédent désactivée sur le premier épisode', (tester) async {
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

  testWidgets('flèche suivant désactivée sur le dernier épisode', (tester) async {
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

  testWidgets('bouton affiche Marquer non vu quand épisode vu', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(watchedEpisodes: {'1_1'}));
    await tester.pump();

    expect(find.text('Marquer non vu'), findsOneWidget);
    expect(find.text('Marquer comme vu'), findsNothing);
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

  testWidgets('le bouton est désactivé pour les épisodes non diffusés', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 2));
    await tester.pump();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('supports back navigation', (tester) async {
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
                    watchedEpisodes: const {},
                    episodeWatchedAt: const {},
                    seasonOffsets: defaultOffsets,
                    seriesTitle: defaultSeriesTitle,
                    isReleasedCheck: (_) => true,
                    onToggleWatched: (_, __) async {},
                    getProgress: () => (watched: const {}, watchedAt: const {}),
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

      await tester.pumpWidget(
        buildPage(
          initialIndex: 1,
          watchedEpisodes: watched,
          episodeWatchedAt: watchedAt,
          getProgress: () => (watched: watched, watchedAt: watchedAt),
          onToggleWatched: (ep, target) async {
            // Simulate parent marking ep2 AND ep1 (batch)
            watched = {'1_1', '1_2'};
            watchedAt = {'1_1': millis, '1_2': millis};
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
}
