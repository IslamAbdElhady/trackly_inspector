import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calls.dart';
import 'theme.dart';

/// Gives an inspector page its own theme, English localizations, left-to-right
/// layout, and snack bars, independent of the host app.
class InspectorScope extends StatelessWidget {
  /// Wraps [child] in the inspector's scope.
  const InspectorScope({super.key, required this.child});

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Localizations(
      locale: const Locale('en', 'US'),
      delegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Theme(
        data: inspectorTheme(brightness),
        child: ScaffoldMessenger(child: child),
      ),
    );
  }
}

/// Copies [text] and shows [message] in a snack bar.
Future<void> copyText(BuildContext context, String text, String message) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}

/// Lower-cases [query] and turns Arabic-Indic digits (٠١٢…) into ASCII
/// digits, so searches typed on an Arabic keyboard still match.
String normalizeQuery(String query) {
  final buffer = StringBuffer();
  for (final rune in query.toLowerCase().runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// A compact search field.
class SearchField extends StatefulWidget {
  /// Creates a search field that reports every change to [onChanged].
  const SearchField({super.key, required this.hint, required this.onChanged});

  /// The placeholder text.
  final String hint;

  /// Called with the new query.
  final ValueChanged<String> onChanged;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value);
      },
      style: const TextStyle(fontSize: 14),
      autocorrect: false,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon:
            _controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A small filter chip.
class FilterPill extends StatelessWidget {
  /// Creates a chip showing [label], highlighted when [selected].
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  /// The chip text.
  final String label;

  /// Whether the chip is active.
  final bool selected;

  /// Called when the chip is tapped.
  final VoidCallback onTap;

  /// The accent color, or the theme's primary color if `null`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = color ?? colors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color:
            selected
                ? accent.withValues(alpha: 0.16)
                : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? accent : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A colored HTTP method label, e.g. `GET`.
class MethodBadge extends StatelessWidget {
  /// Creates a badge for [method].
  const MethodBadge(this.method, {super.key});

  /// The HTTP method.
  final String method;

  @override
  Widget build(BuildContext context) {
    final color = methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: mono(size: 11, color: color, weight: FontWeight.w700),
      ),
    );
  }
}

/// A call's status code, error, or progress indicator.
class StatusBadge extends StatelessWidget {
  /// Creates a badge for [call].
  const StatusBadge(this.call, {super.key});

  /// The call.
  final TracklyHttpCall call;

  @override
  Widget build(BuildContext context) {
    if (call.isPending) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final color = statusColor(call);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        call.statusCode?.toString() ?? 'ERR',
        style: mono(size: 11.5, color: Colors.white, weight: FontWeight.w700),
      ),
    );
  }
}

/// A bold section title.
class SectionTitle extends StatelessWidget {
  /// Creates a title with optional [trailing] actions.
  const SectionTitle(this.title, {super.key, this.trailing});

  /// The title text.
  final String title;

  /// Widgets shown at the end of the row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Rows of names and values, e.g. headers. Tap a row to copy its value.
class KeyValueTable extends StatelessWidget {
  /// Creates a table of [entries], or shows [emptyText] if there are none.
  const KeyValueTable(this.entries, {super.key, this.emptyText = 'None'});

  /// The rows.
  final List<MapEntry<String, String>> entries;

  /// Shown when [entries] is empty.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(emptyText, style: TextStyle(color: colors.outline)),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0) const Divider(height: 1, indent: 12),
            InkWell(
              onTap:
                  () => copyText(context, entry.value, 'Copied ${entry.key}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        entry.key,
                        style: mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: mono(size: 12, color: colors.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A centered icon and message for empty lists.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  /// The icon.
  final IconData icon;

  /// The main text.
  final String title;

  /// Optional detail below [title].
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
