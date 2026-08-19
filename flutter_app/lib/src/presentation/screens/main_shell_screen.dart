import 'package:flutter/material.dart';

import '../../data/models/auth_models.dart';
import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'watchlist_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.onLogout,
    required this.onProfileUpdated,
  });

  final MediaRepository repository;
  final UserProfile? profile;
  final Future<void> Function() onLogout;
  final ValueChanged<UserProfile> onProfileUpdated;

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;
  bool _hideNavigationBar = false;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      WatchlistScreen(
        repository: widget.repository,
        category: WatchCategory.series,
      ),
      WatchlistScreen(
        repository: widget.repository,
        category: WatchCategory.films,
      ),
      WatchlistScreen(
        repository: widget.repository,
        category: WatchCategory.anime,
      ),
      SearchScreen(repository: widget.repository),
      ProfileScreen(
        repository: widget.repository,
        profile: widget.profile,
        onLogout: widget.onLogout,
        onProfileUpdated: widget.onProfileUpdated,
        onSubScreenVisibilityChanged: (isVisible) {
          if (_hideNavigationBar != isVisible) {
            setState(() {
              _hideNavigationBar = isVisible;
            });
          }
        },
      ),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: _index == 3,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _hideNavigationBar
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() {
                  _index = value;
                });
              },
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  label: 'Series',
                ),
                NavigationDestination(
                  icon: Icon(Icons.movie_outlined),
                  label: 'Films',
                ),
                NavigationDestination(
                  icon: Icon(Icons.live_tv_outlined),
                  label: 'Anime',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Recherche',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profil',
                ),
              ],
            ),
    );
  }
}
