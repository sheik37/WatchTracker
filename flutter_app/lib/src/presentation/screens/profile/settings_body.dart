import 'package:flutter/material.dart';

import '../../../data/repositories/media_repository.dart';
import '../applications_settings_page.dart';

/// "Paramètres" sub-screen of the profile screen: account tab (display
/// name/email/userId + navigation to change-password/delete-account) and
/// application-settings tab.
class SettingsBody extends StatelessWidget {
  const SettingsBody({
    super.key,
    required this.repository,
    required this.tabIndex,
    required this.onTabChange,
    required this.displayName,
    required this.email,
    required this.userId,
    required this.saving,
    required this.info,
    required this.error,
    required this.hasPendingDisplayNameChanges,
    required this.onEditDisplayName,
    required this.onSaveDisplayName,
    required this.onChangePasswordTap,
    required this.onDeleteAccountTap,
    required this.onLogout,
  });

  final MediaRepository repository;
  final int tabIndex;
  final ValueChanged<int> onTabChange;
  final String displayName;
  final String email;
  final String userId;
  final bool saving;
  final String? info;
  final String? error;
  final bool hasPendingDisplayNameChanges;
  final VoidCallback onEditDisplayName;
  final VoidCallback onSaveDisplayName;
  final VoidCallback onChangePasswordTap;
  final VoidCallback onDeleteAccountTap;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: tabIndex,
      child: Column(
        children: [
          TabBar(
            onTap: onTabChange,
            tabs: const [
              Tab(text: 'Compte'),
              Tab(text: 'Application'),
            ],
          ),
          Expanded(
            child: tabIndex == 0
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                112,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Card(
                                    elevation: 1,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Identification',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                      ),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    hasPendingDisplayNameChanges &&
                                                        !saving
                                                    ? onSaveDisplayName
                                                    : null,
                                                child: Text(
                                                  saving
                                                      ? 'Sauvegarde...'
                                                      : 'Sauvegarder',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        InkWell(
                                          onTap: onEditDisplayName,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            child: _AccountField(
                                              label: 'Nom d\'utilisateur',
                                              value: displayName,
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          child: _AccountField(
                                            label: 'Adresse e-mail',
                                            value: email,
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          child: _AccountField(
                                            label: 'Identifiant utilisateur',
                                            value: userId,
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        InkWell(
                                          onTap: onChangePasswordTap,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                const Expanded(
                                                  child: Text(
                                                    'Modifier le mot de passe',
                                                  ),
                                                ),
                                                Text(
                                                  '>',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (info != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      info!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ],
                                  if (error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 8,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton(
                                  onPressed: onLogout,
                                  child: const Text('Se déconnecter'),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: InkWell(
                                    onTap: onDeleteAccountTap,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Supprimer le compte',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : ApplicationsSettingsPage(repository: repository),
          ),
        ],
      ),
    );
  }
}

class _AccountField extends StatelessWidget {
  const _AccountField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
