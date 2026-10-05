import 'package:flutter/material.dart';

import '../core/body.dart';
import '../core/calls.dart';
import 'body_view.dart';
import 'screens.dart';
import 'theme.dart';
import 'widgets.dart';

/// The details of one call: overview, request, and response.
class CallPage extends StatelessWidget {
  /// Creates a page for [call], rebuilt when [controller] changes.
  const CallPage({
    super.key,
    required this.controller,
    required this.call,
    this.initialTab = 0,
    this.highlightPath,
    this.highlightValue,
  });

  /// Notifies when [call] gets its response.
  final TracklyInspectorController controller;

  /// The call to show.
  final TracklyHttpCall call;

  /// The tab to open: 0 for Overview, 1 for Request, 2 for Response.
  final int initialTab;

  /// A JSON path in the response to reveal and highlight.
  final String? highlightPath;

  /// A value to highlight when the response isn't JSON.
  final String? highlightValue;

  /// A route to this page.
  static Route<void> route(
    TracklyInspectorController controller,
    TracklyHttpCall call, {
    int initialTab = 0,
    String? highlightPath,
    String? highlightValue,
  }) => MaterialPageRoute(
    settings: const RouteSettings(name: '$inspectorRoutePrefix/call'),
    builder:
        (_) => InspectorScope(
          child: CallPage(
            controller: controller,
            call: call,
            initialTab: initialTab,
            highlightPath: highlightPath,
            highlightValue: highlightValue,
          ),
        ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => DefaultTabController(
            length: 3,
            initialIndex: initialTab,
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Row(
                  children: [
                    MethodBadge(call.method),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        call.uri.path.isEmpty ? '/' : call.uri.path,
                        overflow: TextOverflow.ellipsis,
                        style: mono(size: 14, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Copy as cURL',
                    icon: const Icon(Icons.terminal_rounded),
                    onPressed:
                        () => copyText(
                          context,
                          call.toCurl(),
                          'cURL command copied',
                        ),
                  ),
                  _CopyMenu(call: call),
                ],
                bottom: const TabBar(
                  labelStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(fontSize: 15),
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Request'),
                    Tab(text: 'Response'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _Overview(call: call),
                  _Request(call: call),
                  _Response(
                    call: call,
                    highlightPath: highlightPath,
                    highlightValue: highlightValue,
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _CopyMenu extends StatelessWidget {
  const _CopyMenu({required this.call});

  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'More copy options',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder:
          (_) => [
            PopupMenuItem(
              value: () => copyText(context, '${call.uri}', 'URL copied'),
              child: const Text('Copy URL'),
            ),
            if (call.requestBody != null)
              PopupMenuItem(
                value:
                    () => copyText(
                      context,
                      call.requestBody!,
                      'Request body copied',
                    ),
                child: const Text('Copy request body'),
              ),
            if (call.responseBody != null)
              PopupMenuItem(
                value:
                    () => copyText(
                      context,
                      call.responseBody!,
                      'Response body copied',
                    ),
                child: const Text('Copy response body'),
              ),
            PopupMenuItem(
              value:
                  () => copyText(context, _report(call), 'Call details copied'),
              child: const Text('Copy all details'),
            ),
          ],
    );
  }

  static String _report(TracklyHttpCall call) {
    String headers(Map<String, String> map) =>
        map.isEmpty
            ? '  (none)'
            : map.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');
    return [
      '${call.method} ${call.uri}',
      'Status: ${call.statusCode ?? call.error ?? 'pending'}',
      'Duration: ${formatDuration(call.duration)}',
      '',
      'Request headers:',
      headers(call.requestHeaders),
      if (call.requestBody != null) ...['', 'Request body:', call.requestBody!],
      '',
      'Response headers:',
      headers(call.responseHeaders),
      if (call.responseBody != null) ...[
        '',
        'Response body:',
        call.responseBody!,
      ],
    ].join('\n');
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.call});

  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = statusColor(call);
    final status =
        call.isPending
            ? 'In progress'
            : call.statusCode != null
            ? '${call.statusCode} ${call.reasonPhrase ?? ''}'.trim()
            : 'Failed';

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(
                call.isPending
                    ? Icons.hourglass_top_rounded
                    : call.isFailure
                    ? Icons.error_rounded
                    : Icons.check_circle_rounded,
                color: color,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDuration(call.duration)}  ·  '
                      '${formatBytes(call.responseSize)}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (call.error != null) ...[
          const SectionTitle('Error'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(call.error!, style: mono(color: red)),
          ),
        ],
        const SectionTitle('General'),
        KeyValueTable([
          MapEntry('URL', '${call.uri}'),
          MapEntry('Method', call.method),
          MapEntry('Status', status),
          MapEntry('Client', call.client),
          if (screenNameOf(call) case final screen?) MapEntry('Screen', screen),
          MapEntry('Started', formatTime(call.startTime)),
          if (call.endTime != null)
            MapEntry('Finished', formatTime(call.endTime!)),
          MapEntry('Duration', formatDuration(call.duration)),
          MapEntry('Request size', formatBytes(call.requestSize)),
          MapEntry('Response size', formatBytes(call.responseSize)),
        ]),
        SectionTitle(
          'cURL',
          trailing: IconButton(
            tooltip: 'Copy as cURL',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed:
                () => copyText(context, call.toCurl(), 'cURL command copied'),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            call.toCurl(),
            style: mono(size: 13, color: const Color(0xFFE5E7EB)),
          ),
        ),
      ],
    );
  }
}

class _Request extends StatelessWidget {
  const _Request({required this.call});

  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    final query = [
      for (final entry in call.uri.queryParametersAll.entries)
        for (final value in entry.value) FieldRow(entry.key, value),
    ];
    final hasBody = call.requestBody != null || call.requestFormData != null;

