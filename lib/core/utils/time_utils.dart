/// Formats a "last seen" timestamp for the UI.
String formatLastSeen(DateTime? lastSeen) {
  if (lastSeen == null) return 'Last seen recently';

  final DateTime now = DateTime.now();
  final Duration diff = now.difference(lastSeen);

  if (diff.inSeconds < 60) return 'Last seen just now';
  if (diff.inMinutes < 60) {
    final int m = diff.inMinutes;
    return 'Last seen $m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    final int h = diff.inHours;
    return 'Last seen $h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  if (diff.inDays < 7) {
    final int d = diff.inDays;
    return 'Last seen $d ${d == 1 ? 'day' : 'days'} ago';
  }

  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'Last seen ${months[lastSeen.month - 1]} ${lastSeen.day}';
}

/// Formats a message timestamp for chat bubbles and the conversation list.
///
/// Compact and scannable: today -> "14:05", yesterday -> "Yesterday", within
/// the last week -> weekday name, otherwise -> day/month/year.
String formatChatTime(DateTime? time) {
  if (time == null) return '';
  final DateTime local = time.toLocal();
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final int days = today.difference(day).inDays;

  final String clock = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  if (days == 0) return clock;
  if (days == 1) return 'Yesterday';

  const List<String> weekdays = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  if (days < 7) return weekdays[local.weekday - 1];
  return '${local.day}/${local.month}/${local.year}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Formats a duration as "m:ss" (or "h:mm:ss" for an hour or more).
String formatDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }
  return '$minutes:${_twoDigits(seconds)}';
}
