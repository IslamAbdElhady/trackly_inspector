import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/calls.dart';
import '../core/source_finder.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Mode {
  pretty('Pretty'),
  tree('Tree'),
  table('Table'),
  raw('Raw');

  const _Mode(this.label);

  final String label;
}

enum _Kind { empty, json, urlEncoded, multipart, text, binary }

/// Shows a request or response body the way Postman does: JSON pretty-printed
/// with line numbers or as a collapsible tree, form bodies as key/value
/// tables, and everything else as numbered lines. Has search and copy.
class BodyView extends StatefulWidget {
  /// Creates a view of [body].
  const BodyView({
    super.key,
    required this.body,
    required this.title,
    this.contentType,
    this.formData,
    this.size,
    this.highlightPath,
    this.highlightValue,
  });

  /// The body text.
  final String? body;

  /// Used in the "copied" message, e.g. `Response body`.
  final String title;

  /// The `content-type` header of the body, if any.
  final String? contentType;

  /// The fields of a multipart form body. Shown instead of [body].
  final List<TracklyFormField>? formData;

  /// The body size in bytes, if known.
  final int? size;

  /// A JSON path, e.g. `$.data.name`, to reveal, highlight, and scroll to.
  final String? highlightPath;

  /// Text to search for when the body isn't JSON.
  final String? highlightValue;

  @override
  State<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<BodyView> {
  static const _highlightLimit = 150000;
  static const _lineHeight = 21.0;

  final _scroll = ScrollController();
  final _targetKey = GlobalKey();
  var _kind = _Kind.empty;
  var _mode = _Mode.pretty;
  Object? _json;
  String _pretty = '';
  List<(String, String, bool)> _fields = const [];
  var _searching = false;
  var _query = '';
  final _expanded = <String>{r'$'};
  var _revealed = false;
  int? _scrolledTo;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(BodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body ||
        oldWidget.formData != widget.formData ||
        oldWidget.contentType != widget.contentType) {
      _parse();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_Mode> get _modes => switch (_kind) {
    _Kind.json => const [_Mode.pretty, _Mode.tree, _Mode.raw],
    _Kind.urlEncoded => const [_Mode.table, _Mode.raw],
    _Kind.multipart => const [_Mode.table],
    _Kind.text => const [_Mode.pretty],
    _Kind.empty || _Kind.binary => const [],
  };

  String get _typeLabel {
    final type = widget.contentType?.toLowerCase() ?? '';
    return switch (_kind) {
      _Kind.json => 'JSON',
      _Kind.urlEncoded => 'Form URL-encoded',
      _Kind.multipart => 'Form data',
      _Kind.binary => 'Binary',
      _Kind.empty => 'None',
      _Kind.text when type.contains('xml') => 'XML',
      _Kind.text when type.contains('html') => 'HTML',
      _Kind.text => 'Text',
    };
  }

  void _parse() {
    final body = widget.body;
    final type = widget.contentType?.toLowerCase() ?? '';
    _json = null;
    _pretty = body ?? '';
    _fields = const [];
    _searching = false;
    _query = '';

    final form = widget.formData;
    if (form != null) {
      _kind = _Kind.multipart;
      _mode = _Mode.table;
      _fields = [
        for (final field in form)
          field.isFile
              ? (
                field.name,
                '${field.fileName} · ${formatBytes(field.fileSize)}',
                true,
              )
              : (field.name, field.value ?? '', false),
      ];
      return;
    }
    if (body == null || body.isEmpty) {
      _kind = _Kind.empty;
      return;
    }
    if (body.startsWith('<binary:')) {
      _kind = _Kind.binary;
      return;
    }

    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final json = jsonDecode(body);
        _json = json;
        _kind = _Kind.json;
        _pretty = const JsonEncoder.withIndent('  ').convert(json);
        final highlight = widget.highlightPath;
        if (highlight != null) {
          // Open just the objects and arrays that lead to the highlighted
          // value, in the tree.
          _mode = _Mode.tree;
          _expanded
            ..clear()
            ..add(r'$')
            ..addAll(ancestorPaths(highlight));
        } else {
          _mode = _Mode.pretty;
          if (json is Map && json.length <= 30) {
            for (final key in json.keys) {
              _expanded.add('\$.$key');
            }
          }
        }
        return;
      } on FormatException {
        // Not JSON after all; show it as text below.
      }
    }

    if (type.contains('x-www-form-urlencoded')) {
      final fields = _parseUrlEncoded(body);
      if (fields != null) {
        _kind = _Kind.urlEncoded;
        _mode = _Mode.table;
        _fields = [for (final (key, value) in fields) (key, value, false)];
        return;
      }
    }

    _kind = _Kind.text;
    _mode = _Mode.pretty;
    final value = widget.highlightValue;
    if (value != null && value.isNotEmpty) {
      _searching = true;
      _query = value;
    }
  }

