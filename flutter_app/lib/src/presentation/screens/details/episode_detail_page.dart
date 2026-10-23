// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/episode_watch_key.dart';
import '../../../data/models/details_models.dart';
import '../../../data/repositories/media_repository.dart';
import 'rewatch_choice.dart';
import 'watch_history_dialog.dart';
class EpisodeDetailPage extends StatefulWidget {
  const EpisodeDetailPage({
    super.key,
    required this.episodes,
    required this.initialIndex,
    required this.mediaId,
    required this.repository,
    required this.watchedEpisodes,
    required this.episodeWatchedAt,
    required this.episodeViewCounts,
    required this.seasonOffsets,
    required this.seriesTitle,
    required this.isReleasedCheck,
    required this.onToggleWatched,
    required this.getProgress,
  });

  final List<Episode> episodes;
  final int initialIndex;
  final int mediaId;
  final MediaRepository repository;
  final Set<String> watchedEpisodes;
  final Map<String, int> episodeWatchedAt;
  final Map<String, int> episodeViewCounts;
  final Map<int, int> seasonOffsets;
  final String seriesTitle;
  final bool Function(Episode) isReleasedCheck;
  final Future<void> Function(Episode, bool) onToggleWatched;

  /// Returns the current progress from the parent after a toggle.
  final ({
    Set<String> watched,
    Map<String, int> watchedAt,
    Map<String, int> viewCounts,
  })
  Function()
  getProgress;

  @override
  State<EpisodeDetailPage> createState() => _EpisodeDetailPageState();
}

