import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/backend_models.dart';
import '../../data/models/details_models.dart';
import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import '../theme/slide_up_route.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({
    super.key,
    required this.repository,
    required this.media,
  });

  final MediaRepository repository;
  final Media media;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  MediaDetails? _details;
  WatchStatus? _status;
  bool _tracked = false;
  bool _loading = true;
  String? _error;
  Set<String> _watchedEpisodes = {};
  Map<String, int> _episodeWatchedAt = {};
  int? _movieWatchedAtMillis;
  bool _showEpisodes = false;
  int _tvTabDirection = 1;
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, List<Episode>> _episodesBySeason = {};
  double _tvSwipeDelta = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = widget.media.mediaType == MediaType.movie
          ? await widget.repository.getMovieDetails(widget.media.id)
          : await widget.repository.getTvDetails(widget.media.id);
      if (details.mediaType == MediaType.tv) {
        unawaited(widget.repository.prefetchSeasonEpisodes(details));
      }
      final category = details.watchCategory();
      final tracked = await widget.repository.isInWatchlist(
        widget.media.id,
        widget.media.mediaType,
        category,
      );
      final status = tracked
          ? await widget.repository.getWatchStatus(
              widget.media.id,
              widget.media.mediaType,
              category,
            )
          : null;
      final progressList = await widget.repository.getEpisodeProgress(
        widget.media.id,
      );
      final watchedSet = progressList
          .where((p) => p.isWatched)
          .map((p) => '${p.seasonNumber}_${p.episodeNumber}')
          .toSet();
      final watchedAtMap = {
        for (final p in progressList.where((p) => p.isWatched))
          '${p.seasonNumber}_${p.episodeNumber}': p.updatedAtMillis ?? 0,
      };
      _details = details;
      _tracked = tracked;
      _status = status;
      _watchedEpisodes = watchedSet;
      _episodeWatchedAt = watchedAtMap;
      _movieWatchedAtMillis =
          details.mediaType == MediaType.movie && status == WatchStatus.watched
          ? DateTime.now().millisecondsSinceEpoch
          : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleWatchlist() async {
    final details = _details;
    if (details == null) return;
    final category = details.watchCategory();
    if (_tracked) {
      final label = category == WatchCategory.anime
          ? ('animé', 'cet animé')
          : category == WatchCategory.films
          ? ('film', 'ce film')
          : ('série', 'cette série');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
          title: Text('Supprimer le ${label.$1}'),
          content: Text('Retirer ${label.$2} de vos suivis ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Supprimer',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) await _removeFromWatchlist();
      return;
    }
    final totalEpisodes = details.mediaType == MediaType.movie
        ? 1
        : details.seasons
              .where((s) => s.seasonNumber != 0)
              .fold(0, (acc, s) => acc + s.episodeCount);
    final defaultStatus = category.defaultStatus();
    await widget.repository.addToWatchlist(
      details.toMedia(),
      category,
      defaultStatus,
      totalEpisodes,
    );
    setState(() {
      _tracked = true;
      _status = defaultStatus;
      if (details.mediaType == MediaType.movie) {
        _movieWatchedAtMillis = null;
      }
    });
  }

  Future<void> _removeFromWatchlist() async {
    final details = _details;
    if (details == null) return;
    await widget.repository.removeFromWatchlist(
      details.toMedia(),
      details.watchCategory(),
    );
    setState(() {
      _tracked = false;
      _status = null;
      if (details.mediaType == MediaType.movie) {
        _movieWatchedAtMillis = null;
      }
    });
  }

  Future<void> _setMovieWatched(bool watched) async {
    final details = _details;
    if (details == null) return;
    final category = details.watchCategory();
    final newStatus = watched ? WatchStatus.watched : WatchStatus.notWatched;
    final previousStatus = _status;
    final previousMillis = _movieWatchedAtMillis;
    final previousTracked = _tracked;
    // Optimistic update
    setState(() {
      if (!_tracked) _tracked = true;
      _status = newStatus;
      _movieWatchedAtMillis = watched
          ? DateTime.now().millisecondsSinceEpoch
          : null;
    });
    try {
      if (!previousTracked) {
        await widget.repository.addToWatchlist(
          details.toMedia(),
          category,
          WatchStatus.notWatched,
          1,
        );
      }
      await widget.repository.updateWatchStatus(
        details.toMedia(),
        category,
        newStatus,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tracked = previousTracked;
        _status = previousStatus;
        _movieWatchedAtMillis = previousMillis;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour le film: $e')),
      );
    }
  }

  Future<void> _setEpisodeWatched(
    Episode episode,
    bool watched,
    int? updatedAtMillis,
  ) async {
    final details = _details;
    if (details == null) return;
    final key = '${episode.seasonNumber}_${episode.episodeNumber}';
    final previous = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final next = <String>{..._watchedEpisodes};
    final nextAt = Map<String, int>.from(_episodeWatchedAt);
    final ts = updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (watched) {
      next.add(key);
      nextAt[key] = ts;
    } else {
      next.remove(key);
      nextAt.remove(key);
    }
    setState(() {
      _watchedEpisodes = next;
      _episodeWatchedAt = nextAt;
    });
    _updateTvStatus(details);
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    try {
      await widget.repository.updateEpisodeProgress(
        mediaId: details.id,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
        isWatched: watched,
        updatedAtMillis: watched ? ts : null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previous;
        _episodeWatchedAt = previousAt;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour l\'épisode: $e')),
      );
    }
  }

  Future<void> _markSeasonWatched(Season targetSeason, bool watched) async {
    final details = _details;
    if (details == null) return;
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    final seasons = details.seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final updates = <RemoteEpisodeProgress>[];
    if (targetSeason.seasonNumber == 0) {
      final episodeNumbers = await _episodeNumbersToMark(
        details.id,
        targetSeason,
        watched,
      );
      for (final i in episodeNumbers) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: 0,
            episodeNumber: i,
            isWatched: watched,
          ),
        );
      }
    } else if (watched) {
      for (final season in seasons.where(
        (s) => s.seasonNumber <= targetSeason.seasonNumber,
      )) {
        final episodeNumbers = await _episodeNumbersToMark(
          details.id,
          season,
          true,
          maxEpisodeForTarget: season.seasonNumber == targetSeason.seasonNumber
              ? targetSeason.episodeCount
              : null,
        );
        for (final i in episodeNumbers) {
          updates.add(
            RemoteEpisodeProgress(
              mediaId: details.id,
              seasonNumber: season.seasonNumber,
              episodeNumber: i,
              isWatched: true,
            ),
          );
        }
      }
    } else {
      final episodeNumbers = await _episodeNumbersToMark(
        details.id,
        targetSeason,
        false,
      );
      for (final i in episodeNumbers) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: targetSeason.seasonNumber,
            episodeNumber: i,
            isWatched: false,
          ),
        );
      }
    }
    await _applyEpisodeUpdates(details, updates);
  }

  Future<void> _markOnlySeasonWatched(Season targetSeason, bool watched) async {
    final details = _details;
    if (details == null) return;
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    final episodeNumbers = await _episodeNumbersToMark(
      details.id,
      targetSeason,
      watched,
    );
    final updates = <RemoteEpisodeProgress>[];
    for (final i in episodeNumbers) {
      updates.add(
        RemoteEpisodeProgress(
          mediaId: details.id,
          seasonNumber: targetSeason.seasonNumber,
          episodeNumber: i,
          isWatched: watched,
        ),
      );
    }
    await _applyEpisodeUpdates(details, updates);
  }

  Future<void> _markEpisodeUpTo(
    Episode targetEpisode,
    int? updatedAtMillis,
  ) async {
    final details = _details;
    if (details == null) return;
    await _ensureTvTrackedForEpisodeUpdate(details);
    final seasons = details.seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final targetSeason = seasons.firstWhere(
      (s) => s.seasonNumber == targetEpisode.seasonNumber,
      orElse: () => Season(
        id: 0,
        name: '',
        seasonNumber: targetEpisode.seasonNumber,
        episodeCount: targetEpisode.episodeNumber,
      ),
    );
    final ts = updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    final updates = <RemoteEpisodeProgress>[];
    for (final season in seasons.where(
      (s) => s.seasonNumber < targetEpisode.seasonNumber,
    )) {
      for (var i = 1; i <= season.episodeCount; i++) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: season.seasonNumber,
            episodeNumber: i,
            isWatched: true,
            updatedAtMillis: ts,
          ),
        );
      }
    }
    final end = targetEpisode.episodeNumber
        .clamp(1, targetSeason.episodeCount)
        .toInt();
    for (var i = 1; i <= end; i++) {
      updates.add(
        RemoteEpisodeProgress(
          mediaId: details.id,
          seasonNumber: targetEpisode.seasonNumber,
          episodeNumber: i,
          isWatched: true,
          updatedAtMillis: ts,
        ),
      );
    }
    await _applyEpisodeUpdates(details, updates, ts);
  }

  Future<void> _applyEpisodeUpdates(
    MediaDetails details,
    List<RemoteEpisodeProgress> updates, [
    int? sharedTimestamp,
  ]) async {
    if (updates.isEmpty) return;
    final previous = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final next = <String>{..._watchedEpisodes};
    final nextAt = Map<String, int>.from(_episodeWatchedAt);
    final nowFallback =
        sharedTimestamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final update in updates) {
      final key = '${update.seasonNumber}_${update.episodeNumber}';
      if (update.isWatched) {
        next.add(key);
        nextAt[key] = update.updatedAtMillis ?? nowFallback;
      } else {
        next.remove(key);
        nextAt.remove(key);
      }
    }
    setState(() {
      _watchedEpisodes = next;
      _episodeWatchedAt = nextAt;
    });
    _updateTvStatus(details);
    try {
      await widget.repository.updateEpisodeProgressBatch(
        mediaId: details.id,
        updates: updates,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previous;
        _episodeWatchedAt = previousAt;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour la saison: $e')),
      );
    }
  }

  Future<List<int>> _episodeNumbersToMark(
    int mediaId,
    Season season,
    bool watched, {
    int? maxEpisodeForTarget,
  }) async {
    final maxEpisode = maxEpisodeForTarget ?? season.episodeCount;
    if (!watched) {
      return List<int>.generate(maxEpisode, (i) => i + 1, growable: false);
    }
    final episodes = await _loadSeasonEpisodesForMarking(mediaId, season);
    final released =
        episodes
            .where(_isReleasedEpisode)
            .map((e) => e.episodeNumber)
            .where((n) => n > 0 && n <= maxEpisode)
            .toSet()
            .toList()
          ..sort();
    return released;
  }

  Future<List<Episode>> _loadSeasonEpisodesForMarking(
    int mediaId,
    Season season,
  ) async {
    if (season.episodes.isNotEmpty) return season.episodes;
    try {
      return await widget.repository.getSeasonEpisodes(
        mediaId,
        season.seasonNumber,
      );
    } catch (_) {
      return const <Episode>[];
    }
  }

  bool _isReleasedEpisode(Episode episode) {
    final raw = episode.airDate;
    if (raw == null || raw.isEmpty) return false;
    final date = DateTime.tryParse(raw);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final airDay = DateTime(date.year, date.month, date.day);
    return !airDay.isAfter(today);
  }

  Future<void> _ensureTvTrackedForEpisodeUpdate(MediaDetails details) async {
    if (_tracked) return;
    final category = details.watchCategory();
    final total = details.seasons
        .where((s) => s.seasonNumber != 0)
        .fold(0, (acc, s) => acc + s.episodeCount);
    await widget.repository.addToWatchlist(
      details.toMedia(),
      category,
      category.defaultStatus(),
      total,
    );
    setState(() {
      _tracked = true;
      _status = category.defaultStatus();
    });
  }

  void _updateTvStatus(MediaDetails details) {
    final total = details.seasons
        .where((s) => s.seasonNumber != 0)
        .fold(0, (acc, s) => acc + s.episodeCount);
    final watched = _watchedEpisodes.where((k) => !k.startsWith('0_')).length;
    WatchStatus newStatus;
    if (watched <= 0) {
      newStatus = WatchStatus.notStarted;
    } else if (total > 0 && watched >= total) {
      newStatus = details.tvStatus == TvStatus.ended
          ? WatchStatus.completed
          : WatchStatus.upToDate;
    } else {
      newStatus = WatchStatus.inProgress;
    }
    if (_status != newStatus) {
      setState(() => _status = newStatus);
      widget.repository.updateWatchStatus(
        details.toMedia(),
        details.watchCategory(),
        newStatus,
      );
    }
  }

  void _onSeasonEpisodesLoaded(int seasonNumber, List<Episode> episodes) {
    _episodesBySeason[seasonNumber] = episodes;
  }

  Future<bool?> _showMarkUpToDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        title: const Text('Épisodes précédents manquants'),
        content: const Text(
          'Des épisodes précédents ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seulement celui-ci'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text("Cocher jusqu'ici"),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleEpisodeWithCheck(Episode episode, bool target) async {
    final details = _details;
    if (details == null) return;
    if (episode.seasonNumber == 0) {
      await _setEpisodeWatched(episode, target, null);
      return;
    }
    if (!target) {
      await _setEpisodeWatched(episode, false, null);
      return;
    }
    final orderedSeasons = _orderedSeasons(details.seasons);
    final offsets = _seasonOffsets(orderedSeasons);
    final seasonOffset = offsets[episode.seasonNumber] ?? 0;
    final expectedPreviousCount = seasonOffset + episode.episodeNumber - 1;

    final watchedPositions =
        _watchedEpisodes
            .where((k) => !k.startsWith('0_'))
            .map((k) {
              final idx = k.indexOf('_');
              if (idx <= 0 || idx >= k.length - 1) return null;
              final s = int.tryParse(k.substring(0, idx));
              final e = int.tryParse(k.substring(idx + 1));
              if (s == null || e == null) return null;
              return s * 10000 + e;
            })
            .whereType<int>()
            .toList()
          ..sort();

    final currentKey = episode.seasonNumber * 10000 + episode.episodeNumber;
    var watchedPrevious = 0;
    for (final k in watchedPositions) {
      if (k < currentKey) watchedPrevious++;
    }

    if (watchedPrevious < expectedPreviousCount) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldMarkUpTo = await _showMarkUpToDialog();
      if (!mounted || shouldMarkUpTo == null) return;
      if (shouldMarkUpTo) {
        await _markEpisodeUpTo(episode, now);
      } else {
        await _setEpisodeWatched(episode, true, now);
      }
      return;
    }
    await _setEpisodeWatched(episode, true, null);
  }

  Future<void> _openEpisodeDetailPage(Episode episode) async {
    final details = _details;
    if (details == null) return;
    final orderedSeasons = _orderedSeasons(details.seasons);
    final offsets = _seasonOffsets(orderedSeasons);

    final allEpisodes = <Episode>[];
    for (final season in orderedSeasons) {
      final cached = _episodesBySeason[season.seasonNumber];
      if (cached != null && cached.isNotEmpty) {
        allEpisodes.addAll(cached);
      } else if (season.episodes.isNotEmpty) {
        _episodesBySeason[season.seasonNumber] = season.episodes;
        allEpisodes.addAll(season.episodes);
      } else {
        try {
          final fetched = await widget.repository.getSeasonEpisodes(
            details.id,
            season.seasonNumber,
          );
          _episodesBySeason[season.seasonNumber] = fetched;
          allEpisodes.addAll(fetched);
        } catch (_) {}
      }
    }

    if (allEpisodes.isEmpty || !mounted) return;

    final index = allEpisodes.indexWhere(
      (e) =>
          e.seasonNumber == episode.seasonNumber &&
          e.episodeNumber == episode.episodeNumber,
    );
    if (index < 0) return;

    await Navigator.of(context).push<void>(
      SlideUpRoute(
        builder: (ctx) => EpisodeDetailPage(
          episodes: allEpisodes,
          initialIndex: index,
          watchedEpisodes: _watchedEpisodes,
          episodeWatchedAt: _episodeWatchedAt,
          seasonOffsets: offsets,
          seriesTitle: details.title,
          isReleasedCheck: _isReleasedEpisode,
          onToggleWatched: _toggleEpisodeWithCheck,
          getProgress: () =>
              (watched: _watchedEpisodes, watchedAt: _episodeWatchedAt),
        ),
      ),
    );
  }

  Color? _progressColor() {
    return switch (_status) {
      WatchStatus.inProgress => const Color(0xFFFFC107),
      WatchStatus.upToDate => const Color(0xFF4CAF50),
      WatchStatus.completed || WatchStatus.watched => const Color(0xFF9C27B0),
      _ => null,
    };
  }

  double _progressValue(MediaDetails details) {
    if (_status == WatchStatus.inProgress) {
      final total = details.seasons
          .where((s) => s.seasonNumber != 0)
          .fold(0, (acc, s) => acc + s.episodeCount);
      if (total <= 0) return 0;
      final watched = _watchedEpisodes.where((k) => !k.startsWith('0_')).length;
      return (watched / total).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  void _setTvTab(bool showEpisodes) {
    if (_showEpisodes == showEpisodes) return;
    setState(() {
      _tvTabDirection = showEpisodes ? 1 : -1;
      _showEpisodes = showEpisodes;
    });
  }

  void _handleTvTabSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const minSwipeVelocity = 250.0;
    const minSwipeDistance = 80.0;
    if ((velocity <= -minSwipeVelocity || _tvSwipeDelta <= -minSwipeDistance) &&
        !_showEpisodes) {
      _setTvTab(true);
    } else if ((velocity >= minSwipeVelocity ||
            _tvSwipeDelta >= minSwipeDistance) &&
        _showEpisodes) {
      _setTvTab(false);
    }
    _tvSwipeDelta = 0;
  }

  Widget _buildTvTabContent(
    MediaDetails details,
    List<Season> orderedSeasons,
    Map<int, int> seasonOffsets,
  ) {
    const aboutKey = ValueKey('tv-tab-about');
    const episodesKey = ValueKey('tv-tab-episodes');
    final currentKey = _showEpisodes ? episodesKey : aboutKey;
    final direction = _tvTabDirection.toDouble();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        final children = <Widget>[...previousChildren];
        if (currentChild != null) {
          children.add(currentChild);
        }
        return ClipRect(
          child: Stack(alignment: Alignment.topCenter, children: children),
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == currentKey;
        final offsetTween = isIncoming
            ? Tween<Offset>(
                begin: Offset(direction * 0.18, 0),
                end: Offset.zero,
              )
            : Tween<Offset>(
                begin: Offset(-direction * 0.18, 0),
                end: Offset.zero,
              );
        return SlideTransition(
          position: offsetTween.animate(animation),
          child: child,
        );
      },
      child: _showEpisodes
          ? KeyedSubtree(
              key: episodesKey,
              child: Column(
                children: [
                  for (final season in orderedSeasons)
                    _SeasonSection(
                      key: PageStorageKey<String>(
                        'season_${details.id}_${season.seasonNumber}',
                      ),
                      mediaId: details.id,
                      repository: widget.repository,
                      parentScrollController: _scrollCtrl,
                      season: season,
                      seasonOffset: seasonOffsets[season.seasonNumber] ?? 0,
                      watchedEpisodes: _watchedEpisodes,
                      onToggleEpisode: _setEpisodeWatched,
                      onMarkSeasonWatched: _markSeasonWatched,
                      onMarkOnlySeasonWatched: _markOnlySeasonWatched,
                      onMarkEpisodeUpTo: _markEpisodeUpTo,
                      onOpenEpisode: _openEpisodeDetailPage,
                      onEpisodesLoaded: _onSeasonEpisodesLoaded,
                    ),
                ],
              ),
            )
          : KeyedSubtree(
              key: aboutKey,
              child: _TvAbout(
                details: details,
                category: details.watchCategory(),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _details == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error!)),
      );
    }
    final details = _details;
    if (details == null) return const Scaffold(body: SizedBox.shrink());

    final isTV = details.mediaType == MediaType.tv;
    final progressColor = (_tracked && isTV) ? _progressColor() : null;
    final orderedSeasons = _orderedSeasons(details.seasons);
    final seasonOffsets = _seasonOffsets(orderedSeasons);
    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return Scaffold(
      bottomNavigationBar: !_tracked
          ? _AddBottomBar(
              category: details.watchCategory(),
              onAdd: _toggleWatchlist,
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: isTV ? (_) => _tvSwipeDelta = 0 : null,
        onHorizontalDragUpdate: isTV
            ? (details) => _tvSwipeDelta += details.primaryDelta ?? 0
            : null,
        onHorizontalDragEnd: isTV ? _handleTvTabSwipe : null,
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DetailsHeaderDelegate(
                details: details,
                isTV: isTV,
                showEpisodes: _showEpisodes,
                onShowEpisodesChanged: _setTvTab,
                tracked: _tracked,
                progressColor: progressColor,
                progressValue: progressColor != null
                    ? _progressValue(details)
                    : null,
                watchedGlobal: _tracked && isTV
                    ? _watchedEpisodes.where((k) => !k.startsWith('0_')).length
                    : null,
                totalGlobal: _tracked && isTV
                    ? details.seasons
                          .where((s) => s.seasonNumber != 0)
                          .fold<int>(0, (acc, s) => acc + s.episodeCount)
                    : null,
                onBack: () => Navigator.of(context).pop(),
                onToggleWatchlist: _toggleWatchlist,
                statusBarHeight: statusBarHeight,
              ),
            ),
            if (isTV)
              SliverToBoxAdapter(
                child: _buildTvTabContent(
                  details,
                  orderedSeasons,
                  seasonOffsets,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _MovieInfoStrip(
                  releaseDate: details.releaseDate,
                  isWatched: _status == WatchStatus.watched,
                  watchedAtMillis: _movieWatchedAtMillis,
                  onChanged: _setMovieWatched,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Synopsis',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        details.overview.isEmpty
                            ? 'Aucun synopsis disponible.'
                            : details.overview,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  List<Season> _orderedSeasons(List<Season> seasons) {
    final specials = seasons.where((s) => s.seasonNumber == 0).toList();
    final regular = seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return [...regular, ...specials];
  }

  Map<int, int> _seasonOffsets(List<Season> seasons) {
    var offset = 0;
    final map = <int, int>{};
    for (final season in seasons.where((s) => s.seasonNumber != 0)) {
      map[season.seasonNumber] = offset;
      offset += season.episodeCount < 0 ? 0 : season.episodeCount;
    }
    return map;
  }
}

class _DetailsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DetailsHeaderDelegate({
    required this.details,
    required this.isTV,
    required this.showEpisodes,
    required this.onShowEpisodesChanged,
    required this.tracked,
    required this.progressColor,
    required this.progressValue,
    required this.onBack,
    required this.onToggleWatchlist,
    required this.statusBarHeight,
    this.watchedGlobal,
    this.totalGlobal,
  });

  final MediaDetails details;
  final bool isTV;
  final bool showEpisodes;
  final ValueChanged<bool> onShowEpisodesChanged;
  final bool tracked;
  final Color? progressColor;
  final double? progressValue;
  final VoidCallback onBack;
  final VoidCallback onToggleWatchlist;
  final double statusBarHeight;
  final int? watchedGlobal;
  final int? totalGlobal;

  static const double _headerMaxBase = 210;
  static const double _headerMinBase = 59;
  static const double _tabsHeight = 48;

  @override
  double get minExtent =>
      _headerMinBase + statusBarHeight + (isTV ? _tabsHeight : 0);

  @override
  double get maxExtent =>
      _headerMaxBase + statusBarHeight + (isTV ? _tabsHeight : 0);

  double get _collapseRange => _headerMaxBase - _headerMinBase;

  @override
  bool shouldRebuild(covariant _DetailsHeaderDelegate old) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / _collapseRange).clamp(0.0, 1.0);
    final titleAlpha = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
    final contentAlpha = (1.0 - titleAlpha).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop image — fills the header minus the tabs area
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: isTV ? _tabsHeight : 0,
          child: _MediaHeader(
            details: details,
            contentAlpha: contentAlpha,
            progressColor: progressColor,
            progressValue: progressValue,
            watchedGlobal: watchedGlobal,
            totalGlobal: totalGlobal,
          ),
        ),

        // Tab bar — always pinned at the bottom of the header (TV only)
        if (isTV)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _tabsHeight,
            child: _TvTabs(
              showEpisodes: showEpisodes,
              onChanged: onShowEpisodesChanged,
            ),
          ),

        // Action row (back button, collapsing title, menu)
        Positioned(
          top: statusBarHeight,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: onBack,
                ),
                Expanded(
                  child: titleAlpha > 0
                      ? Text(
                          details.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: titleAlpha),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                  ),
                  onSelected: (value) {
                    if (value == 'toggle') onToggleWatchlist();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        tracked ? 'Retirer des suivis' : 'Ajouter aux suivis',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaHeader extends StatelessWidget {
  const _MediaHeader({
    required this.details,
    required this.contentAlpha,
    this.progressColor,
    this.progressValue,
    this.watchedGlobal,
    this.totalGlobal,
  });

  final MediaDetails details;
  final double contentAlpha;
  final Color? progressColor;
  final double? progressValue;
  final int? watchedGlobal;
  final int? totalGlobal;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (details.backdropPath != null || details.posterPath != null)
          CachedNetworkImage(
            imageUrl: details.backdropPath ?? details.posterPath!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(color: Colors.black54),
          )
        else
          Container(color: Colors.black87),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xB3000000)],
              stops: [0.4, 1.0],
            ),
          ),
        ),
        Positioned(
          bottom: progressColor != null ? 10 : 0,
          left: 16,
          right: 16,
          child: Opacity(
            opacity: contentAlpha,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  details.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.mediaType == MediaType.tv) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${details.seasons.where((s) => s.seasonNumber != 0).length} saison(s)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      if (details.tvStatus != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                        Text(
                          details.tvStatus!.label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (watchedGlobal != null &&
                          totalGlobal != null &&
                          totalGlobal! > 0) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                        Text(
                          '$watchedGlobal / $totalGlobal épisodes vus',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (progressColor != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 6,
              color: progressColor,
              backgroundColor: Colors.black.withValues(alpha: 0.35),
            ),
          ),
      ],
    );
  }
}

