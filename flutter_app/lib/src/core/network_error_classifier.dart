/// Heuristic used across the presentation layer to decide whether an error
/// message indicates that the device is offline or the backend could not be
/// reached, as opposed to a genuine application/server error.
bool isOfflineOrServerUnreachableError(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('socketexception') ||
      normalized.contains('connection') ||
      normalized.contains('connexion') ||
      normalized.contains('clientexception') ||
      normalized.contains('timed out') ||
      normalized.contains('délai dépassé') ||
      normalized.contains('impossible de contacter') ||
      normalized.contains('serveur est accessible');
}
