import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/calls.dart';
import '../core/performance.dart';
import 'call_page.dart';
import 'screens.dart';
import 'theme.dart';
import 'widgets.dart';

/// The screens the app showed, newest first, with how long each took to load
/// and how smoothly it drew.
class PerformanceTab extends StatefulWidget {
  /// Creates the tab.
  const PerformanceTab({super.key, required this.controller});

  /// Where the screens and their requests come from.
  final TracklyInspectorController controller;

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = widget.controller;
    final timeline = screenTimelineOf(controller);
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([timeline, controller]),
      builder: (context, _) {
        final visits = timeline.visits.reversed.toList();
        final budget = timeline.frameBudget;
        final hz = (1000000 / budget.inMicroseconds).round();
        return Column(
          children: [
            if (kDebugMode) const _DebugNotice(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        '$hz Hz · ${_ms(budget)} per frame',
                        if (timeline.memory case final memory?)
                          'Memory ${formatBytes(memory)}',
                      ].join('  ·  '),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear screens',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: controller.clearScreenVisits,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child:
                  visits.isEmpty
                      ? const EmptyState(
                        icon: Icons.speed_rounded,
                        title: 'No screens yet',
                        message: 'Screens show up here as the app opens them.',
                      )
                      : ListView.separated(
                        itemCount: visits.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder:
                            (context, index) => _VisitTile(
                              visit: visits[index],
                              onTap:
                                  () => Navigator.of(context).push(
                                    ScreenVisitPage.route(
                                      controller,
                                      visits[index],
                                    ),
                                  ),
                            ),
                      ),
            ),
          ],
        );
      },
    );
  }
}

class _DebugNotice extends StatelessWidget {
  const _DebugNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is a debug build, which is much slower than release. '
              'For real numbers, use a profile build.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.visit, required this.onTap});

  final TracklyScreenVisit visit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final meta = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final calls = visit.calls.length;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                      size: 14.5,
                      weight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatTime(visit.start).substring(0, 8)}  ·  '
                    '${visit.end == null ? 'showing' : formatDuration(visit.duration)}'
                    '  ·  $calls ${calls == 1 ? 'request' : 'requests'}',
                    style: meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  _FrameSummary(visit),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _LoadBadge(visit),
          ],
        ),
      ),
    );
  }
}

/// E.g. `248 frames · 12 slow · 1 frozen`, with the problems colored.
class _FrameSummary extends StatelessWidget {
  const _FrameSummary(this.visit);

  final TracklyScreenVisit visit;

