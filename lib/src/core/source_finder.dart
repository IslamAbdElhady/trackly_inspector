import 'dart:convert';

import 'calls.dart';
import 'text.dart';

/// How a value on screen matched a value in a response.
enum MatchKind {
  /// The same text.
  exact('Exact match', 4),

  /// The same image URL.
  url('Same URL', 4),

  /// The same number, formatted differently, e.g. `1,250` and `1250`.
  number('Same number', 3),

  /// The value on screen is the start of the response value, e.g. when the
  /// app shortens long text.
  prefix('Shortened', 2),

  /// One contains the other, e.g. `Welcome, Leanne` and `Leanne`.
  partial('Contains', 1);

  const MatchKind(this.label, this.score);

  /// A short description shown in the results.
  final String label;

  /// Higher scores are shown first.
  final int score;
}

/// A call whose response contains a value shown on screen.
class SourceMatch {
  /// Creates a match.
  const SourceMatch({
    required this.call,
    required this.path,
    required this.value,
    required this.kind,
    required this.count,
  });

  /// The call.
  final TracklyHttpCall call;

  /// Where the value is in the response body, e.g. `$.data.user.name`, or
  /// `null` when the call's own URL matched.
  final String? path;

  /// The matching value from the response, as text.
  final String value;

  /// How the value matched.
  final MatchKind kind;

  /// How many values in this call's response matched.
  final int count;
}

/// Formats a JSON [path] for display, e.g. `$.data.user.name` becomes
/// `data.user.name`.
String displayPath(String? path) {
  if (path == null) return 'Request URL';
  if (path == r'$') return 'Body';
  return path.startsWith(r'$.') ? path.substring(2) : path.substring(1);
}

/// The paths of the objects and arrays that contain [path], outermost first,
/// e.g. `$`, `$.data`, and `$.data.users` for `$.data.users[0]`.
List<String> ancestorPaths(String path) => [
  for (var i = 1; i < path.length; i++)
    if (path[i] == '.' || path[i] == '[') path.substring(0, i),
];

/// Finds the calls whose responses contain any of [texts] or [imageUrls],
/// best and most recent matches first.
List<SourceMatch> findSources({
  required List<String> texts,
  List<String> imageUrls = const [],
  required List<TracklyHttpCall> calls,
  int limit = 20,
}) {
  final wanted = [
    for (final text in texts)
      if (normalizeText(text).isNotEmpty) _Wanted(text),
  ];
  final urls = imageUrls.toSet();
  if (wanted.isEmpty && urls.isEmpty) return const [];

  final matches = <SourceMatch>[];
  for (final call in calls) {
    if (call.statusCode == null) continue;

    SourceMatch? best;
    var count = 0;
    void consider(String? path, Object? value, MatchKind? kind) {
      if (kind == null) return;
      count++;
      if (best == null || kind.score > best!.kind.score) {
        best = SourceMatch(
          call: call,
          path: path,
          value: value is String ? value : jsonEncode(value),
          kind: kind,
          count: 0,
        );
      }
    }

    if (urls.contains('${call.uri}')) {
      consider(null, '${call.uri}', MatchKind.url);
    }

    final body = call.responseBody;
    if (body != null) {
      final json = _tryDecode(body);
      if (identical(json, _notJson)) {
        consider(r'$', body, _matchText(body, wanted, urls, rawBody: true));
      } else {
        var visited = 0;
        void walk(Object? node, String path) {
          if (visited++ > 50000) return;
          if (node is Map) {
            for (final entry in node.entries) {
              walk(entry.value, '$path.${entry.key}');
            }
          } else if (node is List) {
            for (var i = 0; i < node.length; i++) {
              walk(node[i], '$path[$i]');
            }
          } else {
            consider(path, node, _matchValue(node, wanted, urls));
          }
        }

        walk(json, r'$');
      }
    }

    final found = best;
    if (found != null) {
      matches.add(
        SourceMatch(
          call: call,
          path: found.path,
          value: found.value,
          kind: found.kind,
          count: count,
        ),
      );
    }
  }

  matches.sort((a, b) {
    final byKind = b.kind.score.compareTo(a.kind.score);
    return byKind != 0 ? byKind : b.call.id.compareTo(a.call.id);
  });
  return matches.take(limit).toList();
}

class _Wanted {
  _Wanted(String text)
    : normalized = normalizeText(text),
      number = _parseNumber(normalizeText(text)) {
    shortened = normalized.replaceFirst(RegExp(r'(…|\.\.\.)$'), '').trim();
  }

  final String normalized;
  final num? number;
  late final String shortened;

  /// Reads the value as a number if it's a single number with optional
  /// currency or units around it, e.g. `EGP 1,250.00` or `3 items`.
  static num? _parseNumber(String text) {
    final groups = RegExp(r'\d+(?:[.,]\d+)*').allMatches(text).toList();
    if (groups.length != 1) return null;
    final negative = text.contains('-${groups.single.group(0)}');
    var digits = groups.single.group(0)!;
    if (digits.contains(',') && digits.contains('.')) {
      digits = digits.replaceAll(',', '');
    } else if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(digits)) {
      digits = digits.replaceAll(',', '');
    } else {
      digits = digits.replaceAll(',', '.');
    }
    final value = num.tryParse(digits);
    return value == null || !negative ? value : -value;
  }
}

final _notJson = Object();

Object? _tryDecode(String body) {
  final trimmed = body.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return _notJson;
  try {
    return jsonDecode(body);
  } on FormatException {
    return _notJson;
  }
}

MatchKind? _matchValue(Object? value, List<_Wanted> wanted, Set<String> urls) {
  if (value is String) return _matchText(value, wanted, urls);
  if (value is num || value is bool) {
    MatchKind? best;
    for (final w in wanted) {
      final kind =
          w.normalized == '$value'
              ? MatchKind.exact
              : value is num && w.number == value
              ? MatchKind.number
              : null;
      if (kind != null && (best == null || kind.score > best.score)) {
        best = kind;
      }
    }
    return best;
  }
  return null;
}

MatchKind? _matchText(
  String value,
  List<_Wanted> wanted,
  Set<String> urls, {
  bool rawBody = false,
}) {
  if (!rawBody && urls.contains(value)) return MatchKind.url;

  final normalized = normalizeText(value);
  if (normalized.isEmpty) return null;
  MatchKind? best;
  for (final w in wanted) {
    MatchKind? kind;
    if (!rawBody && normalized == w.normalized) {
      kind = MatchKind.exact;
    } else if (!rawBody &&
        w.number != null &&
        num.tryParse(normalized) == w.number) {
      kind = MatchKind.number;
    } else if (!rawBody &&
        w.shortened.length >= 4 &&
        w.shortened != w.normalized &&
        normalized.startsWith(w.shortened)) {
      kind = MatchKind.prefix;
    } else if ((!rawBody &&
            normalized.length >= 4 &&
            w.normalized.contains(normalized)) ||
        (w.normalized.length >= 4 && normalized.contains(w.normalized))) {
      kind = MatchKind.partial;
    }
    if (kind != null && (best == null || kind.score > best.score)) {
      best = kind;
    }
  }
  return best;
}
