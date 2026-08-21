import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

class AppUpdateResult {
  const AppUpdateResult({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String currentVersion;
  final int currentBuildNumber;
  final String latestVersion;
  final int? latestBuildNumber;
  final String? downloadUrl;
  final String? releaseNotes;

  bool get isUpdateAvailable {
    final versionComparison = _compareVersionStrings(
      latestVersion,
      currentVersion,
    );
    if (versionComparison > 0) {
      return true;
    }
    if (versionComparison < 0) {
      return false;
    }
    if (latestBuildNumber == null) {
      return false;
    }
    return latestBuildNumber! > currentBuildNumber;
  }

  String get currentLabel => '$currentVersion+$currentBuildNumber';

  String get latestLabel {
    if (latestBuildNumber == null) {
      return latestVersion;
    }
    return '$latestVersion+$latestBuildNumber';
  }
}

class AppUpdateService {
  AppUpdateService({
    http.Client? httpClient,
    this.currentVersion,
    this.currentBuildNumber,
    this.manifestUrl,
    this.androidUpdateUrl,
    this.iosUpdateUrl,
    this.updateDownloadUrl,
    this.targetPlatform,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String? currentVersion;
  final int? currentBuildNumber;
  final String? manifestUrl;
  final String? androidUpdateUrl;
  final String? iosUpdateUrl;
  final String? updateDownloadUrl;
  final TargetPlatform? targetPlatform;

  String get _resolvedCurrentVersion => currentVersion ?? AppConfig.appVersion;
  int get _resolvedCurrentBuildNumber =>
      currentBuildNumber ?? AppConfig.appBuildNumber;
  String get _resolvedManifestUrl => manifestUrl ?? AppConfig.updateManifestUrl;
  String get _resolvedAndroidUpdateUrl =>
      androidUpdateUrl ?? AppConfig.androidUpdateUrl;
  String get _resolvedIosUpdateUrl => iosUpdateUrl ?? AppConfig.iosUpdateUrl;
  String get _resolvedUpdateDownloadUrl =>
      updateDownloadUrl ?? AppConfig.updateDownloadUrl;
  TargetPlatform get _resolvedTargetPlatform =>
      targetPlatform ?? defaultTargetPlatform;

  void dispose() {
    _httpClient.close();
  }

  Future<AppUpdateResult> checkForUpdates() async {
    final currentVersion = _resolvedCurrentVersion.trim();
    final currentBuild = _resolvedCurrentBuildNumber;
    final manifestUrl = _resolvedManifestUrl.trim();

    if (manifestUrl.isEmpty) {
      return AppUpdateResult(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuild,
        latestVersion: currentVersion,
        latestBuildNumber: currentBuild,
        downloadUrl: _fallbackDownloadUrl(),
        releaseNotes: null,
      );
    }

    final uri = Uri.parse(manifestUrl);
    final response = await _httpClient
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Impossible de récupérer les mises à jour.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw StateError('Format de manifest invalide.');
    }

    final latestVersion = (payload['latest_version'] as String?)?.trim();
    if (latestVersion == null || latestVersion.isEmpty) {
      throw StateError('latest_version manquant dans le manifest.');
    }

    final latestBuild = _readBuildNumber(payload['latest_build']);
    final platformUrl = _platformDownloadUrl(payload);
    final downloadUrl = platformUrl != null && platformUrl.trim().isNotEmpty
        ? platformUrl.trim()
        : _fallbackDownloadUrl();
    final notes = (payload['release_notes'] as String?)?.trim();

    return AppUpdateResult(
      currentVersion: currentVersion,
      currentBuildNumber: currentBuild,
      latestVersion: latestVersion,
      latestBuildNumber: latestBuild,
      downloadUrl: downloadUrl,
      releaseNotes: notes,
    );
  }

  int? _readBuildNumber(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _platformDownloadUrl(Map<String, dynamic> payload) {
    switch (_resolvedTargetPlatform) {
      case TargetPlatform.android:
        return payload['android_url'] as String?;
      case TargetPlatform.iOS:
        return payload['ios_url'] as String?;
      default:
        return (payload['desktop_url'] as String?) ??
            (payload['url'] as String?);
    }
  }

  String? _fallbackDownloadUrl() {
    switch (_resolvedTargetPlatform) {
      case TargetPlatform.android:
        final androidUrl = _resolvedAndroidUpdateUrl.trim();
        if (androidUrl.isNotEmpty) return androidUrl;
        break;
      case TargetPlatform.iOS:
        final iosUrl = _resolvedIosUpdateUrl.trim();
        if (iosUrl.isNotEmpty) return iosUrl;
        break;
      default:
        break;
    }
    final genericUrl = _resolvedUpdateDownloadUrl.trim();
    return genericUrl.isEmpty ? null : genericUrl;
  }
}

int _compareVersionStrings(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < maxLength; i++) {
    final leftValue = i < leftParts.length ? leftParts[i] : 0;
    final rightValue = i < rightParts.length ? rightParts[i] : 0;
    if (leftValue > rightValue) return 1;
    if (leftValue < rightValue) return -1;
  }
  return 0;
}

List<int> _versionParts(String value) {
  return value
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList(growable: false);
}
