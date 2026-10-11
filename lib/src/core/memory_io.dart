import 'dart:io';

/// The app's memory use in bytes (its resident set size), or `null` if it
/// can't be measured.
int? currentMemory() {
  try {
    final bytes = ProcessInfo.currentRss;
    return bytes > 0 ? bytes : null;
  } catch (_) {
    return null;
  }
}
