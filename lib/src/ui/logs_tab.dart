import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:trackly_logger/trackly_logger.dart';

import '../core/calls.dart';
import 'theme.dart';
import 'widgets.dart';

/// The list of `trackly_logger` records, newest at the bottom.
class LogsTab extends StatefulWidget {
  /// Creates the tab.
  const LogsTab({super.key, required this.controller});

  /// Where the records come from.
  final TracklyInspectorController controller;

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> with AutomaticKeepAliveClientMixin {
  var _query = '';
  TracklyLevel? _minLevel;

  @override
  bool get wantKeepAlive => true;

  bool _matches(TracklyRecord record) {
    if (_minLevel != null && record.level < _minLevel!) return false;
    if (_query.isEmpty) return true;
    final query = normalizeQuery(_query);
    return record.message.toLowerCase().contains(query) ||
        (record.tag?.toLowerCase().contains(query) ?? false) ||
        ('${record.error ?? ''}').toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  hint: 'Search message, tag, or error',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              IconButton(
                tooltip: 'Clear logs',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: widget.controller.clearLogs,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              FilterPill(
                label: 'All',
                selected: _minLevel == null,
                onTap: () => setState(() => _minLevel = null),
              ),
              for (final level in TracklyLevel.values.skip(1))
                FilterPill(
                  label: '${level.label.toLowerCase()}+',
                  color: levelColor(level),
                  selected: _minLevel == level,
                  onTap: () => setState(() => _minLevel = level),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Divider(),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final all = widget.controller.logs;
              final records = all.reversed.where(_matches).toList();
              if (records.isEmpty) {
                return all.isEmpty
                    ? const EmptyState(
                      icon: Icons.notes_rounded,
                      title: 'No logs yet',
                      message:
                          'Logs from trackly_logger, like '
                          "trackly.info('…'), show up here.",
                    )
                    : const EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'No matching logs',
                    );
              }
              // Reversed so the newest record sits at the bottom, like a
              // console, and the list starts scrolled to it.
              return ListView.separated(
                reverse: true,
                itemCount: records.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder:
                    (context, index) => _LogTile(record: records[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LogTile extends StatefulWidget {
  const _LogTile({required this.record});

  final TracklyRecord record;

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  var _expanded = false;

  static const _plain = TracklyConsoleOutput(colors: false);

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final colors = Theme.of(context).colorScheme;
    final color = levelColor(record.level);
    final extra = record.extra;
    final hasDetails =
        record.caller != null ||
        (extra != null && extra.isNotEmpty) ||
        record.error != null ||
        record.stackTrace != null;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      onLongPress:
          () =>
              copyText(context, _plain.format(record).join('\n'), 'Log copied'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(record.level.emoji, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  record.level.label,
                  style: mono(size: 11, color: color, weight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  formatTime(record.time),
                  style: mono(size: 11, color: colors.outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.tag ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                      size: 11,
                      color: colors.primary,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasDetails)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.outline,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              record.message,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: mono(size: 12.5, color: colors.onSurface),
            ),
            if (_expanded && hasDetails) ...[
              const SizedBox(height: 8),
              if (record.caller != null)
                _Detail('at', record.caller!, colors.outline),
              if (extra != null && extra.isNotEmpty)
                _Detail(
                  'extra',
                  const JsonEncoder.withIndent(
                    '  ',
                  ).convert(extra.map((k, v) => MapEntry(k, '$v'))),
                  colors.onSurfaceVariant,
                ),
              if (record.error != null)
                _Detail('error', '${record.error}', red),
              if (record.stackTrace != null)
                _Detail(
                  'stack',
                  '${record.stackTrace}'.trimRight(),
                  colors.onSurfaceVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: mono(size: 11, color: grey, weight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: mono(size: 11.5, color: color)),
          ),
        ],
      ),
    );
  }
}
