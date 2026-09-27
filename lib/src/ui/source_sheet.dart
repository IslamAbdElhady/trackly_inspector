import 'package:flutter/material.dart';

import '../core/calls.dart';
import '../core/source_finder.dart';
import 'element_picker.dart';
import 'screens.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the user chose in the source sheet.
sealed class SourceAction {}

/// Open [call]'s details, highlighting [path] in its response.
class OpenCallAction extends SourceAction {
  /// Creates the action.
  OpenCallAction(this.call, {this.path, this.value});

  /// The call to open.
  final TracklyHttpCall call;

  /// The JSON path of the matched value, if any.
  final String? path;

  /// The matched value, if any.
  final String? value;
}

/// Go back to inspect mode to pick something else.
class InspectAgainAction extends SourceAction {}

/// Shows where a picked element's data came from.
class SourceSheet extends StatelessWidget {
  /// Creates the sheet.
  const SourceSheet({
    super.key,
    required this.picked,
    required this.matches,
    required this.screenCalls,
    required this.recentCalls,
  });

  /// What the user picked.
  final PickedElement picked;

  /// Calls whose responses contain the picked values, best first.
  final List<SourceMatch> matches;

  /// Calls made while the current screen was showing, newest first.
  final List<TracklyHttpCall> screenCalls;

  /// The most recent calls, newest first.
  final List<TracklyHttpCall> recentCalls;

  /// A route that slides the sheet up from the bottom.
  static Route<SourceAction> route(SourceSheet sheet) => PageRouteBuilder(
    settings: const RouteSettings(name: '$inspectorRoutePrefix/source'),
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    barrierLabel: 'Close',
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => InspectorScope(child: sheet),
    transitionsBuilder:
        (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = screenCalls.isNotEmpty ? screenCalls : recentCalls;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Material(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _Header(picked: picked),
                const Divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      if (matches.isNotEmpty) ...[
                        SectionTitle(
                          'Found in ${matches.length} '
                          '${matches.length == 1 ? 'request' : 'requests'}',
                        ),
                        for (final match in matches) _MatchTile(match: match),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Text(
                            recentCalls.isEmpty
                                ? 'No requests recorded yet.'
                                : "This value isn't in any response. The app "
                                    'may format or calculate it before '
                                    'showing it.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                        if (fallback.isNotEmpty) ...[
                          SectionTitle(
                            screenCalls.isNotEmpty
                                ? 'Requests from this screen'
                                : 'Recent requests',
                          ),
                          for (final call in fallback.take(10))
                            _CallTile(call: call),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.picked});

  final PickedElement picked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          Icon(
            picked.kind == 'Image'
                ? Icons.image_outlined
                : Icons.text_fields_rounded,
            color: colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  picked.kind.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  picked.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 13.5, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, InspectAgainAction()),
            icon: const Icon(Icons.ads_click, size: 18),
            label: const Text('Inspect again'),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match});

  final SourceMatch match;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final call = match.call;
    return InkWell(
      onTap:
          () => Navigator.pop(
            context,
            OpenCallAction(call, path: match.path, value: match.value),
          ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CallLine(call: call),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: displayPath(match.path),
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' = '),
                          TextSpan(text: match.value),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    match.count > 1
                        ? '${match.kind.label} · ${match.count}'
                        : match.kind.label,
                    style: TextStyle(fontSize: 11, color: colors.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});

  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, OpenCallAction(call)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: _CallLine(call: call),
      ),
    );
  }
}

class _CallLine extends StatelessWidget {
  const _CallLine({required this.call});

  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return Row(
      children: [
        MethodBadge(call.method),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(size: 13, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatTime(call.startTime).substring(0, 8),
          style: const TextStyle(fontSize: 12, color: grey),
        ),
        const SizedBox(width: 8),
        StatusBadge(call),
      ],
    );
  }
}
