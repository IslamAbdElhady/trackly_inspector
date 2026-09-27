import 'package:flutter/material.dart';

import '../core/calls.dart';
import 'call_page.dart';
import 'theme.dart';
import 'widgets.dart';

enum _StatusFilter {
  all('All'),
  success('2xx'),
  redirect('3xx'),
  clientError('4xx'),
  serverError('5xx'),
  failed('Failed'),
  pending('Pending');

  const _StatusFilter(this.label);

  final String label;

  bool matches(TracklyHttpCall call) {
    final code = call.statusCode ?? 0;
    return switch (this) {
      all => true,
      success => code >= 200 && code < 300,
      redirect => code >= 300 && code < 400,
      clientError => code >= 400 && code < 500,
      serverError => code >= 500,
      failed => call.error != null && call.statusCode == null,
      pending => call.isPending,
    };
  }
}

const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// The list of recorded calls, with search and filters.
class NetworkTab extends StatefulWidget {
  /// Creates the tab.
  const NetworkTab({super.key, required this.controller});

  /// Where the calls come from.
  final TracklyInspectorController controller;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab>
    with AutomaticKeepAliveClientMixin {
  var _query = '';
  var _status = _StatusFilter.all;
  String? _method;

  @override
  bool get wantKeepAlive => true;

  bool _matches(TracklyHttpCall call) {
    if (!_status.matches(call)) return false;
    if (_method != null && call.method != _method) return false;
    if (_query.isEmpty) return true;
    final query = normalizeQuery(_query);
    return '${call.method} ${call.uri} ${call.statusCode ?? ''}'
            .toLowerCase()
            .contains(query) ||
        (call.requestBody?.toLowerCase().contains(query) ?? false) ||
        (call.responseBody?.toLowerCase().contains(query) ?? false);
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
                  hint: 'Search URL, status, or body',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              IconButton(
                tooltip: 'Clear requests',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: widget.controller.clearCalls,
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
              for (final filter in _StatusFilter.values)
                FilterPill(
                  label: filter.label,
                  selected: _status == filter,
                  onTap: () => setState(() => _status = filter),
                ),
              const VerticalDivider(width: 14, indent: 6, endIndent: 6),
              for (final method in _methods)
                FilterPill(
                  label: method,
                  color: methodColor(method),
                  selected: _method == method,
                  onTap:
                      () => setState(
                        () => _method = _method == method ? null : method,
                      ),
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
              final all = widget.controller.calls;
              final calls = all.reversed.where(_matches).toList();
              if (calls.isEmpty) {
                return all.isEmpty
                    ? const EmptyState(
                      icon: Icons.wifi_tethering_rounded,
                      title: 'No requests yet',
                      message:
                          'Add TracklyDioInterceptor to Dio, or use '
                          'TracklyHttpClient, and requests will show up here.',
                    )
                    : const EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'No matching requests',
                    );
              }
              return ListView.separated(
                itemCount: calls.length,
                separatorBuilder: (_, _) => const Divider(indent: 12),
                itemBuilder:
                    (context, index) => _CallTile(
                      call: calls[index],
                      onTap:
                          () => Navigator.of(context).push(
                            CallPage.route(widget.controller, calls[index]),
                          ),
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call, required this.onTap});

  final TracklyHttpCall call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    final query = call.uri.hasQuery ? '?${call.uri.query}' : '';
    final meta = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Align(
                alignment: Alignment.centerLeft,
                child: MethodBadge(call.method),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: path),
                        TextSpan(
                          text: query,
                          style: TextStyle(color: colors.outline),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 13, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatTime(call.startTime).substring(0, 8)}  ·  ${call.uri.host}',
                    style: meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (call.error != null && call.statusCode == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        call.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: red),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(call),
                const SizedBox(height: 5),
                Text(formatDuration(call.duration), style: meta),
                Text(formatBytes(call.responseSize), style: meta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
