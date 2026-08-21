import 'package:flutter/services.dart';

class AppUpdateLaunchException implements Exception {
  const AppUpdateLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateLauncher {
  static const MethodChannel _systemChannel = MethodChannel(
    'watchtracker/system',
  );

  static String? extractFirstHttpUrl(String text) {
    final match = RegExp(
      r'https?://\S+',
      caseSensitive: false,
    ).firstMatch(text);
    final candidate = match?.group(0);
    if (candidate == null || candidate.isEmpty) return null;
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return uri.toString();
  }

  Future<void> openDownload(String? url) {
    return _openUrl(
      url: url,
      invalidUrlError: 'Lien de mise à jour invalide.',
      openError: 'Impossible de lancer le téléchargement de la mise à jour.',
      mode: 'download',
    );
  }

  Future<void> openReleaseNotes(String? releaseNotes) {
    final notes = releaseNotes?.trim();
    final url = notes == null ? null : extractFirstHttpUrl(notes);
    return _openUrl(
      url: url,
      invalidUrlError: 'Lien de note de version invalide.',
      openError: 'Impossible d\'ouvrir automatiquement la note de version.',
    );
  }

  Future<void> _openUrl({
    required String? url,
    required String invalidUrlError,
    required String openError,
    String mode = 'view',
  }) async {
    final normalizedUrl = url?.trim();
    final uri = normalizedUrl == null ? null : Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw AppUpdateLaunchException(invalidUrlError);
    }

    var opened = false;
    try {
      opened =
          await _systemChannel.invokeMethod<bool>('openUrl', <String, dynamic>{
            'url': uri.toString(),
            'mode': mode,
          }) ??
          false;
    } on PlatformException {
      opened = false;
    }

    if (!opened) {
      throw AppUpdateLaunchException(openError);
    }
  }
}
