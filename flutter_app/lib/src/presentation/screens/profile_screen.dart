import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/app_update_service.dart';
import '../../data/models/auth_models.dart';
import '../../data/repositories/media_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.onLogout,
    required this.onSubScreenVisibilityChanged,
    required this.onProfileUpdated,
  });

  final MediaRepository repository;
  final UserProfile? profile;
  final Future<void> Function() onLogout;
  final ValueChanged<bool> onSubScreenVisibilityChanged;
  final ValueChanged<UserProfile> onProfileUpdated;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const MethodChannel _systemChannel = MethodChannel(
    'watchtracker/system',
  );
  bool _showSettings = false;
  bool _showChangePassword = false;
  bool _showDeleteAccount = false;
  bool _showAbout = false;
  int _settingsTab = 0;

  late final TextEditingController _displayNameCtrl = TextEditingController(
    text: _effectiveDisplayName,
  );
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _savingDisplayName = false;
  String? _displayNameError;
  String? _displayNameInfo;
  String _lastSavedDisplayName = '';

  bool _changingPassword = false;
  String? _passwordError;

  bool _deletingAccount = false;
  String? _deleteError;

  final AppUpdateService _appUpdateService = AppUpdateService();
  bool _checkingForUpdates = false;
  String? _appUpdateError;
  AppUpdateResult? _appUpdateResult;

  @override
  void initState() {
    super.initState();
    _lastSavedDisplayName = _effectiveDisplayName;
  }

  String get _userIdAsDefaultName =>
      widget.profile?.userId.toString() ?? 'Non disponible';

  String get _effectiveDisplayName {
    final value = widget.profile?.displayName?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return _userIdAsDefaultName;
  }

  String get _baseDisplayName {
    final saved = _lastSavedDisplayName.trim();
    if (saved.isNotEmpty) return saved;
    return _effectiveDisplayName;
  }

  String get _accountEmail => widget.profile?.email.trim().isNotEmpty == true
      ? widget.profile!.email.trim()
      : 'Non disponible';

  String get _pendingDisplayName {
    final value = _displayNameCtrl.text.trim();
    return value.isEmpty ? _userIdAsDefaultName : value;
  }

  bool get _hasPendingDisplayNameChanges =>
      _pendingDisplayName != _baseDisplayName;

  bool get _subScreenVisible =>
      _showSettings || _showChangePassword || _showDeleteAccount || _showAbout;

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentProfileName = widget.profile?.displayName?.trim();
    final previousProfileName = oldWidget.profile?.displayName?.trim();
    if (currentProfileName != previousProfileName) {
      final nextSavedName =
          (currentProfileName != null && currentProfileName.isNotEmpty)
          ? currentProfileName
          : _userIdAsDefaultName;
      _lastSavedDisplayName = nextSavedName;
    }
    if (!_hasPendingDisplayNameChanges &&
        oldWidget.profile?.displayName != widget.profile?.displayName) {
      _displayNameCtrl.text = _baseDisplayName;
    }
  }

  void _notifySubScreenVisibility() {
    widget.onSubScreenVisibilityChanged(_subScreenVisible);
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingForUpdates = true;
      _appUpdateError = null;
    });
    try {
      final result = await _appUpdateService.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _appUpdateResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appUpdateError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _checkingForUpdates = false);
      }
    }
  }

  Future<void> _openUpdateDownload() async {
    final url = _appUpdateResult?.downloadUrl?.trim();
    if (url == null || url.isEmpty) {
      setState(() {
        _appUpdateError =
            'Aucun lien de téléchargement configuré pour cette plateforme.';
      });
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      setState(() {
        _appUpdateError = 'Lien de mise à jour invalide.';
      });
      return;
    }
    var opened = false;
    try {
      opened =
          await _systemChannel.invokeMethod<bool>('openUrl', <String, dynamic>{
            'url': uri.toString(),
          }) ??
          false;
    } on PlatformException {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() {
        _appUpdateError =
            'Impossible d\'ouvrir automatiquement le lien de mise à jour.';
      });
    }
  }

  @override
  void dispose() {
    _appUpdateService.dispose();
    _displayNameCtrl.dispose();
    _curPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _back() async {
    if (_showChangePassword) {
      setState(() => _showChangePassword = false);
      _notifySubScreenVisibility();
      return;
    }
    if (_showDeleteAccount) {
      setState(() => _showDeleteAccount = false);
      _notifySubScreenVisibility();
      return;
    }
    if (_showAbout) {
      setState(() => _showAbout = false);
      _notifySubScreenVisibility();
      return;
    }
    if (_showSettings && _settingsTab == 0 && _hasPendingDisplayNameChanges) {
      final discard = await _showDiscardChangesDialog();
      if (discard == true && mounted) {
        setState(() {
          _displayNameCtrl.text = _baseDisplayName;
          _displayNameError = null;
          _displayNameInfo = null;
          _showSettings = false;
        });
        _notifySubScreenVisibility();
      }
      return;
    }
    if (mounted) {
      setState(() => _showSettings = false);
      _notifySubScreenVisibility();
    }
  }

  Future<bool?> _showDiscardChangesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler les modifications ?'),
        content: const Text(
          'Cette page contient des modifications non enregistrées. Si tu quittes maintenant, elles seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Rester'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter sans enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDisplayName() async {
    var draftValue = _pendingDisplayName;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Modifier le nom d\'utilisateur'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextFormField(
            initialValue: draftValue,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (value) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop(value.trim());
            },
            decoration: const InputDecoration(
              labelText: 'Nom d\'utilisateur',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop(draftValue.trim());
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _displayNameCtrl.text = result.isEmpty ? _userIdAsDefaultName : result;
      _displayNameInfo = null;
      _displayNameError = null;
    });
  }

  Future<void> _saveDisplayName() async {
    setState(() {
      _savingDisplayName = true;
      _displayNameError = null;
      _displayNameInfo = null;
    });
    try {
      final normalized = _displayNameCtrl.text.trim();
      final valueToSave =
          normalized.isEmpty || normalized == _userIdAsDefaultName
          ? null
          : normalized;
      final updated = await widget.repository.updateCurrentUserDisplayName(
        valueToSave,
      );
      if (mounted) {
        final savedName = (updated?.displayName?.trim().isNotEmpty == true)
            ? updated!.displayName!.trim()
            : (normalized.isEmpty ? _userIdAsDefaultName : normalized);

        _lastSavedDisplayName = savedName;
        _displayNameCtrl.text = savedName;

        if (updated != null) {
          widget.onProfileUpdated(updated);
        }

        setState(() => _displayNameInfo = 'Nom mis à jour');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _displayNameError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _savingDisplayName = false);
      }
    }
  }

  Future<void> _changePassword() async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      setState(
        () => _passwordError = 'Les mots de passe ne correspondent pas.',
      );
      return;
    }
    setState(() {
      _changingPassword = true;
      _passwordError = null;
    });
    try {
      await widget.repository.changePassword(
        _curPassCtrl.text,
        _newPassCtrl.text,
      );
      if (mounted) {
        await widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _passwordError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _changingPassword = false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    setState(() {
      _deletingAccount = true;
      _deleteError = null;
    });
    try {
      await widget.repository.deleteCurrentUserAccount();
      await widget.repository.clearLocalSessionData();
      if (mounted) {
        await widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleteError = e.toString();
          _deletingAccount = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _subScreenVisible
        ? _showDeleteAccount
              ? ''
              : _showAbout
              ? 'À propos'
              : _showChangePassword
              ? 'Modifier le mot de passe'
              : 'Paramètres'
        : 'Profil';

    return PopScope(
      canPop: !_subScreenVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(title),
          centerTitle: _subScreenVisible,
          leading: _subScreenVisible
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _back,
                )
              : null,
          automaticallyImplyLeading: false,
          actions: _subScreenVisible
              ? null
              : [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      if (value == 'settings') {
                        setState(() {
                          _settingsTab = 0;
                          _showSettings = true;
                        });
                        _notifySubScreenVisibility();
                      } else if (value == 'about') {
                        setState(() => _showAbout = true);
                        _notifySubScreenVisibility();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings_rounded),
                            SizedBox(width: 12),
                            Text('Paramètres'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'about',
                        child: Row(
                          children: [
                            Icon(Icons.info_rounded),
                            SizedBox(width: 12),
                            Text('À propos'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        body: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_showChangePassword) {
      return _ChangePasswordBody(
        currentController: _curPassCtrl,
        newController: _newPassCtrl,
        confirmController: _confirmPassCtrl,
        loading: _changingPassword,
        error: _passwordError,
        onChanged: () => setState(() {}),
        onSubmit: _changePassword,
      );
    }
    if (_showDeleteAccount) {
      return _DeleteAccountBody(
        loading: _deletingAccount,
        error: _deleteError,
        onDelete: _deleteAccount,
      );
    }
    if (_showAbout) {
      return _AboutBody(
        version: '${AppConfig.appVersion}+${AppConfig.appBuildNumber}',
        checkingForUpdates: _checkingForUpdates,
        appUpdateError: _appUpdateError,
        appUpdateResult: _appUpdateResult,
        onCheckForUpdates: _checkForUpdates,
        onOpenUpdateDownload: _openUpdateDownload,
      );
    }
    if (_showSettings) {
      return _SettingsBody(
        tabIndex: _settingsTab,
        onTabChange: (value) => setState(() => _settingsTab = value),
        displayName: _pendingDisplayName,
        email: _accountEmail,
        userId: _userIdAsDefaultName,
        saving: _savingDisplayName,
        info: _displayNameInfo,
        error: _displayNameError,
        hasPendingDisplayNameChanges: _hasPendingDisplayNameChanges,
        onEditDisplayName: _editDisplayName,
        onSaveDisplayName: _saveDisplayName,
        onChangePasswordTap: () {
          setState(() {
            _curPassCtrl.clear();
            _newPassCtrl.clear();
            _confirmPassCtrl.clear();
            _passwordError = null;
            _showChangePassword = true;
          });
          _notifySubScreenVisibility();
        },
        onDeleteAccountTap: () {
          setState(() {
            _deleteError = null;
            _deletingAccount = false;
            _showDeleteAccount = true;
          });
          _notifySubScreenVisibility();
        },
        onLogout: widget.onLogout,
      );
    }
    return _ProfileMainBody(
      displayName: _effectiveDisplayName,
      email: _accountEmail,
      backendUrl: AppConfig.backendBaseUrl.trim().isEmpty
          ? 'Non configurée'
          : AppConfig.backendBaseUrl,
    );
  }
}

class _ProfileMainBody extends StatelessWidget {
  const _ProfileMainBody({
    required this.displayName,
    required this.email,
    required this.backendUrl,
  });

  final String displayName;
  final String email;
  final String backendUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informations du compte',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Nom d\'utilisateur : $displayName'),
                Text('Adresse e-mail : $email'),
                Text('API backend : $backendUrl'),
                const Text('Session : connectée'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
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
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      Card(
                        elevation: 1,
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Application'),
                              SizedBox(height: 8),
                              Text(
                                'Configuration de l\'application bientôt disponible.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordBody extends StatelessWidget {
  const _ChangePasswordBody({
    required this.currentController,
    required this.newController,
    required this.confirmController,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController currentController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final bool loading;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        currentController.text.isNotEmpty &&
        newController.text.isNotEmpty &&
        confirmController.text.isNotEmpty &&
        !loading;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: currentController,
          obscureText: true,
          enabled: !loading,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Mot de passe actuel',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newController,
          obscureText: true,
          enabled: !loading,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Nouveau mot de passe',
            border: OutlineInputBorder(),
          ),
        ),
        _PasswordCriteriaChecklist(password: newController.text),
        const SizedBox(height: 12),
        TextField(
          controller: confirmController,
          obscureText: true,
          enabled: !loading,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(
            labelText: 'Confirmer le mot de passe',
            border: OutlineInputBorder(),
          ),
        ),
        _PasswordCriteriaChecklist(password: confirmController.text),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canSubmit ? onSubmit : null,
            child: Text(
              loading ? 'Modification...' : 'Modifier le mot de passe',
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteAccountBody extends StatelessWidget {
  const _DeleteAccountBody({
    required this.loading,
    required this.error,
    required this.onDelete,
  });

  final bool loading;
  final String? error;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La suppression du compte est définitive. Toutes vos données liées à ce compte (profil, suivi de contenus, progression des épisodes et sessions actives) seront supprimées de manière irréversible.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Conformément aux obligations réglementaires, certaines traces techniques strictement nécessaires à la sécurité et à la conformité peuvent être conservées pour une durée limitée.',
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onDelete,
              child: Text(loading ? 'Suppression...' : 'Supprimer mon compte'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutBody extends StatelessWidget {
  const _AboutBody({
    required this.version,
    required this.checkingForUpdates,
    required this.appUpdateError,
    required this.appUpdateResult,
    required this.onCheckForUpdates,
    required this.onOpenUpdateDownload,
  });

  final String version;
  final bool checkingForUpdates;
  final String? appUpdateError;
  final AppUpdateResult? appUpdateResult;
  final Future<void> Function() onCheckForUpdates;
  final Future<void> Function() onOpenUpdateDownload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Image.asset(
            'assets/images/watchtracker_logo.png',
            width: 120,
            height: 120,
            errorBuilder: (_, _, _) => const Icon(
              Icons.movie_filter_rounded,
              size: 120,
              color: Color(0xFF006A6A),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(version),
                const Divider(height: 24),
                Text(
                  'Mises à jour',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  appUpdateResult == null
                      ? 'Appuie sur "Vérifier les mises à jour" pour récupérer la dernière version.'
                      : 'Version installée : ${appUpdateResult!.currentLabel}',
                ),
                if (appUpdateResult != null) ...[
                  const SizedBox(height: 4),
                  Text('Dernière version : ${appUpdateResult!.latestLabel}'),
                ],
                if (appUpdateResult?.releaseNotes != null &&
                    appUpdateResult!.releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(appUpdateResult!.releaseNotes!),
                ],
                if (appUpdateError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    appUpdateError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: checkingForUpdates
                      ? null
                      : () {
                          onCheckForUpdates();
                        },
                  child: Text(
                    checkingForUpdates
                        ? 'Vérification...'
                        : 'Vérifier les mises à jour',
                  ),
                ),
                if (appUpdateResult?.isUpdateAvailable == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton(
                      onPressed: () {
                        onOpenUpdateDownload();
                      },
                      child: const Text('Télécharger la mise à jour'),
                    ),
                  ),
                if (appUpdateResult != null &&
                    appUpdateResult!.isUpdateAvailable == false) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tu as déjà la dernière version.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordCriteriaChecklist extends StatelessWidget {
  const _PasswordCriteriaChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final checks = <(String, bool)>[
      ('10 caractères minimum', password.length >= 10),
      ('au moins une minuscule', password.contains(RegExp(r'[a-z]'))),
      ('au moins une majuscule', password.contains(RegExp(r'[A-Z]'))),
      ('au moins un chiffre', password.contains(RegExp(r'[0-9]'))),
      ('au moins un symbole', password.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: checks.map((entry) {
          final (label, isValid) = entry;
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${isValid ? "• ✓ " : "• ✗ "}$label',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isValid
                    ? const Color(0xFF2E7D32)
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }).toList(),
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