class _EpisodeDetailPageState extends State<EpisodeDetailPage> {
  late int _currentIndex;
  late PageController _pageController;
  late Map<String, bool> _watchedLocal;
  late Map<String, int> _watchedAtLocal;
  late Map<String, int> _viewCountsLocal;
  late Map<String, List<int>> _episodeWatchDates;

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
    _viewCountsLocal = Map<String, int>.from(widget.episodeViewCounts);
    for (final entry in _watchedLocal.entries) {
      if (entry.value) {
        _viewCountsLocal.putIfAbsent(entry.key, () => 1);
      }
    }
    _episodeWatchDates = {};
    _loadWatchDates();
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
    _viewCountsLocal
      ..clear()
      ..addAll(progress.viewCounts);
    for (final entry in _watchedLocal.entries) {
      if (entry.value) {
        _viewCountsLocal.putIfAbsent(entry.key, () => 1);
      }
    }
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
    final isWatched = _watchedLocal[k] ?? false;
    var target = !isWatched;
    if (isWatched) {
      final choice = await _showRewatchDialog();
      if (choice == null) return;
      if (choice == RewatchChoice.rewatch) {
        target = true;
      } else {
        final dates = _episodeWatchDates[k] ?? const <int>[];
        if (dates.length > 1) {
          final selected = await _showWatchDatePickerDialog(dates);
          if (selected == null) return;
          await _deleteEpisodeWatchDate(ep, selected);
          return;
        }
        target = false;
      }
    }
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _watchedLocal[k] = target;
      if (target && !isWatched) {
        _watchedAtLocal[k] = nowMillis;
      } else if (!target) {
        _watchedAtLocal.remove(k);
      } else if (target && isWatched) {
        _watchedAtLocal[k] = _watchedAtLocal[k] ?? nowMillis;
      }
      if (target && isWatched) {
        _viewCountsLocal[k] = (_viewCountsLocal[k] ?? 1) + 1;
      } else if (target) {
        _viewCountsLocal[k] = 1;
      } else {
        _viewCountsLocal.remove(k);
      }
    });
    await widget.onToggleWatched(ep, target);
    if (mounted) {
      await _loadWatchDates();
      setState(_syncFromProgress);
    }
  }

  Future<RewatchChoice?> _showRewatchDialog() {
    final key = '${_current.seasonNumber}_${_current.episodeNumber}';
    final dates = _episodeWatchDates[key] ?? const <int>[];
    return showDialog<RewatchChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Épisode déjà vu'),
        content: const Text(
          'Voulez-vous le marquer non vu ou ajouter une revue (+1 vue) ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.unwatch),
            child: Text(
              dates.length > 1 ? 'Supprimer un visionnage' : 'Marquer non vu',
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.rewatch),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Revoir (+1 vue)'),
          ),
        ],
      ),
    );
  }

  Future<int?> _showWatchDatePickerDialog(List<int> dates) {
    if (dates.isEmpty) return Future<int?>.value(null);
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        title: const Text('Supprimer un visionnage'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final watchedAt in dates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${DateTime.fromMillisecondsSinceEpoch(watchedAt).day.toString().padLeft(2, '0')}/${DateTime.fromMillisecondsSinceEpoch(watchedAt).month.toString().padLeft(2, '0')}/${DateTime.fromMillisecondsSinceEpoch(watchedAt).year}',
                    ),
                    trailing: const Icon(Icons.delete_outline_rounded),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          backgroundColor: Theme.of(confirmCtx)
                              .colorScheme
                              .surfaceContainerHigh,
                          title: const Text('Confirmer la suppression'),
                          content: Text(
                            'Supprimer le visionnage du ${DateTime.fromMillisecondsSinceEpoch(watchedAt).day.toString().padLeft(2, '0')}/${DateTime.fromMillisecondsSinceEpoch(watchedAt).month.toString().padLeft(2, '0')}/${DateTime.fromMillisecondsSinceEpoch(watchedAt).year} ?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(true),
                              icon: const Icon(Icons.delete_rounded, size: 18),
                              label: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        Navigator.of(ctx).pop(watchedAt);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEpisodeWatchDate(Episode ep, int watchedAtMillis) async {
    final key = '${ep.seasonNumber}_${ep.episodeNumber}';
    final previousWatched = Map<String, int>.from(_watchedAtLocal);
    final previousCounts = Map<String, int>.from(_viewCountsLocal);
    final previousSelected = Map<String, bool>.from(_watchedLocal);
    final remainingDates = (_episodeWatchDates[key] ?? const <int>[])
        .where((millis) => millis != watchedAtMillis)
        .toList();
    setState(() {
      if (remainingDates.isEmpty) {
        _watchedLocal[key] = false;
        _watchedAtLocal.remove(key);
        _viewCountsLocal.remove(key);
      } else {
        _watchedLocal[key] = true;
        _watchedAtLocal[key] = remainingDates.first;
        _viewCountsLocal[key] = remainingDates.length;
      }
    });
    try {
      await widget.repository.deleteEpisodeWatchEvent(
        mediaId: widget.mediaId,
        seasonNumber: ep.seasonNumber,
        episodeNumber: ep.episodeNumber,
        watchedAtMillis: watchedAtMillis,
      );
      final progress = await widget.repository.getEpisodeProgress(
        widget.mediaId,
      );
      final watchedSet = progress
          .where((p) => p.isWatched)
          .map((p) => '${p.seasonNumber}_${p.episodeNumber}')
          .toSet();
      final watchedAtMap = {
        for (final p in progress.where((p) => p.isWatched))
          '${p.seasonNumber}_${p.episodeNumber}': p.updatedAtMillis ?? 0,
      };
      final viewCounts = Map<String, int>.from(
        await widget.repository.getEpisodeViewCounts(widget.mediaId),
      );
      if (mounted) {
        final refreshedDates = <String, List<int>>{};
        for (final item in widget.episodes) {
          refreshedDates['${item.seasonNumber}_${item.episodeNumber}'] =
              await widget.repository.getEpisodeWatchDates(
                mediaId: widget.mediaId,
                seasonNumber: item.seasonNumber,
                episodeNumber: item.episodeNumber,
              );
        }
        setState(() {
          _watchedLocal = {
            for (final episode in widget.episodes)
              '${episode.seasonNumber}_${episode.episodeNumber}': watchedSet
                  .contains('${episode.seasonNumber}_${episode.episodeNumber}'),
          };
          _watchedAtLocal
            ..clear()
            ..addAll(watchedAtMap);
          _viewCountsLocal
            ..clear()
            ..addAll(viewCounts);
          _episodeWatchDates
            ..clear()
            ..addAll(refreshedDates);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedLocal = previousSelected;
        _watchedAtLocal
          ..clear()
          ..addAll(previousWatched);
        _viewCountsLocal
          ..clear()
          ..addAll(previousCounts);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer ce visionnage: $e')),
      );
    }
  }

  Future<void> _loadWatchDates() async {
    for (final ep in widget.episodes) {
      try {
        final dates = await widget.repository.getEpisodeWatchDates(
          mediaId: widget.mediaId,
          seasonNumber: ep.seasonNumber,
          episodeNumber: ep.episodeNumber,
        );
        final key = '${ep.seasonNumber}_${ep.episodeNumber}';
        if (mounted) {
          setState(() {
            _episodeWatchDates[key] = dates;
          });
        }
      } catch (_) {}
    }
  }

  void _showWatchHistoryDialog(Episode ep) {
    final dates = _episodeWatchDates[ep.watchKey] ?? [];
    if (dates.isEmpty) return;

    showWatchHistoryDialog(
      context: context,
      dates: dates,
      onDeleteDate: (ms) => _deleteEpisodeWatchDate(ep, ms),
    );
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
    final viewCount = _viewCountsLocal[k] ?? (isWatched ? 1 : 0);
    final rewatchCount = viewCount > 1 ? viewCount : null;
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
              if (rewatchCount != null)
                ActionChip(
                  avatar: const Icon(Icons.replay_rounded, size: 16),
                  label: Text('x$rewatchCount vues'),
                  onPressed: () => _showWatchHistoryDialog(ep),
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
                        placeholder: (_, _) => Container(
                          height: 220,
                          width: double.infinity,
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          height: 220,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_rounded,
                              size: 42,
                            ),
                          ),
                        ),
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
