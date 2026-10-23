/// Formats a watch-date timestamp (milliseconds since epoch) as a
/// `dd/MM/yyyy` label, used throughout the details screen to display
/// viewing/rewatch history.
String formatWatchDateLabel(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
