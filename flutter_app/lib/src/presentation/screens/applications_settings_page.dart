import 'package:flutter/material.dart';

import '../../data/repositories/media_repository.dart';

class ApplicationsSettingsPage extends StatefulWidget {
  const ApplicationsSettingsPage({super.key, required this.repository});

  final MediaRepository repository;

  @override
  State<ApplicationsSettingsPage> createState() =>
      _ApplicationsSettingsPageState();
}

class _ApplicationsSettingsPageState extends State<ApplicationsSettingsPage> {
  late Future<int> _cacheSize;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  void _refreshCacheSize() {
    _cacheSize = widget.repository.metadataCache.getCacheSizeForUI();
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vider le cache'),
        content: const Text(
          'Êtes-vous sûr ? Les données en cache seront supprimées.\n'
          'Les données seront rechargées depuis le réseau à la prochaine consultation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vider', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await widget.repository.clearMetadataCache();
      if (mounted) {
        setState(() {
          _clearing = false;
          _refreshCacheSize();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✓ Cache vidé')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _clearing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('✗ Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Applications')),
      body: ListView(
        children: [
          // Cache section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cache Hors-ligne',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Taille du cache'),
                          FutureBuilder<int>(
                            future: _cacheSize,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Text(
                                  _formatBytes(snapshot.data ?? 0),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey.shade600),
                                );
                              }
                              return SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.grey.shade400,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<int>(
                        future: _cacheSize,
                        builder: (context, snapshot) {
                          final bytes = snapshot.data ?? 0;
                          final maxBytes = 50 * 1024 * 1024; // 50 MB
                          final percent = (bytes / maxBytes).clamp(0.0, 1.0);

                          return Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percent,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation(
                                    percent > 0.8 ? Colors.orange : Colors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Max: 50 MB (${(percent * 100).toStringAsFixed(1)}% utilisé)',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Durée de validité: 30 jours',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _clearing ? null : _clearCache,
                          icon: _clearing
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          label: Text(
                            _clearing
                                ? 'Suppression en cours...'
                                : 'Vider le cache',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'À propos du cache',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '• Le cache stocke les données des séries/films consultés\n'
                    '• Les données expirent après 30 jours\n'
                    '• Le cache est limité à 50 MB (ancien contenu supprimé automatiquement)\n'
                    '• Vous pouvez marquer des épisodes comme vus même hors-ligne\n'
                    '• Les actions seront synchronisées quand la connexion sera rétablie',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