    return _Parts(
      initial: hasBody ? 2 : (query.isNotEmpty ? 0 : 1),
      parts: [
        _Part(
          'Params',
          query.length,
          (_) => _TablePart(rows: query, emptyText: 'No query parameters'),
        ),
        _Part(
          'Headers',
          call.requestHeaders.length,
          (_) => _TablePart(
            rows: [
              for (final header in call.requestHeaders.entries)
                FieldRow(header.key, header.value),
            ],
            emptyText: 'No headers',
          ),
        ),
        _Part(
          'Body',
          null,
          (_) => BodyView(
            body: call.requestBody,
            title: 'Request body',
            contentType: headerValue(call.requestHeaders, 'content-type'),
            formData: call.requestFormData,
            size: call.requestSize,
          ),
        ),
      ],
    );
  }
}

class _Response extends StatelessWidget {
  const _Response({
    required this.call,
    this.highlightPath,
    this.highlightValue,
  });

  final TracklyHttpCall call;
  final String? highlightPath;
  final String? highlightValue;

  @override
  Widget build(BuildContext context) {
    if (call.isPending) {
      return const EmptyState(
        icon: Icons.hourglass_top_rounded,
        title: 'Waiting for the response…',
      );
    }
    if (call.statusCode == null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No response',
        message: call.error,
      );
    }
    return _Parts(
      parts: [
        _Part(
          'Body',
          null,
          (_) => BodyView(
            body: call.responseBody,
            title: 'Response body',
            contentType: headerValue(call.responseHeaders, 'content-type'),
            size: call.responseSize,
            highlightPath: highlightPath,
            highlightValue: highlightValue,
          ),
        ),
        _Part(
          'Headers',
          call.responseHeaders.length,
          (_) => _TablePart(
            rows: [
              for (final header in call.responseHeaders.entries)
                FieldRow(header.key, header.value),
            ],
            emptyText: 'No headers',
          ),
        ),
      ],
    );
  }
}

class _Part {
  const _Part(this.label, this.count, this.builder);

  final String label;
  final int? count;
  final WidgetBuilder builder;
}

/// Postman-style tabs inside a request or response, e.g. Params, Headers, and
/// Body. Each part keeps its state when switching.
class _Parts extends StatefulWidget {
  const _Parts({required this.parts, this.initial = 0});

  final List<_Part> parts;
  final int initial;

  @override
  State<_Parts> createState() => _PartsState();
}

class _PartsState extends State<_Parts> {
  late var _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              for (final (index, part) in widget.parts.indexed)
                FilterPill(
                  label:
                      part.count == null
                          ? part.label
                          : '${part.label}  ${part.count}',
                  selected: index == _selected,
                  onTap: () => setState(() => _selected = index),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: _selected,
            children: [
              for (final part in widget.parts) Builder(builder: part.builder),
            ],
          ),
        ),
      ],
    );
  }
}

class _TablePart extends StatelessWidget {
  const _TablePart({required this.rows, required this.emptyText});

  final List<FieldRow> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: [FieldTable(rows: rows, emptyText: emptyText)],
    );
  }
}
