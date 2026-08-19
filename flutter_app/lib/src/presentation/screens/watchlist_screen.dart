import 'package:flutter/material.dart';

import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import '../widgets/media_card.dart';
import 'details_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    required this.repository,
    required this.category,
  });

  final MediaRepository repository;
  final WatchCategory category;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late Future<List<WatchlistItem>> _future;
  final Map<WatchStatus, bool> _expanded = {};
  bool _staleExpanded = true;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.repository.watchlistVersion.addListener(_onWatchlistChanged);
    for (final s in WatchStatus.values) {
      _expanded[s] = true;
    }
  }

  @override
  void dispose() {
    widget.repository.watchlistVersion.removeListener(_onWatchlistChanged);
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.repository.getWatchlist(widget.category);
    });
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statusesForCategory(widget.category);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.category.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<List<WatchlistItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? [];
          final staleItems = widget.category == WatchCategory.films
              ? <WatchlistItem>[]
              : all.where((i) => _isStale(i)).toList();
          final regular = all.where((i) => !staleItems.contains(i)).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (widget.category != WatchCategory.films) ...[
                  _SectionHeader(
                    title: 'Pas regardé depuis un moment',
                    expanded: _staleExpanded,
                    onToggle: () =>
                        setState(() => _staleExpanded = !_staleExpanded),
                  ),
                  if (_staleExpanded)
                    staleItems.isEmpty
                        ? _emptySection()
                        : _SectionGrid(items: staleItems, onTap: _openDetails),
                ],
                for (final status in statuses) ...[
                  _SectionHeader(
                    title: status.label,
                    expanded: _expanded[status] ?? true,
                    onToggle: () => setState(
                      () => _expanded[status] = !(_expanded[status] ?? true),
                    ),
                  ),
                  if (_expanded[status] ?? true)
                    (() {
                      final items = regular
                          .where((i) => i.status == status)
                          .toList();
                      return items.isEmpty
                          ? _emptySection()
                          : _SectionGrid(items: items, onTap: _openDetails);
                    })(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Text(
          'Aucun titre dans cette sous-liste',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _openDetails(WatchlistItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DetailsScreen(repository: widget.repository, media: item.media),
      ),
    );
    _reload();
  }

  bool _isStale(WatchlistItem item) {
    final watchedAt = item.lastWatchedAt;
    if (watchedAt == null || item.watchedEpisodes <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch - watchedAt >
        const Duration(days: 30).inMilliseconds;
  }

  List<WatchStatus> _statusesForCategory(WatchCategory category) {
    return switch (category) {
      WatchCategory.films => [WatchStatus.notWatched, WatchStatus.watched],
      _ => [
        WatchStatus.notStarted,
        WatchStatus.inProgress,
        WatchStatus.upToDate,
        WatchStatus.completed,
      ],
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.items, required this.onTap});

  final List<WatchlistItem> items;
  final Future<void> Function(WatchlistItem) onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <List<WatchlistItem>>[];
    for (var i = 0; i < items.length; i += 3) {
      rows.add(items.sublist(i, i + 3 > items.length ? items.length : i + 3));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...row.map(
                  (item) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _WatchlistCard(item: item, onTap: onTap),
                    ),
                  ),
                ),
                if (row.length < 3)
                  ...List.generate(
                    3 - row.length,
                    (_) => const Expanded(child: SizedBox()),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({required this.item, required this.onTap});

  final WatchlistItem item;
  final Future<void> Function(WatchlistItem) onTap;

  Color? _progressColor() {
    return switch (item.status) {
      WatchStatus.inProgress => const Color(0xFFFFC107),
      WatchStatus.upToDate => const Color(0xFF4CAF50),
      WatchStatus.completed => const Color(0xFF9C27B0),
      WatchStatus.watched => const Color(0xFF9C27B0),
      _ => null,
    };
  }

  double _progress() {
    if (item.status == WatchStatus.inProgress) {
      if (item.totalEpisodes <= 0) return 0;
      return (item.watchedEpisodes / item.totalEpisodes).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final progressColor = _progressColor();
    final showProgress =
        item.media.mediaType != MediaType.movie &&
        item.status != WatchStatus.notStarted &&
        item.status != WatchStatus.notWatched &&
        progressColor != null;

    return MediaCard(
      posterPath: item.media.posterPath,
      title: item.media.title,
      onTap: () => onTap(item),
      bottomContent: showProgress
          ? Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress(),
                minHeight: 6,
                color: progressColor,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
            )
          : null,
    );
  }
}
