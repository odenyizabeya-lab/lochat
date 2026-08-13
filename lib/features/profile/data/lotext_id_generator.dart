import 'dart:math';

final RegExp _lotextIdPattern = RegExp(r'^\d{9}$');

/// Returns a new random 9-digit LoText ID (100000000-999999999).
String generateLotextId(Random random) {
  return (100000000 + random.nextInt(900000000)).toString();
}

/// Whether [value] looks like a valid 9-digit LoText ID.
bool isValidLotextId(String value) => _lotextIdPattern.hasMatch(value);
