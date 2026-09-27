import 'dart:convert';

/// A request or response body turned into text for display.
typedef CapturedBody = ({String? text, int? size});

/// Content types whose bytes are shown as text.
final _textContentType = RegExp(
  r'json|text/|xml|javascript|x-www-form-urlencoded|graphql',
  caseSensitive: false,
);

/// Converts a body from any HTTP client into displayable text and its size in
/// bytes.
///
/// Strings are kept as is, maps and lists are encoded as JSON, and bytes are
/// decoded as UTF-8 unless [contentType] says they are binary.
CapturedBody captureBody(
  Object? data, {
  String? contentType,
  required int maxLength,
}) {
  if (data == null) return (text: null, size: null);

  final String text;
  final int size;
  if (data is String) {
    text = data;
    size = utf8.encode(data).length;
  } else if (data is List<int>) {
    size = data.length;
    text = _decodeBytes(data, contentType) ?? '<binary: $size bytes>';
  } else if (data is Map || data is List) {
    text = jsonEncode(data, toEncodable: (value) => '$value');
    size = utf8.encode(text).length;
  } else {
    text = '$data';
    size = utf8.encode(text).length;
  }

  return (text: _truncate(text, maxLength), size: size);
}

String? _decodeBytes(List<int> bytes, String? contentType) {
  if (bytes.isEmpty) return '';
  if (contentType != null &&
      contentType.isNotEmpty &&
      !_textContentType.hasMatch(contentType)) {
    return null;
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}\n'
      '… truncated (${text.length} characters in total)';
}

/// Finds a header by name, ignoring case.
String? headerValue(Map<String, String> headers, String name) {
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}