  @override
  Widget build(BuildContext context) {
    final meta = TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final bold = meta.copyWith(fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        style: meta,
        children: [
          TextSpan(text: '${visit.frames} frames'),
          if (visit.slowFrames > 0)
            TextSpan(
              text: '  ·  ${visit.slowFrames} slow',
              style: bold.copyWith(color: orange),
            ),
          if (visit.frozenFrames > 0)
            TextSpan(
              text: '  ·  ${visit.frozenFrames} frozen',
              style: bold.copyWith(color: red),
            ),
          if (visit.frames > 0 && visit.slowFrames == 0)
            TextSpan(text: '  ·  smooth', style: bold.copyWith(color: green)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The screen's load time, colored by how long it took.
class _LoadBadge extends StatelessWidget {
  const _LoadBadge(this.visit);

  final TracklyScreenVisit visit;

  @override
  Widget build(BuildContext context) {
    final load = visit.loadCalls;
    if (load.isEmpty) return const SizedBox.shrink();
    final time = visit.loadTime;
    if (time == null) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final color = _loadColor(time);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        formatDuration(time),
        style: mono(size: 12.5, color: color, weight: FontWeight.w700),
      ),
    );
  }
}

/// The details of one screen visit: loading, requests, and frames.
class ScreenVisitPage extends StatelessWidget {
  /// Creates a page for [visit].
  const ScreenVisitPage({
    super.key,
    required this.controller,
    required this.visit,
  });

  /// Notifies when the visit's requests finish.
  final TracklyInspectorController controller;

  /// The visit to show.
  final TracklyScreenVisit visit;

  /// A route to this page.
  static Route<void> route(
    TracklyInspectorController controller,
    TracklyScreenVisit visit,
  ) => MaterialPageRoute(
    settings: const RouteSettings(name: '$inspectorRoutePrefix/screen'),
    builder:
        (_) => InspectorScope(
          child: ScreenVisitPage(controller: controller, visit: visit),
        ),
  );

  @override
  Widget build(BuildContext context) {
    final timeline = screenTimelineOf(controller);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          visit.name,
          overflow: TextOverflow.ellipsis,
          style: mono(size: 16, weight: FontWeight.w600),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([timeline, controller]),
        builder: (context, _) {
          final load = visit.loadCalls;
          final loadTime = visit.loadTime;
          final budget = visit.frameBudget;
          final frames = visit.frames;
          String share(int count) =>
              frames == 0 ? '$count' : '$count (${100 * count ~/ frames}%)';

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SectionTitle('Loading'),
              KeyValueTable([
                MapEntry(
                  'Loaded in',
                  load.isEmpty
                      ? 'No requests when it opened'
                      : loadTime == null
                      ? 'Loading…'
                      : formatDuration(loadTime),
                ),
                MapEntry(
                  'Requests',
                  '${load.length} when it opened, '
                      '${visit.calls.length} in total',
                ),
                MapEntry('Opened', formatTime(visit.start)),
                MapEntry(
                  'On screen for',
                  visit.end == null
                      ? 'Showing now'
                      : formatDuration(visit.duration),
                ),
              ]),
              if (visit.calls.isNotEmpty) ...[
                const SectionTitle('Requests'),
                _Waterfall(controller: controller, visit: visit),
              ],
              const SectionTitle('Frames'),
              KeyValueTable([
                MapEntry('Frames', '$frames'),
                MapEntry(
                  'Slow',
                  '${share(visit.slowFrames)}, over ${_ms(budget)}',
                ),
                MapEntry(
                  'Frozen',
                  '${share(visit.frozenFrames)}, over '
                      '${formatDuration(TracklyScreenVisit.frozenFrameTime)}',
                ),
                MapEntry('Average build', _ms(visit.averageBuild)),
                MapEntry('Average raster', _ms(visit.averageRaster)),
                if (visit.peakMemory case final memory?)
                  MapEntry('Peak memory', formatBytes(memory)),
              ]),
              if (visit.slowestFrames.isNotEmpty) ...[
                const SectionTitle('Slowest frames'),
                for (final frame in visit.slowestFrames)
                  _FrameRow(frame: frame, visit: visit),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The visit's requests as bars on a timeline from when the screen opened,
/// like the waterfall in a browser's Network tab.
class _Waterfall extends StatelessWidget {
  const _Waterfall({required this.controller, required this.visit});

  final TracklyInspectorController controller;
  final TracklyScreenVisit visit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final calls = visit.calls;
    final load = visit.loadCalls.toSet();
    final now = DateTime.now();
    var begin = visit.start;
    var finish = begin;
    for (final call in calls) {
      if (call.startTime.isBefore(begin)) begin = call.startTime;
      final end = call.endTime ?? now;
      if (end.isAfter(finish)) finish = end;
    }
    final span = math.max(finish.difference(begin).inMicroseconds, 1);
    double at(DateTime time) => time.difference(begin).inMicroseconds / span;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final call in calls)
          InkWell(
            onTap:
                () => Navigator.of(
                  context,
                ).push(CallPage.route(controller, call)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MethodBadge(call.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          call.uri.path.isEmpty ? '/' : call.uri.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(size: 13.5, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDuration(call.duration),
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final left = at(call.startTime) * width;
                      final right = at(call.endTime ?? now) * width;
                      final color = call.isPending ? grey : statusColor(call);
                      return Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.only(left: left),
                        child: Container(
                          width: math.max(right - left, 4),
                          decoration: BoxDecoration(
                            color:
                                load.contains(call)
                                    ? color
                                    : color.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Bars start when the screen opened. Faded bars came after it '
            'loaded.',
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _FrameRow extends StatelessWidget {
  const _FrameRow({required this.frame, required this.visit});

  final TracklyFrame frame;
  final TracklyScreenVisit visit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color =
        frame.total > TracklyScreenVisit.frozenFrameTime
            ? red
            : frame.build > visit.frameBudget ||
                frame.raster > visit.frameBudget
            ? orange
            : green;
    final offset = frame.time.difference(visit.start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '+${formatDuration(offset.isNegative ? Duration.zero : offset)}',
              style: mono(size: 13, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              'build ${_ms(frame.build)}  ·  raster ${_ms(frame.raster)}',
              style: TextStyle(fontSize: 13.5, color: colors.onSurface),
            ),
          ),
          Text(
            _ms(frame.total),
            style: mono(size: 13.5, color: color, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Color _loadColor(Duration time) =>
    time < const Duration(seconds: 1)
        ? green
        : time < const Duration(seconds: 3)
        ? orange
        : red;

/// Formats a duration in milliseconds with one decimal, e.g. `16.7 ms`.
String _ms(Duration? duration) =>
    duration == null
        ? '—'
        : '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';
