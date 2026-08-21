import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/details_models.dart';
import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import '../widgets/media_card.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final MediaRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _discoveryScrollCtrl = ScrollController();
  List<Media> _discoveryPool = [];
  int _visibleDiscoveryCount = 0;
  List<Media> _results = [];
  Set<String> _tracked = {};
  bool _loading = false;
  String? _error;
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  static const int _discoveryBatchSize = 8;
  static const double _discoveryLoadThreshold = 320;

  @override
  void initState() {
    super.initState();
    _discoveryScrollCtrl.addListener(_maybeLoadMoreDiscovery);
    _loadDiscovery();
    _ctrl.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _discoveryScrollCtrl.removeListener(_maybeLoadMoreDiscovery);
    _discoveryScrollCtrl.dispose();
    _ctrl.removeListener(_onSearchTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final query = _ctrl.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      _searchRequestId++;
      setState(() {
        _searching = false;
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _search(query);
    });
  }

  Future<void> _loadDiscovery() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.repository.getDiscoveryMedia(),
        widget.repository.getTrackedMediaKeys(),
      ]);
      final discovery = values[0] as List<Media>;
      final tracked = values[1] as Set<String>;
      if (!mounted) return;
      setState(() {
        _discoveryPool = discovery;
        _visibleDiscoveryCount = discovery.isEmpty
            ? 0
            : discovery.length < _discoveryBatchSize
            ? discovery.length
            : _discoveryBatchSize;
        _tracked = tracked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _maybeLoadMoreDiscovery() {
    if (_searching || _loading) return;
    if (_visibleDiscoveryCount >= _discoveryPool.length) return;
    if (!_discoveryScrollCtrl.hasClients) return;
    if (_discoveryScrollCtrl.position.extentAfter > _discoveryLoadThreshold) {
      return;
    }
    _loadMoreDiscovery();
  }

  void _loadMoreDiscovery() {
    if (_visibleDiscoveryCount >= _discoveryPool.length) {
      return;
    }
    final nextCount = (_visibleDiscoveryCount + _discoveryBatchSize).clamp(
      0,
      _discoveryPool.length,
    );
    setState(() {
      _visibleDiscoveryCount = nextCount;
    });
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    final requestId = ++_searchRequestId;
    if (trimmed.isEmpty) {
      setState(() {
        _searching = false;
        _results = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _searching = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.repository.searchMedia(trimmed),
        widget.repository.getTrackedMediaKeys(),
      ]);
      final results = values[0] as List<Media>;
      final tracked = values[1] as Set<String>;
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _results = results;
        _tracked = tracked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow(Media media) async {
    final key = _mediaKey(media);
    final wasTracked = _tracked.contains(key);
    setState(() {
      if (wasTracked) {
        _tracked.remove(key);
      } else {
        _tracked.add(key);
      }
    });
    try {
      final existingCategories = await widget.repository
          .getTrackedCategoriesForMedia(media.id, media.mediaType);
      if (existingCategories.isNotEmpty) {
        for (final category in existingCategories) {
          await widget.repository.removeFromWatchlist(media, category);
        }
        final refreshedTracked = await widget.repository.getTrackedMediaKeys();
        if (!mounted) return;
        setState(() => _tracked = refreshedTracked);
      } else {
        final addPreset = await _buildAddPreset(media);
        final cat = addPreset.$1;
        final totalEpisodes = addPreset.$2;
        await widget.repository.addToWatchlist(
          media,
          cat,
          cat.defaultStatus(),
          totalEpisodes,
        );
        final refreshedTracked = await widget.repository.getTrackedMediaKeys();
        if (!mounted) return;
        setState(() => _tracked = refreshedTracked);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour ce suivi: $e')),
      );
      setState(() {
        if (wasTracked) {
          _tracked.add(key);
        } else {
          _tracked.remove(key);
        }
      });
    }
  }

  String _mediaKey(Media media) => '${media.mediaType.value}_${media.id}';

  Future<(WatchCategory, int)> _buildAddPreset(Media media) async {
    if (media.mediaType == MediaType.movie) {
      return (WatchCategory.films, 1);
    }
    final details = await widget.repository.getTvDetailsFast(media.id);
    final category = details.watchCategory();
    final totalEpisodes = _sumRegularSeasonEpisodes(details);
    return (category, totalEpisodes);
  }

  int _sumRegularSeasonEpisodes(MediaDetails details) {
    return details.seasons
        .where((s) => s.seasonNumber != 0)
        .fold(0, (acc, s) => acc + s.episodeCount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _ctrl,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Rechercher des films, séries...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() {
                              _searching = false;
                              _results = [];
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
              ),
            ),
          ),
          if (_error != null)
            Expanded(
              child: Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_loading &&
              (_searching ? _results.isEmpty : _discoveryPool.isEmpty))
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_searching && _results.isEmpty && !_loading)
            const Expanded(
              child: Center(
                child: Text('Il n\'y a aucun résultat pour cette recherche'),
              ),
            )
          else if (_searching)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final media = _results[i];
                  final tracked = _tracked.contains(_mediaKey(media));
                  return _SearchRow(
                    media: media,
                    tracked: tracked,
                    onTap: () => _openDetails(media),
                    onToggle: () => _toggleFollow(media),
                  );
                },
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                controller: _discoveryScrollCtrl,
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.7,
                ),
                itemCount: _visibleDiscoveryCount,
                itemBuilder: (context, i) {
                  final media = _discoveryPool[i];
                  final tracked = _tracked.contains(_mediaKey(media));
                  return Stack(
                    children: [
                      MediaCard(
                        posterPath: media.posterPath,
                        title: media.title,
                        onTap: () => _openDetails(media),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: FollowCheckbox(
                            checked: tracked,
                            onToggle: () => _toggleFollow(media),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openDetails(Media media) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DetailsScreen(repository: widget.repository, media: media),
      ),
    );
    final tracked = await widget.repository.getTrackedMediaKeys();
    if (!mounted) return;
    setState(() {
      _tracked = tracked;
    });
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.media,
    required this.tracked,
    required this.onTap,
    required this.onToggle,
  });

  final Media media;
  final bool tracked;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                height: 76,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: media.posterPath != null
                      ? CachedNetworkImage(
                          imageUrl: media.posterPath!,
                          fit: BoxFit.cover,
                        )
                      : Container(color: Colors.grey.shade700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  media.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FollowCheckbox(checked: tracked, onToggle: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}