  /// Splits `a=1&b=two%20words` into its decoded fields, keeping their order
  /// and repeated keys. Returns `null` if it isn't valid form encoding.
  static List<(String, String)>? _parseUrlEncoded(String body) {
    try {
      return [
        for (final pair in body.trim().split('&'))
          if (pair.isNotEmpty)
            pair.contains('=')
                ? (
                  Uri.decodeQueryComponent(
                    pair.substring(0, pair.indexOf('=')),
                  ),
                  Uri.decodeQueryComponent(
                    pair.substring(pair.indexOf('=') + 1),
                  ),
                )
                : (Uri.decodeQueryComponent(pair), ''),
      ];
    } on ArgumentError {
      return null;
    }
  }

  /// Scrolls the row with [_targetKey] into view once it's laid out. Rows far
  /// down aren't built yet, so first jump near where it should be.
  void _scrollToRow(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scroll.hasClients) return;
      if (_targetKey.currentContext == null) {
        final position = _scroll.position;
        position.jumpTo(
          (index * _lineHeight).clamp(0, position.maxScrollExtent).toDouble(),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      final row = _targetKey.currentContext;
      if (row != null && row.mounted) {
        await Scrollable.ensureVisible(
          row,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _Kind.empty:
        return const EmptyState(icon: Icons.inbox_outlined, title: 'No body');
      case _Kind.binary:
        return EmptyState(
          icon: Icons.insert_drive_file_outlined,
          title: 'Binary body',
          message: [
            if (widget.contentType != null) widget.contentType!,
            formatBytes(widget.size),
          ].join('  ·  '),
        );
      case _Kind.json || _Kind.urlEncoded || _Kind.multipart || _Kind.text:
        break;
    }

    final mode = _searching && _kind != _Kind.urlEncoded ? _Mode.pretty : _mode;
    final content = switch (mode) {
      _Mode.pretty => _lines(context),
      _Mode.tree => _tree(context),
      _Mode.table => _table(context),
      _Mode.raw => _raw(context),
    };
    final selectable = mode == _Mode.pretty || mode == _Mode.raw;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context, mode),
        const Divider(),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: selectable ? SelectionArea(child: content) : content,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context, _Mode mode) {
    final colors = Theme.of(context).colorScheme;
    final modes = _modes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeChip(_typeLabel),
              const SizedBox(width: 10),
              Text(
                formatBytes(widget.size),
                style: TextStyle(
                  fontSize: 13.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (mode == _Mode.tree) ...[
                IconButton(
                  tooltip: 'Expand all',
                  icon: const Icon(Icons.unfold_more, size: 21),
                  onPressed: () => setState(_expandAll),
                ),
                IconButton(
                  tooltip: 'Collapse all',
                  icon: const Icon(Icons.unfold_less, size: 21),
                  onPressed:
                      () => setState(() {
                        _expanded
                          ..clear()
                          ..add(r'$');
                      }),
                ),
              ],
              if (_kind == _Kind.json || _kind == _Kind.text)
                IconButton(
                  tooltip: 'Search in body',
                  isSelected: _searching,
                  icon: const Icon(Icons.manage_search, size: 23),
                  onPressed:
                      () => setState(() {
                        _searching = !_searching;
                        _query = '';
                      }),
                ),
              IconButton(
                tooltip: 'Copy body',
                icon: const Icon(Icons.copy_rounded, size: 21),
                onPressed:
                    () => copyText(
                      context,
                      _copyText(mode),
                      '${widget.title} copied',
                    ),
              ),
            ],
          ),
          if (modes.length > 1 && !_searching)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SegmentedButton<_Mode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                segments: [
                  for (final mode in modes)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {mode},
                onSelectionChanged:
                    (selection) => setState(() => _mode = selection.first),
              ),
            ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      hint: 'Search in ${widget.title.toLowerCase()}',
                      initialValue: _query,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        '${_matches().length} found',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _copyText(_Mode mode) => switch (_kind) {
    _Kind.multipart => _fields.map((f) => '${f.$1}: ${f.$2}').join('\n'),
    _Kind.json when mode != _Mode.raw => _pretty,
    _ => widget.body ?? '',
  };

  void _expandAll() {
    void visit(Object? value, String path) {
      if (value is Map) {
        _expanded.add(path);
        for (final entry in value.entries) {
          visit(entry.value, '$path.${entry.key}');
        }
      } else if (value is List) {
        _expanded.add(path);
        for (var i = 0; i < value.length; i++) {
          visit(value[i], '$path[$i]');
        }
      }
    }

    visit(_json, r'$');
  }

  List<(int, int)> _matches() {
    // Only the query is normalized (e.g. Arabic digits typed on an Arabic
    // keyboard), so offsets in the body stay right.
    final query = normalizeQuery(_query);
    if (query.isEmpty) return const [];
    final text = _pretty.toLowerCase();
    final matches = <(int, int)>[];
    var index = text.indexOf(query);
    while (index != -1 && matches.length < 5000) {
      matches.add((index, index + query.length));
      index = text.indexOf(query, index + query.length);
    }
    return matches;
  }

  /// The body as numbered lines, with JSON colors and search highlights.
  Widget _lines(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final text = _pretty;
    final matches = _matches();
    final segments =
        _kind == _Kind.json && text.length <= _highlightLimit
            ? _jsonSegments(text, _JsonColors.of(dark))
            : const <_Segment>[];
    final lines = _splitLines(
      _spans(
        text,
        segments,
        matches,
        dark ? const Color(0x99A16207) : const Color(0xFFFDE68A),
      ),
    );

    // Scroll to the first match whenever it moves to another line.
    var target = -1;
    if (matches.isNotEmpty) {
      target = '\n'.allMatches(text.substring(0, matches.first.$1)).length;
      if (target != _scrolledTo) {
        _scrolledTo = target;
        _scrollToRow(target);
      }
    } else {
      _scrolledTo = null;
    }

    final digits = '${lines.length}'.length;
    final gutter = 14.0 + digits * 8.5;
    final style = mono(color: colors.onSurface);
    final numberStyle = mono(
      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
    );

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 32),
      itemCount: lines.length,
      itemBuilder:
          (context, index) => Row(
            key: index == target ? _targetKey : null,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectionContainer.disabled(
                child: SizedBox(
                  width: gutter,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.right,
                      style: numberStyle,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children:
                        lines[index].isEmpty
                            ? const [TextSpan(text: ' ')]
                            : lines[index],
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// The body exactly as it was sent or received.
  Widget _raw(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [Text(widget.body ?? '', style: mono(color: colors.onSurface))],
    );
  }

  /// Form fields as a key/value table.
  Widget _table(BuildContext context) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: [
        FieldTable(
          rows: [
            for (final (key, value, isFile) in _fields)
              FieldRow(
                key,
                value,
                type:
                    _kind == _Kind.multipart
                        ? (isFile ? 'File' : 'Text')
                        : null,
              ),
          ],
          emptyText: 'No fields',
        ),
      ],
    );
  }

  Widget _tree(BuildContext context) {
    final nodes = <_Node>[];
    void visit(String? key, Object? value, int depth, String path) {
      nodes.add(_Node(key, value, depth, path));
      if (!_expanded.contains(path)) return;
      if (value is Map) {
        for (final entry in value.entries) {
          visit('${entry.key}', entry.value, depth + 1, '$path.${entry.key}');
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          visit('$i', value[i], depth + 1, '$path[$i]');
        }
      }
    }

    visit(null, _json, 0, r'$');
    final highlight = nodes.indexWhere(
      (node) => node.path == widget.highlightPath,
    );
    if (highlight != -1 && !_revealed) {
      _revealed = true;
      _scrollToRow(highlight);
    }
    final theme = Theme.of(context);
    final colors = _JsonColors.of(theme.brightness == Brightness.dark);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      itemCount: nodes.length,
      itemBuilder:
          (context, index) => _NodeRow(
            key: index == highlight ? _targetKey : null,
            highlighted: index == highlight,
            node: nodes[index],
            expanded: _expanded.contains(nodes[index].path),
            colors: colors,
            muted: theme.colorScheme.onSurfaceVariant,
            onToggle:
                () => setState(() {
                  final path = nodes[index].path;
                  if (!_expanded.remove(path)) _expanded.add(path);
                }),
          ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Node {
  _Node(this.key, this.value, this.depth, this.path);

  final String? key;
  final Object? value;
  final int depth;
  final String path;

  bool get isContainer => value is Map || value is List;
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    super.key,
    required this.highlighted,
    required this.node,
    required this.expanded,
    required this.colors,
    required this.muted,
    required this.onToggle,
  });

  final bool highlighted;
  final _Node node;
  final bool expanded;
  final _JsonColors colors;
  final Color muted;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final value = node.value;
    final isList = node.key != null && int.tryParse(node.key!) != null;
    return InkWell(
      onTap: node.isContainer ? onToggle : null,
      onLongPress:
          () => copyText(
            context,
            value is String ? value : jsonEncode(value),
            node.key == null ? 'Copied JSON' : 'Copied ${node.key}',
          ),
      child: Container(
        decoration:
            highlighted
                ? BoxDecoration(
                  color: const Color(0x55FACC15),
                  borderRadius: BorderRadius.circular(4),
                )
                : null,
        padding: EdgeInsets.only(left: node.depth * 18.0, top: 3, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child:
                  node.isContainer
                      ? Icon(
                        expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 20,
                        color: muted,
                      )
                      : null,
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: mono(),
                  children: [
                    if (node.key != null) ...[
                      TextSpan(
                        text: node.key,
                        style: TextStyle(
                          color: isList ? muted : colors.key,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: ': ', style: TextStyle(color: muted)),
                    ],
                    _valueSpan(value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _valueSpan(Object? value) {
    return switch (value) {
      Map() || List() when expanded => TextSpan(
        text: value is List ? '(${value.length}) [' : '{',
        style: TextStyle(color: muted),
      ),
      Map() ||
      List() => TextSpan(text: _preview(value), style: TextStyle(color: muted)),
      String() => TextSpan(
        text: jsonEncode(value),
        style: TextStyle(color: colors.string),
      ),
      num() => TextSpan(text: '$value', style: TextStyle(color: colors.number)),
      bool() => TextSpan(
        text: '$value',
        style: TextStyle(color: colors.keyword),
      ),
      _ => TextSpan(text: 'null', style: TextStyle(color: colors.keyword)),
    };
  }
}

/// A one-line summary of a collapsed object or array, like Chrome's
/// DevTools: `{id: 1, title: "Hello", …}` or `(3) [1, 2, 3]`.
String _preview(Object? value, [int limit = 60]) {
  String short(Object? item) => switch (item) {
    Map() => '{…}',
    List() => '[…]',
    String() => jsonEncode(
      item.length > 20 ? '${item.substring(0, 20)}…' : item,
    ),
    _ => '$item',
  };

  final Iterable<String> parts;
  final String open, close;
  if (value is Map) {
    parts = value.entries.map((e) => '${e.key}: ${short(e.value)}');
    (open, close) = ('{', '}');
  } else {
    parts = (value as List).map(short);
    (open, close) = ('(${value.length}) [', ']');
  }

  final buffer = StringBuffer(open);
  var first = true;
  for (final part in parts) {
    if (buffer.length + part.length > limit) {
      buffer.write(first ? '…' : ', …');
      break;
    }
    if (!first) buffer.write(', ');
    buffer.write(part);
    first = false;
  }
  buffer.write(close);
  return buffer.toString();
}

class _JsonColors {
  const _JsonColors({
    required this.key,
    required this.string,
    required this.number,
    required this.keyword,
  });

  factory _JsonColors.of(bool dark) =>
      dark
          ? const _JsonColors(
            key: Color(0xFF93C5FD),
            string: Color(0xFF86EFAC),
            number: Color(0xFFFCA5A5),
            keyword: Color(0xFFC4B5FD),
          )
          : const _JsonColors(
            key: Color(0xFF1D4ED8),
            string: Color(0xFF15803D),
            number: Color(0xFFB91C1C),
            keyword: Color(0xFF7C3AED),
          );

  final Color key;
  final Color string;
  final Color number;
  final Color keyword;
}

typedef _Segment = (int start, int end, Color color);

final _jsonToken = RegExp(
  r'("(?:[^"\\]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)',
);

List<_Segment> _jsonSegments(String text, _JsonColors colors) => [
  for (final match in _jsonToken.allMatches(text))
    if (match.group(1) != null)
      (
        match.start,
        match.start + match.group(1)!.length,
        match.group(2) != null ? colors.key : colors.string,
      )
    else if (match.group(3) != null)
      (match.start, match.end, colors.keyword)
    else
      (match.start, match.end, colors.number),
];

/// Splits [text] into spans colored by [segments], with [matches] highlighted.
List<TextSpan> _spans(
  String text,
  List<_Segment> segments,
  List<(int, int)> matches,
  Color highlight,
) {
  if (segments.isEmpty && matches.isEmpty) return [TextSpan(text: text)];

  final points = <int>{0, text.length};
  for (final (start, end, _) in segments) {
    points
      ..add(start)
      ..add(end);
  }
  for (final (start, end) in matches) {
    points
      ..add(start)
      ..add(end);
  }
  final sorted = points.toList()..sort();

  final spans = <TextSpan>[];
  var segment = 0;
  var match = 0;
  for (var i = 0; i < sorted.length - 1; i++) {
    final start = sorted[i];
    final end = sorted[i + 1];
    while (segment < segments.length && segments[segment].$2 <= start) {
      segment++;
    }
    while (match < matches.length && matches[match].$2 <= start) {
      match++;
    }
    final color =
        segment < segments.length && segments[segment].$1 <= start
            ? segments[segment].$3
            : null;
    final highlighted = match < matches.length && matches[match].$1 <= start;
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style:
            color == null && !highlighted
                ? null
                : TextStyle(
                  color: color,
                  backgroundColor: highlighted ? highlight : null,
                ),
      ),
    );
  }
  return spans;
}

/// Splits [spans] at line breaks, so each line can be shown with a number.
List<List<TextSpan>> _splitLines(List<TextSpan> spans) {
  final lines = <List<TextSpan>>[[]];
  for (final span in spans) {
    final parts = (span.text ?? '').split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) lines.add([]);
      if (parts[i].isNotEmpty) {
        lines.last.add(TextSpan(text: parts[i], style: span.style));
      }
    }
  }
  return lines;
}
