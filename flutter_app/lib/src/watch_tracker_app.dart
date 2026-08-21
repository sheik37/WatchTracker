import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'presentation/theme/app_theme.dart';
import 'data/local/auth_session_store.dart';
import 'data/local/watchtracker_database.dart';
import 'data/models/auth_models.dart';
import 'data/remote/tvdb_api_client.dart';
import 'data/remote/tmdb_api_client.dart';
import 'data/repositories/media_repository.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/main_shell_screen.dart';

const _kAdminEmail = 'admin@watchtracker.net';
const _kResendCooldown = 60;
const _kForgotCooldown = 60;

class WatchTrackerApp extends StatefulWidget {
  const WatchTrackerApp({super.key});

  @override
  State<WatchTrackerApp> createState() => _WatchTrackerAppState();
}

class _WatchTrackerAppState extends State<WatchTrackerApp> {
  late final AuthSessionStore _sessionStore;
  late final MediaRepository _repository;

  bool _bootLoading = true;
  bool _authLoading = false;
  String? _authError;
  String? _authInfo;
  String? _token;
  String? _refreshToken;
  UserProfile? _profile;
  bool _showOtpField = false;
  bool _showResendVerification = false;

  int _retryAfterSeconds = 0;
  int? _attemptsRemaining;
  int _resendCooldown = 0;
  int _forgotCooldown = 0;

  Timer? _retryTimer;
  Timer? _resendTimer;
  Timer? _forgotTimer;