extension on TvStatus {
  String get label => switch (this) {
    TvStatus.returningSeries => 'Série en cours',
    TvStatus.ended => 'Terminée',
    TvStatus.canceled => 'Annulée',
    TvStatus.planned => 'Prévue',
    TvStatus.inProduction => 'En production',
  };
}

class _TvTabs extends StatelessWidget {
  const _TvTabs({required this.showEpisodes, required this.onChanged});

  final bool showEpisodes;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    final selectedTextColor = Theme.of(context).colorScheme.onSurface;
    final unselectedTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final textTheme = Theme.of(context).textTheme.labelLarge;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: _TvTabButton(
              label: 'À propos',
              selected: !showEpisodes,
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              unselectedTextColor: unselectedTextColor,
              textStyle: textTheme,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _TvTabButton(
              label: 'Épisodes',
              selected: showEpisodes,
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              unselectedTextColor: unselectedTextColor,
              textStyle: textTheme,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvTabButton extends StatelessWidget {
  const _TvTabButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? selectedColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: textStyle?.copyWith(
            color: selected ? selectedTextColor : unselectedTextColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TvAbout extends StatelessWidget {
  const _TvAbout({required this.details, required this.category});

  final MediaDetails details;
  final WatchCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category == WatchCategory.anime
                ? 'Informations sur l\'animé'
                : 'Informations sur la série',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            details.overview.isEmpty
                ? 'Aucun synopsis disponible.'
                : details.overview,
          ),
        ],
      ),
    );
  }
}

