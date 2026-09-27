import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/source_finder.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Mode { tree, raw }

/// Shows a request or response body as a sliver, with a collapsible tree for
/// JSON, a raw view with syntax colors, search, and copy.
class BodyView extends StatefulWidget {
  /// Creates a view of [body].
  const BodyView({
    super.key,
    required this.body,
    required this.title,
    this.highlightPath,
    this.highlightValue,
  });

  /// The body text.
  final String? body;

  /// Used in the "copied" message, e.g. `Response body`.
  final String title;

  /// A JSON path, e.g. `$.data.name`, to reveal, highlight, and scroll to.
  final String? highlightPath;

  /// Text to search for when the body isn't JSON.
  final String? highlightValue;

  @override
  State<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<BodyView> {
  static const _highlightLimit = 150000;

  Object? _json;
  bool _isJson = false;
  String _pretty = '';
  var _mode = _Mode.tree;
  var _searching = false;
  var _query = '';
  final _expanded = <String>{r'$'};
  final _highlightKey = GlobalKey();
  var _revealed = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(BodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _parse();
  }

  void _parse() {
    final body = widget.body;
    _isJson = false;
    _pretty = body ?? '';
    if (body == null) return;
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return;
    try {
      _json = jsonDecode(body);
      _isJson = true;
      _pretty = const JsonEncoder.withIndent('  ').convert(_json);
      final json = _json;
      final highlight = widget.highlightPath;
      if (highlight != null) {
        // Open just the objects and arrays that lead to the highlighted value.
        _mode = _Mode.tree;
        _expanded
          ..clear()
          ..add(r'$')
          ..addAll(ancestorPaths(highlight));
      } else if (json is Map && json.length <= 30) {
        // Open the first level of small documents.
        for (final key in json.keys) {
          _expanded.add('\$.$key');
        }
      }
    } on FormatException {
      _isJson = false;
    }
    final value = widget.highlightValue;
    if (!_isJson && value != null && value.isNotEmpty) {
      _searching = true;
      _query = value;
    }
  }

  /// Scrolls the highlighted row into view once it's laid out. Rows far down
  /// aren't built yet, so first jump near where it should be.
  void _reveal(int index) {
    if (_revealed) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_highlightKey.currentContext == null) {
        final position = Scrollable.maybeOf(context)?.position;
        if (position == null) return;
        position.jumpTo(
          (index * 26.0).clamp(0, position.maxScrollExtent).toDouble(),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      final row = _highlightKey.currentContext;
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
    final body = widget.body;
    if (body == null || body.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('No body', style: TextStyle(color: grey)),
        ),
      );
    }

    final showTree = _isJson && _mode == _Mode.tree && !_searching;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _toolbar(context)),
        if (showTree) _tree(context) else _raw(context),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Column(
        children: [
          Row(
            children: [
              if (_isJson)
                SegmentedButton<_Mode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: _Mode.tree, label: Text('Preview')),
                    ButtonSegment(value: _Mode.raw, label: Text('Raw')),
                  ],
                  selected: {_searching ? _Mode.raw : _mode},
                  onSelectionChanged:
                      (selection) => setState(() {
                        _mode = selection.first;
                        _searching = false;
                        _query = '';
                      }),
                ),
              const Spacer(),
              if (_isJson && _mode == _Mode.tree && !_searching) ...[
                IconButton(
                  tooltip: 'Expand all',
                  icon: const Icon(Icons.unfold_more, size: 20),
                  onPressed: () => setState(_expandAll),
                ),
                IconButton(
                  tooltip: 'Collapse all',
                  icon: const Icon(Icons.unfold_less, size: 20),
                  onPressed:
                      () => setState(() {
                        _expanded
                          ..clear()
                          ..add(r'$');
                      }),
                ),
              ],
              IconButton(
                tooltip: 'Search in body',
                isSelected: _searching,
                icon: const Icon(Icons.manage_search, size: 22),
                onPressed:
                    () => setState(() {
                      _searching = !_searching;
                      _query = '';
                    }),
              ),
              IconButton(
                tooltip: 'Copy body',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed:
                    () => copyText(
                      context,
                      _isJson ? _pretty : widget.body!,
                      '${widget.title} copied',
                    ),
              ),
            ],
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
                        style: const TextStyle(fontSize: 12.5, color: grey),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

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
    if (_query.isEmpty) return const [];
    final text = _pretty.toLowerCase();
    final query = normalizeQuery(_query);
    final matches = <(int, int)>[];
    var index = text.indexOf(query);
    while (index != -1 && matches.length < 5000) {
      matches.add((index, index + query.length));
      index = text.indexOf(query, index + query.length);
    }
    return matches;
  }

  Widget _raw(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = _pretty;
    final segments =
        _isJson && text.length <= _highlightLimit
            ? _jsonSegments(text, _JsonColors.of(dark))
            : const <_Segment>[];
    final spans = _spans(
      text,
      segments,
      _matches(),
      dark ? const Color(0x99A16207) : const Color(0xFFFDE68A),
    );

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText.rich(
          TextSpan(style: mono(color: colors.onSurface), children: spans),
        ),
      ),
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
    final highlightIndex = nodes.indexWhere(
      (node) => node.path == widget.highlightPath,
    );
    if (highlightIndex != -1) _reveal(highlightIndex);
    final colors = _JsonColors.of(
      Theme.of(context).brightness == Brightness.dark,
    );

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList.builder(
        itemCount: nodes.length,
        itemBuilder:
            (context, index) => _NodeRow(
              key: index == highlightIndex ? _highlightKey : null,
              highlighted: index == highlightIndex,
              node: nodes[index],
              expanded: _expanded.contains(nodes[index].path),
              colors: colors,
              onToggle:
                  () => setState(() {
                    final path = nodes[index].path;
                    if (!_expanded.remove(path)) _expanded.add(path);
                  }),
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
    required this.onToggle,
  });

  final bool highlighted;
  final _Node node;
  final bool expanded;
  final _JsonColors colors;
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
        padding: EdgeInsets.only(left: node.depth * 16.0, top: 3, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child:
                  node.isContainer
                      ? Icon(
                        expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 18,
                        color: grey,
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
                          color: isList ? grey : colors.key,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ': ', style: TextStyle(color: grey)),
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
        style: const TextStyle(color: grey),
      ),
      Map() || List() => TextSpan(
        text: _preview(value),
        style: const TextStyle(color: grey),
      ),
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
