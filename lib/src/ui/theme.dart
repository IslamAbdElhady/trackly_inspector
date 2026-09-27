import 'package:flutter/material.dart';
import 'package:trackly_logger/trackly_logger.dart';

import '../core/calls.dart';

const _seed = Color(0xFF3B82F6);

/// Success color.
const green = Color(0xFF16A34A);

/// Info and GET color.
const blue = Color(0xFF2563EB);

/// Warnings, 4xx, and PUT color.
const orange = Color(0xFFEA580C);

/// Errors, 5xx, and DELETE color.
const red = Color(0xFFDC2626);

/// Debug and PATCH color.
const teal = Color(0xFF0D9488);

/// Other methods color.
const purple = Color(0xFF7C3AED);

/// Pending and trace color.
const grey = Color(0xFF6B7280);

/// The inspector's own theme, so it looks the same in every app.
ThemeData inspectorTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// A monospaced text style for URLs, headers, and bodies.
TextStyle mono({
  double size = 12.5,
  Color? color,
  FontWeight? weight,
  Color? background,
}) => TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: const ['Roboto Mono', 'Courier New', 'monospace'],
  fontSize: size,
  color: color,
  fontWeight: weight,
  backgroundColor: background,
  height: 1.45,
);

/// The color of an HTTP method.
Color methodColor(String method) => switch (method) {
  'GET' => blue,
  'POST' => green,
  'PUT' => orange,
  'PATCH' => teal,
  'DELETE' => red,
  _ => purple,
};

/// The color of a call's status.
Color statusColor(TracklyHttpCall? call) {
  if (call == null || call.isPending) return grey;
  final code = call.statusCode;
  if (call.error != null || code == null || code >= 500) return red;
  if (code >= 400) return orange;
  if (code >= 300) return blue;
  return green;
}

/// The color of a log level.
Color levelColor(TracklyLevel level) => switch (level) {
  TracklyLevel.trace => grey,
  TracklyLevel.debug => teal,
  TracklyLevel.info => blue,
  TracklyLevel.success => green,
  TracklyLevel.warning => orange,
  TracklyLevel.error => red,
  TracklyLevel.fatal => const Color(0xFF991B1B),
};

/// Formats a size in bytes, e.g. `1.2 KB`.
String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Formats a duration, e.g. `132 ms` or `2.40 s`.
String formatDuration(Duration? duration) {
  if (duration == null) return '…';
  final ms = duration.inMilliseconds;
  return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';
}

/// Formats a time of day, e.g. `10:53:21.664`.
String formatTime(DateTime time) {
  String pad(int value, [int width = 2]) => '$value'.padLeft(width, '0');
  return '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}'
      '.${pad(time.millisecond, 3)}';
}