class _MovieInfoStrip extends StatelessWidget {
  const _MovieInfoStrip({
    required this.releaseDate,
    required this.isWatched,
    required this.watchedAtMillis,
    required this.onChanged,
  });

  final String? releaseDate;
  final bool isWatched;
  final int? watchedAtMillis;
  final ValueChanged<bool> onChanged;

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Date inconnue';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatMillis(int? raw) {
    if (raw == null) return 'Vu';
    final d = DateTime.fromMillisecondsSinceEpoch(raw);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  _formatDate(releaseDate),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 12),
                const Icon(Icons.visibility_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  isWatched ? _formatMillis(watchedAtMillis) : 'Pas vu',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Checkbox(value: isWatched, onChanged: (v) => onChanged(v ?? false)),
        ],
      ),
    );
  }
}

class _WatchedToggleButton extends StatelessWidget {
  const _WatchedToggleButton({
    super.key,
    required this.checked,
    required this.onTap,
    required this.tooltip,
    this.size = 34,
  });

  final bool checked;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.surfaceContainerHigh;
    final borderColor = checked ? activeColor : colorScheme.outlineVariant;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        checked: checked,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? activeColor : inactiveColor,
                border: Border.all(color: borderColor),
                boxShadow: checked
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: checked
                      ? Icon(
                          Icons.check_rounded,
                          key: const ValueKey('checked'),
                          color: colorScheme.onPrimary,
                          size: size * 0.56,
                        )
                      : Container(
                          key: const ValueKey('unchecked'),
                          width: size * 0.18,
                          height: size * 0.18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonSection extends StatefulWidget {
  const _SeasonSection({
    super.key,
    required this.mediaId,
    required this.repository,
    required this.parentScrollController,
    required this.season,
    required this.seasonOffset,
    required this.watchedEpisodes,
    required this.onToggleEpisode,
    required this.onMarkSeasonWatched,
    required this.onMarkOnlySeasonWatched,
    required this.onMarkEpisodeUpTo,
    required this.onOpenEpisode,
    required this.onEpisodesLoaded,
  });

  final int mediaId;
  final MediaRepository repository;
  final ScrollController parentScrollController;
  final Season season;
  final int seasonOffset;
  final Set<String> watchedEpisodes;
  final Future<void> Function(Episode, bool, int?) onToggleEpisode;
  final Future<void> Function(Season, bool) onMarkSeasonWatched;
  final Future<void> Function(Season, bool) onMarkOnlySeasonWatched;
  final Future<void> Function(Episode, int?) onMarkEpisodeUpTo;
  final Future<void> Function(Episode) onOpenEpisode;
  final void Function(int seasonNumber, List<Episode> episodes)
  onEpisodesLoaded;

  @override
  State<_SeasonSection> createState() => _SeasonSectionState();
}

class _SeasonSectionState extends State<_SeasonSection> {
  bool _expanded = false;
  bool _loadingEpisodes = false;
  List<Episode> _episodes = [];
  final ScrollController _episodesScrollCtrl = ScrollController();

  @override
  void dispose() {
    _episodesScrollCtrl.dispose();
    super.dispose();
  }

  bool _isWatched(Episode ep) =>
      widget.watchedEpisodes.contains('${ep.seasonNumber}_${ep.episodeNumber}');

  bool get _isSpecialSeason => widget.season.seasonNumber == 0;

  int _countWatchedBeforePosition(List<int> watchedPositions, int value) {
    var left = 0;
    var right = watchedPositions.length;
    while (left < right) {
      final mid = (left + right) >> 1;
      if (watchedPositions[mid] < value) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    return left;
  }

  int _expectedPreviousCount(Episode episode) =>
      widget.seasonOffset + episode.episodeNumber - 1;

  int? _parseEpisodePositionKey(String key) {
    final idx = key.indexOf('_');
    if (idx <= 0 || idx >= key.length - 1) return null;
    final s = int.tryParse(key.substring(0, idx));
    final e = int.tryParse(key.substring(idx + 1));
    if (s == null || e == null) return null;
    return _episodePositionKey(s, e);
  }

  int _episodePositionKey(int seasonNumber, int episodeNumber) =>
      seasonNumber * 10000 + episodeNumber;

  Future<void> _loadEpisodesIfNeeded() async {
    if (_episodes.isNotEmpty || widget.season.episodeCount <= 0) return;
    if (widget.season.episodes.isNotEmpty) {
      setState(() => _episodes = widget.season.episodes);
      widget.onEpisodesLoaded(
        widget.season.seasonNumber,
        widget.season.episodes,
      );
      return;
    }
    setState(() => _loadingEpisodes = true);
    try {
      final fetched = await widget.repository.getSeasonEpisodes(
        widget.mediaId,
        widget.season.seasonNumber,
      );
      if (!mounted) return;
      setState(() => _episodes = fetched);
      widget.onEpisodesLoaded(widget.season.seasonNumber, fetched);
    } finally {
      if (mounted) {
        setState(() => _loadingEpisodes = false);
      }
    }
  }

  Future<void> _onEpisodeCheckRequest(Episode episode, bool target) async {
    if (_isSpecialSeason) {
      await widget.onToggleEpisode(episode, target, null);
      return;
    }
    if (!target) {
      await widget.onToggleEpisode(episode, false, null);
      return;
    }
    final watchedPositions =
        widget.watchedEpisodes
            .map(_parseEpisodePositionKey)
            .whereType<int>()
            .toList()
          ..sort();
    final current = _episodePositionKey(
      episode.seasonNumber,
      episode.episodeNumber,
    );
    final watchedPrevious = _countWatchedBeforePosition(
      watchedPositions,
      current,
    );
    if (watchedPrevious < _expectedPreviousCount(episode)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldMarkUpTo = await _showMarkPreviousEpisodesDialog();
      if (!mounted || shouldMarkUpTo == null) return;
      if (shouldMarkUpTo) {
        await widget.onMarkEpisodeUpTo(episode, now);
      } else {
        await widget.onToggleEpisode(episode, true, now);
      }
      return;
    }
    await widget.onToggleEpisode(episode, true, null);
  }

  Future<bool?> _showMarkPreviousEpisodesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Épisodes précédents manquants'),
        content: const Text(
          'Des épisodes précédents ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seulement celui-ci'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMarkPreviousSeasonsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Saisons précédentes manquantes'),
        content: const Text(
          'Des épisodes de saisons précédentes ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seulement cette saison'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text("Cocher jusqu'ici"),
          ),
        ],
      ),
    );
  }