  @override
  void initState() {
    super.initState();
    _sessionStore = AuthSessionStore();
    _repository = MediaRepository(
      TmdbApiClient(apiKey: AppConfig.tmdbApiKey),
      AppConfig.tvdbApiKey.isEmpty
          ? null
          : TvdbApiClient(apiKey: AppConfig.tvdbApiKey),
      WatchTrackerDatabase(),
      backendBaseUrl: AppConfig.backendBaseUrl,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _resendTimer?.cancel();
    _forgotTimer?.cancel();
    super.dispose();
  }

  void _startRetryCountdown(int seconds) {
    _retryTimer?.cancel();
    setState(() {
      _retryAfterSeconds = seconds;
      _attemptsRemaining = null;
    });
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _retryAfterSeconds = (_retryAfterSeconds - 1).clamp(0, 9999);
      });
      if (_retryAfterSeconds <= 0) {
        t.cancel();
        setState(() {
          _attemptsRemaining = null;
        });
      }
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = _kResendCooldown);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendCooldown = (_resendCooldown - 1).clamp(0, 9999));
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  void _startForgotCooldown([int seconds = _kForgotCooldown]) {
    _forgotTimer?.cancel();
    setState(() => _forgotCooldown = seconds);
    _forgotTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _forgotCooldown = (_forgotCooldown - 1).clamp(0, 9999));
      if (_forgotCooldown <= 0) t.cancel();
    });
  }

  Future<void> _bootstrap() async {
    final token = await _sessionStore.token();
    final refreshToken = await _sessionStore.refreshToken();
    final expiresAt = await _sessionStore.tokenExpiresAtMillis();
    if (token != null && token.isNotEmpty) {
      _repository.setBackendAuthToken(token);
      if (refreshToken != null &&
          refreshToken.isNotEmpty &&
          expiresAt != null &&
          expiresAt <= DateTime.now().millisecondsSinceEpoch + 30 * 1000) {
        try {
          final refreshed = await _repository.refresh(refreshToken);
          await _sessionStore.saveTokens(
            token: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresInSeconds: refreshed.expiresInSeconds,
          );
          _token = refreshed.accessToken;
          _refreshToken = refreshed.refreshToken;
          _repository.setBackendAuthToken(refreshed.accessToken);
        } catch (_) {
          await _sessionStore.clearSession();
          await _repository.clearLocalSessionData();
          _repository.setBackendAuthToken(null);
          _token = null;
        }
      } else {
        _token = token;
        _refreshToken = refreshToken;
      }
      if (_token != null) {
        try {
          _profile = await _repository.getCurrentUserProfile();
          if (_profile != null) {
            await _sessionStore.saveUserProfile(
              userId: _profile!.userId,
              email: _profile!.email,
              displayName: _profile!.displayName,
            );
          }
          await _repository.synchronizeWithBackend();
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _bootLoading = false);
  }

  Future<void> _login(String email, String password, String? otpCode) async {
    setState(() {
      _authLoading = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      final tokens = await _repository.login(email, password, otpCode: otpCode);
      await _sessionStore.saveTokens(
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.expiresInSeconds,
      );
      _repository.setBackendAuthToken(tokens.accessToken);
      _token = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      _profile = await _repository.getCurrentUserProfile();
      if (_profile != null) {
        await _sessionStore.saveUserProfile(
          userId: _profile!.userId,
          email: _profile!.email,
          displayName: _profile!.displayName,
        );
      }
      await _repository.synchronizeWithBackend();
      if (mounted) {
        setState(() {
          _showOtpField = false;
          _showResendVerification = false;
          _retryAfterSeconds = 0;
          _attemptsRemaining = null;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _authError = e.message;
          if (e.requiresOtp) _showOtpField = true;
          _attemptsRemaining = (e.retryAfterSeconds ?? 0) > 0
              ? null
              : e.attemptsRemaining;
        });
        if ((e.retryAfterSeconds ?? 0) > 0) {
          _startRetryCountdown(e.retryAfterSeconds!);
        }
      }
      rethrow;
    } catch (e) {
      if (mounted) setState(() => _authError = e.toString());
      rethrow;
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _register(String email, String password) async {
    setState(() {
      _authLoading = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      await _repository.register(email, password);
      if (mounted) {
        setState(() {
          _authInfo =
              'Inscription réussie. Vérifie ton email pour activer ton compte.';
          _showResendVerification = true;
        });
        _startResendCooldown();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _authError = e.message;
          _attemptsRemaining = (e.retryAfterSeconds ?? 0) > 0
              ? null
              : e.attemptsRemaining;
        });
        if ((e.retryAfterSeconds ?? 0) > 0) {
          _startRetryCountdown(e.retryAfterSeconds!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _authError = e.toString());
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _forgotPassword(String email) async {
    if (!email.contains('@')) {
      setState(() => _authError = 'Saisis une adresse email valide.');
      return;
    }
    if (_forgotCooldown > 0) return;
    setState(() {
      _authLoading = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      final msg = await _repository.forgotPassword(email);
      if (mounted) {
        setState(() => _authInfo = msg);
        _startForgotCooldown();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _authError = e.message);
        if ((e.retryAfterSeconds ?? 0) > 0) {
          _startForgotCooldown(e.retryAfterSeconds!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _authError = e.toString());
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _resendVerification(String email) async {
    if (!email.contains('@')) {
      setState(() => _authError = 'Saisis une adresse email valide.');
      return;
    }
    if (!_showResendVerification || _resendCooldown > 0) return;
    setState(() {
      _authLoading = true;
      _authError = null;
      _authInfo = null;
    });
    try {
      final msg = await _repository.resendVerification(email);
      if (mounted) {
        setState(() => _authInfo = msg);
        _startResendCooldown();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _authError = e.message);
    } catch (e) {
      if (mounted) setState(() => _authError = e.toString());
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _repository.logout(_refreshToken);
    } catch (_) {
      // The backend may already have invalidated the session (e.g. after
      // password change or account deletion). Local logout must still proceed.
    } finally {
      await _repository.clearLocalSessionData();
      await _sessionStore.clearSession();
      _repository.setBackendAuthToken(null);
      if (mounted) {
        setState(() {
          _token = null;
          _refreshToken = null;
          _profile = null;
          _showOtpField = false;
          _showResendVerification = false;
          _authError = null;
          _authInfo = null;
        });
      }
    }
  }

  Future<void> _handleProfileUpdated(UserProfile profile) async {
    _profile = profile;
    await _sessionStore.saveUserProfile(
      userId: profile.userId,
      email: profile.email,
      displayName: profile.displayName,
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WatchTracker',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: _bootLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_token == null
                ? AuthScreen(
                    isLoading: _authLoading,
                    appVersionLabel:
                        '${AppConfig.appVersion}+${AppConfig.appBuildNumber}',
                    errorMessage: _authError,
                    infoMessage: _authInfo,
                    retryAfterSeconds: _retryAfterSeconds > 0
                        ? _retryAfterSeconds
                        : null,
                    attemptsRemaining: _attemptsRemaining,
                    showResendVerification: _showResendVerification,
                    showOtpCodeField: _showOtpField,
                    admin2faEmail: _kAdminEmail,
                    resendCooldownSeconds: _resendCooldown > 0
                        ? _resendCooldown
                        : null,
                    forgotCooldownSeconds: _forgotCooldown > 0
                        ? _forgotCooldown
                        : null,
                    onLogin: _login,
                    onRegister: _register,
                    onForgotPassword: _forgotPassword,
                    onResendVerification: _resendVerification,
                    onModeChanged: () => setState(() {
                      _authError = null;
                      _authInfo = null;
                      _attemptsRemaining = null;
                    }),
                  )
                : MainShellScreen(
                    repository: _repository,
                    profile: _profile,
                    onLogout: _logout,
                    onProfileUpdated: (profile) {
                      _handleProfileUpdated(profile);
                    },
                  )),
    );
  }
}
