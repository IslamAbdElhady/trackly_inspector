import 'package:flutter/material.dart';

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
            style: mono(size: 12, color: const Color(0xFFE5E7EB)),
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
    final query =
        call.uri.queryParametersAll.entries
            .expand((e) => e.value.map((value) => MapEntry(e.key, value)))
            .toList();
    final form = call.requestFormData;

    return CustomScrollView(
      slivers: [
        if (query.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle('Query parameters (${query.length})'),
          ),
          SliverToBoxAdapter(child: KeyValueTable(query)),
        ],
        SliverToBoxAdapter(child: _Headers(call.requestHeaders)),
        if (form != null) ...[
          SliverToBoxAdapter(child: SectionTitle('Form data (${form.length})')),
          SliverToBoxAdapter(
            child: KeyValueTable([
              for (final field in form)
                MapEntry(
                  field.name,
                  field.isFile
                      ? '📎 ${field.fileName} (${formatBytes(field.fileSize)})'
                      : field.value ?? '',
                ),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ] else ...[
          const SliverToBoxAdapter(child: SectionTitle('Body')),
          BodyView(body: call.requestBody, title: 'Request body'),
        ],
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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Headers(call.responseHeaders)),
        const SliverToBoxAdapter(child: SectionTitle('Body')),
        BodyView(
          body: call.responseBody,
          title: 'Response body',
          highlightPath: highlightPath,
          highlightValue: highlightValue,
        ),
      ],
    );
  }
}

/// A headers table that collapses when there are many headers, so the body
/// stays in view.
class _Headers extends StatefulWidget {
  const _Headers(this.headers);

  final Map<String, String> headers;

  @override
  State<_Headers> createState() => _HeadersState();
}

class _HeadersState extends State<_Headers> {
  late var _expanded = widget.headers.length <= 6;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SectionTitle(
            'Headers (${widget.headers.length})',
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ),
          ),
        ),
        if (_expanded) KeyValueTable(widget.headers.entries.toList()),
      ],
    );
  }
}