  String _seasonTitle() => _isSpecialSeason
      ? 'Épisodes spéciaux'
      : 'Saison ${widget.season.seasonNumber}';

  Future<void> _onSeasonCheckRequest(bool target) async {
    if (!target || _isSpecialSeason) {
      await widget.onMarkSeasonWatched(widget.season, target);
      return;
    }
    final watchedPositions =
        widget.watchedEpisodes
            .map(_parseEpisodePositionKey)
            .whereType<int>()
            .toList()
          ..sort();
    final firstEpisodePosition = _episodePositionKey(
      widget.season.seasonNumber,
      1,
    );
    final watchedBefore = _countWatchedBeforePosition(
      watchedPositions,
      firstEpisodePosition,
    );
    final expectedBefore = widget.seasonOffset;
    if (watchedBefore < expectedBefore) {
      final includePrevious = await _showMarkPreviousSeasonsDialog();
      if (includePrevious == null) return;
      if (includePrevious) {
        await widget.onMarkSeasonWatched(widget.season, true);
      } else {
        await widget.onMarkOnlySeasonWatched(widget.season, true);
      }
      return;
    }
    await widget.onMarkSeasonWatched(widget.season, true);
  }

  Widget _buildEmptyState() {
    final hasEpisodes = widget.season.episodeCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.38),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.playlist_remove_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                hasEpisodes ? 'Aucun épisode chargé' : 'Saison vide',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                hasEpisodes
                    ? 'Les épisodes n’ont pas encore été chargés.'
                    : 'Cette saison ne contient pas d’épisodes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (hasEpisodes) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _loadEpisodesIfNeeded,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _episodeNumbers(Episode episode) {
    final globalNumber = widget.seasonOffset + episode.episodeNumber;
    return 'S${episode.seasonNumber.toString().padLeft(2, '0')} | E${episode.episodeNumber.toString().padLeft(2, '0')} (E${globalNumber.toString().padLeft(2, '0')})';
  }

  bool _isFutureEpisodeRelease(Episode episode) {
    final raw = episode.airDate;
    if (raw == null || raw.isEmpty) return true;
    final date = DateTime.tryParse(raw);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final airDay = DateTime(date.year, date.month, date.day);
    return airDay.isAfter(today);
  }

  @override
  Widget build(BuildContext context) {
    final watchedCount = widget.watchedEpisodes
        .where((k) => k.startsWith('${widget.season.seasonNumber}_'))
        .length;
    final totalCount = widget.season.episodeCount;
    final allWatched = totalCount > 0 && watchedCount >= totalCount;
    final showProgress = watchedCount > 0 && totalCount > 0;
    final progress = totalCount > 0 ? watchedCount / totalCount : 0.0;
    final progressColor = allWatched
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFC107);
    final progressTrackColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.8);

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          child: InkWell(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
              if (_expanded) {
                _loadEpisodesIfNeeded();
              }
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              _seasonTitle(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                            ),
                          ],
                        ),
                      ),
                      if (totalCount > 0) ...[
                        Text(
                          '$watchedCount/$totalCount',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _WatchedToggleButton(
                        key: ValueKey(
                          'season-toggle-${widget.season.seasonNumber}',
                        ),
                        checked: allWatched,
                        size: 36,
                        tooltip: allWatched
                            ? 'Marquer la saison non vue'
                            : 'Marquer la saison vue',
                        onTap: () => _onSeasonCheckRequest(!allWatched),
                      ),
                    ],
                  ),
                ),
                if (showProgress)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: ValueKey(
                          'season-progress-${widget.season.seasonNumber}',
                        ),
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 8,
                        color: progressColor,
                        backgroundColor: progressTrackColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          _loadingEpisodes
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _episodes.isEmpty
              ? _buildEmptyState()
              : SizedBox(
                  height: (_episodes.length * 96.0).clamp(0.0, 520.0),
                  child: NotificationListener<OverscrollNotification>(
                    onNotification: (notification) {
                      if (!_episodesScrollCtrl.hasClients ||
                          !widget.parentScrollController.hasClients) {
                        return false;
                      }
                      final inner = _episodesScrollCtrl.position;
                      final parent = widget.parentScrollController.position;
                      final isAtInnerBottom =
                          inner.pixels >= inner.maxScrollExtent;
                      final isAtInnerTop =
                          inner.pixels <= inner.minScrollExtent;
                      if ((notification.overscroll > 0 && isAtInnerBottom) ||
                          (notification.overscroll < 0 && isAtInnerTop)) {
                        final target = (parent.pixels + notification.overscroll)
                            .clamp(0.0, parent.maxScrollExtent)
                            .toDouble();
                        if ((target - parent.pixels).abs() > 0.5) {
                          widget.parentScrollController.jumpTo(target);
                        }
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _episodesScrollCtrl,
                      padding: EdgeInsets.zero,
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final ep = _episodes[index];
                        final watched = _isWatched(ep);
                        final showReleaseStatus =
                            !_isWatched(ep) &&
                            (_isFutureEpisodeRelease(ep) || ep.airDate == null);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Card(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            child: ListTile(
                              onTap: () => widget.onOpenEpisode(ep),
                              leading: SizedBox(
                                width: 72,
                                height: 72,
                                child: ep.stillPath == null
                                    ? const Icon(
                                        Icons.image_not_supported_rounded,
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: ep.stillPath!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              title: _isSpecialSeason
                                  ? Text(
                                      ep.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : Text(
                                      _episodeNumbers(ep),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                              subtitle: _isSpecialSeason
                                  ? null
                                  : Text(
                                      ep.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: showReleaseStatus
                                  ? _EpisodeReleaseStatus(airDate: ep.airDate)
                                  : _WatchedToggleButton(
                                      key: ValueKey(
                                        'episode-toggle-${ep.seasonNumber}_${ep.episodeNumber}',
                                      ),
                                      checked: watched,
                                      size: 32,
                                      tooltip: watched
                                          ? 'Marquer l\'épisode non vu'
                                          : 'Marquer l\'épisode vu',
                                      onTap: () =>
                                          _onEpisodeCheckRequest(ep, !watched),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        const Divider(height: 1),
      ],
    );
  }
}

class _EpisodeReleaseStatus extends StatelessWidget {
  const _EpisodeReleaseStatus({required this.airDate});

  final String? airDate;

  @override
  Widget build(BuildContext context) {
    final raw = airDate;
    if (raw == null || raw.isEmpty) {
      return const Text(
        'A venir',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final date = DateTime.tryParse(raw);
    if (date == null) {
      return const Text(
        'A venir',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final episodeDay = DateTime(date.year, date.month, date.day);
    final days = episodeDay.difference(today).inDays;
    final value = days <= 0 ? '0' : '$days';
    final unit = days == 1 ? 'jour' : 'jours';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        Text(unit, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class EpisodeDetailPage extends StatefulWidget {
  const EpisodeDetailPage({
    super.key,
    required this.episodes,
    required this.initialIndex,
    required this.watchedEpisodes,
    required this.episodeWatchedAt,
    required this.seasonOffsets,
    required this.seriesTitle,
    required this.isReleasedCheck,
    required this.onToggleWatched,
    required this.getProgress,
  });

  final List<Episode> episodes;
  final int initialIndex;
  final Set<String> watchedEpisodes;
  final Map<String, int> episodeWatchedAt;
  final Map<int, int> seasonOffsets;
  final String seriesTitle;
  final bool Function(Episode) isReleasedCheck;
  final Future<void> Function(Episode, bool) onToggleWatched;

  /// Returns the current (watched, watchedAt) from the parent after a toggle.
  final ({Set<String> watched, Map<String, int> watchedAt}) Function()
  getProgress;

  @override
  State<EpisodeDetailPage> createState() => _EpisodeDetailPageState();
}

class _EpisodeDetailPageState extends State<EpisodeDetailPage> {
  late int _currentIndex;
  late PageController _pageController;
  late Map<String, bool> _watchedLocal;
  late Map<String, int> _watchedAtLocal;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _watchedLocal = {
      for (final ep in widget.episodes)
        '${ep.seasonNumber}_${ep.episodeNumber}': widget.watchedEpisodes
            .contains('${ep.seasonNumber}_${ep.episodeNumber}'),
    };
    _watchedAtLocal = Map<String, int>.from(widget.episodeWatchedAt);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _syncFromProgress() {
    final progress = widget.getProgress();
    for (final ep in widget.episodes) {
      final k = '${ep.seasonNumber}_${ep.episodeNumber}';
      _watchedLocal[k] = progress.watched.contains(k);
    }
    _watchedAtLocal
      ..clear()
      ..addAll(progress.watchedAt);
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _toggleEpisode(Episode ep) async {
    final k = '${ep.seasonNumber}_${ep.episodeNumber}';
    final target = !(_watchedLocal[k] ?? false);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _watchedLocal[k] = target;
      if (target) {
        _watchedAtLocal[k] = nowMillis;
      } else {
        _watchedAtLocal.remove(k);
      }
    });
    await widget.onToggleWatched(ep, target);
    if (mounted) setState(_syncFromProgress);
  }

  Episode get _current => widget.episodes[_currentIndex];

  bool get _isWatched =>
      _watchedLocal['${_current.seasonNumber}_${_current.episodeNumber}'] ??
      false;

  bool get _isReleased => widget.isReleasedCheck(_current);

  String _episodeRef(Episode ep) =>
      'S${ep.seasonNumber.toString().padLeft(2, '0')} | E${ep.episodeNumber.toString().padLeft(2, '0')}';

  String _globalEpLabel(Episode ep) {
    final offset = widget.seasonOffsets[ep.seasonNumber] ?? 0;
    return 'Ép. ${(offset + ep.episodeNumber).toString().padLeft(2, '0')}';
  }

  String? _watchedDateLabel(String key) {
    final millis = _watchedAtLocal[key];
    if (millis == null || millis == 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return 'Vu le ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  void _showSeasonSheet(BuildContext context) {
    // Liste ordonnée des numéros de saison (même ordre que _orderedSeasons)
    final seasonNumbers = widget.seasonOffsets.keys.toList()
      ..sort((a, b) {
        if (a == 0) return 1;
        if (b == 0) return -1;
        return a.compareTo(b);
      });

    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 320),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _SeasonSheetContent(
        seasonNumbers: seasonNumbers,
        initialSeason: _current.seasonNumber,
        currentEpisode: _current,
        episodes: widget.episodes,
        watchedLocal: _watchedLocal,
        onEpisodeTap: (ep) {
          Navigator.pop(sheetCtx);
          final targetIndex = widget.episodes.indexOf(ep);
          if (targetIndex >= 0) _goTo(targetIndex);
        },
      ),
    );
  }

  Widget _buildEpisodeContent(BuildContext context, int index) {
    final ep = widget.episodes[index];
    final k = '${ep.seasonNumber}_${ep.episodeNumber}';
    final isWatched = _watchedLocal[k] ?? false;
    final isReleased = widget.isReleasedCheck(ep);
    final watchedLabel = isWatched ? _watchedDateLabel(k) : null;
    final runtimeLabel = ep.runtime != null ? '${ep.runtime} min' : 'Inconnue';
    final airDateLabel = ep.airDate?.isNotEmpty == true
        ? ep.airDate!
        : 'Inconnue';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ep.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: isWatched
                ? OutlinedButton.icon(
                    onPressed: () => _toggleEpisode(ep),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Marquer non vu'),
                  )
                : FilledButton.icon(
                    onPressed: isReleased ? () => _toggleEpisode(ep) : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Marquer comme vu'),
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Date : $airDateLabel')),
              Chip(label: Text('Durée : $runtimeLabel')),
              if (isWatched)
                Chip(
                  avatar: const Icon(Icons.check_circle, size: 16),
                  label: Text(watchedLabel ?? 'Vu'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Synopsis',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            ep.overview.isEmpty ? 'Aucun synopsis disponible.' : ep.overview,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.seriesTitle),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'toggle') await _toggleEpisode(_current);
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'toggle',
                enabled: _isReleased,
                child: Text(_isWatched ? 'Marquer non vu' : 'Marquer comme vu'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: current.stillPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: current.stillPath!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          size: 42,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _currentIndex > 0
                        ? () => _goTo(_currentIndex - 1)
                        : null,
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                    tooltip: 'Épisode précédent',
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSeasonSheet(context),
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -200 &&
                            _currentIndex < widget.episodes.length - 1) {
                          _goTo(_currentIndex + 1);
                        } else if (velocity > 200 && _currentIndex > 0) {
                          _goTo(_currentIndex - 1);
                        }
                      },
                      child: Text(
                        '${_episodeRef(current)}  ·  ${_globalEpLabel(current)}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _currentIndex < widget.episodes.length - 1
                        ? () => _goTo(_currentIndex + 1)
                        : null,
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                    tooltip: 'Épisode suivant',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.episodes.length,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: _buildEpisodeContent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonSheetContent extends StatefulWidget {
  const _SeasonSheetContent({
    required this.seasonNumbers,
    required this.initialSeason,
    required this.currentEpisode,
    required this.episodes,
    required this.watchedLocal,
    required this.onEpisodeTap,
  });

  final List<int> seasonNumbers;
  final int initialSeason;
  final Episode currentEpisode;
  final List<Episode> episodes;
  final Map<String, bool> watchedLocal;
  final void Function(Episode) onEpisodeTap;

  @override
  State<_SeasonSheetContent> createState() => _SeasonSheetContentState();
}

class _SeasonSheetContentState extends State<_SeasonSheetContent> {
  late int _shownSeason;

  @override
  void initState() {
    super.initState();
    _shownSeason = widget.initialSeason;
  }

  @override
  Widget build(BuildContext context) {
    final seasonIdx = widget.seasonNumbers.indexOf(_shownSeason);
    final hasPrev = seasonIdx > 0;
    final hasNext = seasonIdx < widget.seasonNumbers.length - 1;
    final seasonEpisodes = widget.episodes
        .where((ep) => ep.seasonNumber == _shownSeason)
        .toList();
    final seasonLabel = _shownSeason == 0 ? 'Spéciaux' : 'Saison $_shownSeason';
    final watchedCount = seasonEpisodes
        .where(
          (ep) =>
              widget.watchedLocal['${ep.seasonNumber}_${ep.episodeNumber}'] ??
              false,
        )
        .length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: hasPrev
                    ? () => setState(
                        () =>
                            _shownSeason = widget.seasonNumbers[seasonIdx - 1],
                      )
                    : null,
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      seasonLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$watchedCount / ${seasonEpisodes.length} vus',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: hasNext
                    ? () => setState(
                        () =>
                            _shownSeason = widget.seasonNumbers[seasonIdx + 1],
                      )
                    : null,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: seasonEpisodes.length,
            itemBuilder: (_, i) {
              final ep = seasonEpisodes[i];
              final k = '${ep.seasonNumber}_${ep.episodeNumber}';
              final isWatched = widget.watchedLocal[k] ?? false;
              final isCurrentEp =
                  ep.seasonNumber == widget.currentEpisode.seasonNumber &&
                  ep.episodeNumber == widget.currentEpisode.episodeNumber;
              return ListTile(
                dense: true,
                selected: isCurrentEp,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isWatched
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isWatched ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontWeight: isCurrentEp
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                onTap: () => widget.onEpisodeTap(ep),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _AddBottomBar extends StatelessWidget {
  const _AddBottomBar({required this.category, required this.onAdd});

  final WatchCategory category;
  final VoidCallback onAdd;

  String get _label {
    return switch (category) {
      WatchCategory.films => '+ Ajouter le film',
      WatchCategory.anime => '+ Ajouter l\'animé',
      _ => '+ Ajouter la série',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: GestureDetector(
        onTap: onAdd,
        child: Container(
          width: double.infinity,
          height: 59,
          color: const Color(0xFFFFD400),
          alignment: Alignment.center,
          child: Text(
            _label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xC7000000),
            ),
          ),
        ),
      ),
    );
  }
}
