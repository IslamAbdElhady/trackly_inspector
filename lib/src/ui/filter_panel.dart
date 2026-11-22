// Flutter 3.50 deprecates these imports for the material_ui and
// cupertino_ui packages, which need Flutter 3.47 or later. Importing
// them from Flutter keeps older versions working.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/json_filter.dart';
import '../core/source_finder.dart';
import '../core/text.dart';
import 'theme.dart';
import 'widgets.dart';

/// Filters a list in a JSON body by the fields its items have. Every field
/// gets chips of its values, a "from … to" range, or a "contains" box,
/// depending on its values.
class FilterPanel extends StatelessWidget {
  /// Creates a panel for filtering [list].
  const FilterPanel({
    super.key,
    required this.lists,
    required this.list,
    required this.filters,
    required this.matches,
    required this.generation,
    required this.onList,
    required this.onChanged,
    required this.onClear,
    required this.onDone,
  });

  /// All the lists in the body that can be filtered.
  final List<FilterableList> lists;

  /// The list being filtered.
  final FilterableList list;

  /// The filters, keyed by field name.
  final Map<String, FieldFilter> filters;

  /// How many items match [filters].
  final int matches;

  /// Changes when the filters are cleared, so text boxes start empty again.
  final int generation;

  /// Called when another list is picked.
  final ValueChanged<FilterableList> onList;

  /// Called when a field's filter changes.
  final void Function(String field, FieldFilter filter) onChanged;

  /// Called to remove every filter.
  final VoidCallback onClear;

  /// Called to show the matching items.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fields = list.fields;
    final total = list.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
            children: [
              if (lists.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  runSpacing: 6,
                  children: [
                    for (final other in lists)
                      FilterPill(
                        label: displayPath(other.path),
                        count: other.items.length,
                        selected: identical(other, list),
                        onTap: () => onList(other),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
              ],
              if (fields.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'The ${list.name} have no fields to filter by.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _FieldSection(
                  key: ValueKey('$generation ${list.path} ${fields[i].name}'),
                  field: fields[i],
                  filter: filters[fields[i].name] ?? const FieldFilter(),
                  onChanged: (filter) => onChanged(fields[i].name, filter),
                ),
              ],
            ],
          ),
        ),
        const Divider(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                if (filters.values.any((filter) => !filter.isEmpty))
                  TextButton(onPressed: onClear, child: const Text('Clear')),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    onDone();
                  },
                  child: Text(
                    matches == total
                        ? 'Show all $total'
                        : 'Show $matches of $total',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({
    super.key,
    required this.field,
    required this.filter,
    required this.onChanged,
  });

  final FilterField field;
  final FieldFilter filter;
  final ValueChanged<FieldFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final warning =
        theme.brightness == Brightness.dark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFB45309);
    final hint = switch (field.kind) {
      FieldKind.number =>
        '${formatNumber(field.min)} to ${formatNumber(field.max)}',
      FieldKind.text => '${field.distinct} different',
      FieldKind.chips => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.name,
                  overflow: TextOverflow.ellipsis,
                  style: mono(
                    size: 14,
                    weight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (field.kind == FieldKind.number)
            _RangeInputs(
              min: filter.min,
              max: filter.max,
              onChanged:
                  (min, max) => onChanged(
                    FieldFilter(
                      values: filter.values,
                      min: min,
                      max: max,
                      text: filter.text,
                    ),
                  ),
            ),
          if (field.kind == FieldKind.text)
            SearchField(
              hint: 'Contains',
              icon: Icons.text_fields_rounded,
              initialValue: filter.text,
              onChanged:
                  (text) => onChanged(
                    FieldFilter(
                      values: filter.values,
                      min: filter.min,
                      max: filter.max,
                      text: text,
                    ),
                  ),
            ),
          if (field.values.isNotEmpty) ...[
            if (field.kind != FieldKind.chips) const SizedBox(height: 8),
            Wrap(
              runSpacing: 6,
              children: [
                for (final value in field.values)
                  FilterPill(
                    label: value.label,
                    count: value.count,
                    selected: filter.values.contains(value.key),
                    color:
                        value.key == missingKey || value.key == 'null'
                            ? warning
                            : null,
                    onTap:
                        () => onChanged(
                          FieldFilter(
                            values:
                                filter.values.contains(value.key)
                                    ? ({...filter.values}..remove(value.key))
                                    : {...filter.values, value.key},
                            min: filter.min,
                            max: filter.max,
                            text: filter.text,
                          ),
                        ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RangeInputs extends StatefulWidget {
  const _RangeInputs({
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final num? min;
  final num? max;
  final void Function(num? min, num? max) onChanged;

  @override
  State<_RangeInputs> createState() => _RangeInputsState();
}

class _RangeInputsState extends State<_RangeInputs> {
  late final _min = TextEditingController(text: formatNumber(widget.min));
  late final _max = TextEditingController(text: formatNumber(widget.max));

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _changed(String _) =>
      widget.onChanged(_parse(_min.text), _parse(_max.text));

  static num? _parse(String text) => num.tryParse(normalizeText(text));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget field(TextEditingController controller, String hint) => TextField(
      controller: controller,
      onChanged: _changed,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return Row(
      children: [
        Expanded(child: field(_min, 'From')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('to', style: TextStyle(color: colors.onSurfaceVariant)),
        ),
        Expanded(child: field(_max, 'To')),
      ],
    );
  }
}

/// A chip for a filter in use. Tapping it opens the filters, and its x
/// removes it.
class ActiveFilterChip extends StatelessWidget {
  /// Creates a chip showing [label].
  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  /// What the filter matches, e.g. `fuel: diesel`.
  final String label;

  /// Called when the chip is tapped.
  final VoidCallback onTap;

  /// Called when the x is tapped.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.16),
      shape: StadiumBorder(side: BorderSide(color: accent, width: 1.2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Remove filter',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 17, color: accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Describes [filter] on the field called [name], e.g. `fuel: diesel,
/// petrol` or `engine.hp: 200 to 450`.
String describeFilter(String name, FieldFilter filter, FilterField? field) {
  final min = filter.min;
  final max = filter.max;
  final text = filter.text.trim();
  final parts = [
    if (min != null && max != null)
      '${formatNumber(min)} to ${formatNumber(max)}'
    else if (min != null)
      '≥ ${formatNumber(min)}'
    else if (max != null)
      '≤ ${formatNumber(max)}',
    if (text.isNotEmpty) 'contains "$text"',
    for (final key in filter.values) field?.labelOf(key) ?? key,
  ];
  return '$name: ${parts.join(', ')}';
}

/// [number] without a needless `.0`, or nothing if it's `null`.
String formatNumber(num? number) {
  if (number == null) return '';
  if (number is double && number == number.truncateToDouble()) {
    if (number.abs() < 1e15) return number.toInt().toString();
  }
  return '$number';
}
