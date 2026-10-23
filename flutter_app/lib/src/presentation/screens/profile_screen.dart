import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/app_update_launcher.dart';
import '../../core/app_update_service.dart';
import '../../data/models/auth_models.dart';
import '../../data/repositories/media_repository.dart';
import 'profile/about_body.dart';
import 'profile/change_password_body.dart';
import 'profile/delete_account_body.dart';
import 'profile/profile_main_body.dart';
import 'profile/settings_body.dart';

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
  final AppUpdateLauncher _appUpdateLauncher = AppUpdateLauncher();
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
    try {
      await _appUpdateLauncher.openDownload(_appUpdateResult?.downloadUrl);
    } on AppUpdateLaunchException catch (e) {
      if (!mounted) return;
      setState(() => _appUpdateError = e.message);
    }
  }

  Future<void> _openReleaseNotes() async {
    try {
      await _appUpdateLauncher.openReleaseNotes(_appUpdateResult?.releaseNotes);
    } on AppUpdateLaunchException catch (e) {
      if (!mounted) return;
      setState(() => _appUpdateError = e.message);
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
      return ChangePasswordBody(
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
      return DeleteAccountBody(
        loading: _deletingAccount,
        error: _deleteError,
        onDelete: _deleteAccount,
      );
    }
    if (_showAbout) {
      return AboutBody(
        version: '${AppConfig.appVersion}+${AppConfig.appBuildNumber}',
        checkingForUpdates: _checkingForUpdates,
        appUpdateError: _appUpdateError,
        appUpdateResult: _appUpdateResult,
        onCheckForUpdates: _checkForUpdates,
        onOpenUpdateDownload: _openUpdateDownload,
        onOpenReleaseNotes: _openReleaseNotes,
      );
    }
    if (_showSettings) {
      return SettingsBody(
        repository: widget.repository,
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
    return ProfileMainBody(
      displayName: _effectiveDisplayName,
      email: _accountEmail,
      backendUrl: AppConfig.backendBaseUrl.trim().isEmpty
          ? 'Non configurée'
          : AppConfig.backendBaseUrl,
    );
  }
}

