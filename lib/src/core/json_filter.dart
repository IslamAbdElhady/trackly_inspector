import 'text.dart';

/// The most items of a list that are read to build and apply filters.
const _maxItems = 20000;

/// How deep inside each item fields are looked for.
const _maxDepth = 5;

/// The most fields offered for a list.
const _maxFields = 60;

/// The most different values a text field can have and still be offered as
/// chips. Fields with more get a "contains" box instead.
const _maxChips = 12;

/// The most different values a number field can have and still be offered as
/// chips. Fields with more get a "from … to" range instead.
const _maxNumberChips = 6;

/// The most values a field can have that no two items share and still be
/// offered as chips.
const _maxUniqueChips = 3;

/// The value key of items that don't have a field at all.
const missingKey = 'missing';

/// Finds the lists of objects in [json] that can be filtered, e.g. the `cars`
/// in `{"cars": [{…}, {…}]}`, biggest first.
///
/// Only lists reached through objects count: lists inside a list's items are
/// fields of those items instead, e.g. `tires[].size`.
List<FilterableList> findFilterableLists(Object? json) {
  final lists = <FilterableList>[];
  void visit(Object? value, String path, int depth) {
    if (value is List) {
      final objects = value.whereType<Map<dynamic, dynamic>>().length;
      if (value.length >= 2 && objects * 2 >= value.length) {
        lists.add(FilterableList._(path, value));
      }
    } else if (value is Map && depth < _maxDepth) {
      for (final entry in value.entries) {
        visit(entry.value, '$path.${entry.key}', depth + 1);
      }
    }
  }

  visit(json, r'$', 0);
  // Biggest first, keeping the body's order for lists of the same size.
  final order = {for (var i = 0; i < lists.length; i++) lists[i]: i};
  return lists..sort((a, b) {
    final bySize = b.items.length.compareTo(a.items.length);
    return bySize != 0 ? bySize : order[a]!.compareTo(order[b]!);
  });
}

/// A list of objects in a JSON body that can be filtered by the fields its
/// items have.
class FilterableList {
  FilterableList._(this.path, this.items);

  /// The list's JSON path, e.g. `$.data.cars`.
  final String path;

  /// The list's items.
  final List<Object?> items;

  /// A short name for the items, e.g. `cars`, or `items` when the whole body
  /// is the list.
  String get name =>
      path == r'$' ? 'items' : path.substring(path.lastIndexOf('.') + 1);

  /// Each item's values, by field name.
  late final List<Map<String, List<Object?>>> _values = [
    for (final item in items.take(_maxItems)) _fieldValues(item),
  ];

  /// The fields the items have, in the order they first appear.
  late final List<FilterField> fields = _buildFields();

  late final Map<String, FilterField> _byName = {
    for (final field in fields) field.name: field,
  };

  /// The field called [name], if the items have it.
  FilterField? field(String name) => _byName[name];

  /// The indices of the items that match all of [filters], which are keyed by
  /// field name.
  List<int> apply(Map<String, FieldFilter> filters) {
    final active = [
      for (final entry in filters.entries)
        if (!entry.value.isEmpty) entry,
    ];
    return [
      for (var i = 0; i < _values.length; i++)
        if (active.every((entry) => entry.value.matches(_values[i][entry.key])))
          i,
    ];
  }

  List<FilterField> _buildFields() {
    final names = <String>[];
    final counts = <String, Map<String, int>>{};
    final samples = <String, Map<String, Object?>>{};
    final present = <String, int>{};
    for (final item in _values) {
      for (final MapEntry(key: name, value: values) in item.entries) {
        if (!counts.containsKey(name)) {
          if (names.length == _maxFields) continue;
          names.add(name);
          counts[name] = {};
          samples[name] = {};
        }
        present[name] = (present[name] ?? 0) + 1;
        // Count each value once per item, e.g. a car with four 18" tires.
        final seen = <String>{};
        for (final value in values) {
          final key = valueKey(value);
          if (seen.add(key)) {
            counts[name]![key] = (counts[name]![key] ?? 0) + 1;
            samples[name]!.putIfAbsent(key, () => value);
          }
        }
      }
    }
    return [
      for (final name in names)
        FilterField._(
          name,
          counts[name]!,
          samples[name]!,
          _values.length - present[name]!,
        ),
    ];
  }
}

/// The values of each field in [item], e.g. `{brand: [BMW],
/// engine.hp: [258], tires[].size: [18, 18, 18, 18]}`.
Map<String, List<Object?>> _fieldValues(Object? item) {
  final values = <String, List<Object?>>{};
  void visit(Object? value, String name, int depth) {
    if (value is Map) {
      if (depth == _maxDepth) return;
      for (final entry in value.entries) {
        visit(
          entry.value,
          name.isEmpty ? '${entry.key}' : '$name.${entry.key}',
          depth + 1,
        );
      }
    } else if (value is List) {
      if (depth == _maxDepth || name.isEmpty) return;
      for (final element in value) {
        visit(element, '$name[]', depth + 1);
      }
    } else if (name.isNotEmpty) {
      (values[name] ??= []).add(value);
    }
  }

  visit(item, '', 0);
  return values;
}

/// How a field is filtered.
enum FieldKind {
  /// By picking some of its values, shown as chips.
  chips,

  /// By a range of numbers.
  number,

  /// By text the value contains.
  text,
}

/// One value of a field, and how many items have it.
class FieldValue {
  const FieldValue._(this.key, this.label, this.count);

  /// Identifies the value in a [FieldFilter], e.g. `s:diesel` or `n:4`.
  final String key;

  /// The value as shown, e.g. `diesel`.
  final String label;

  /// How many items have the value.
  final int count;
}

/// A field of a [FilterableList]'s items, e.g. `engine.hp`, with the values
/// it has.
class FilterField {
  FilterField._(
    this.name,
    Map<String, int> counts,
    Map<String, Object?> samples,
    int missing,
  ) {
    final present = [
      for (final MapEntry(:key, :value) in samples.entries)
        if (value != null) (key, value),
    ];
    distinct = present.length;
    final numbers =
        present.isNotEmpty && present.every((entry) => entry.$2 is num);
    // Values that no two items share, like names, emails, and IDs, make
    // chips that each pick one item, so they get a box instead.
    final unique =
        distinct > _maxUniqueChips &&
        present.every((entry) => counts[entry.$1] == 1);
    if (numbers && (unique || distinct > _maxNumberChips)) {
      kind = FieldKind.number;
    } else if (unique) {
      kind = FieldKind.text;
    } else if (distinct <= _maxChips) {
      kind = FieldKind.chips;
    } else {
      kind = FieldKind.text;
    }
    final all = [
      if (kind == FieldKind.number)
        for (final (_, value) in present) value as num,
    ];
    min = all.isEmpty ? null : all.reduce((a, b) => a < b ? a : b);
    max = all.isEmpty ? null : all.reduce((a, b) => a > b ? a : b);

    final shown = [
      if (kind == FieldKind.chips)
        for (final (key, value) in present)
          FieldValue._(key, valueLabel(value), counts[key]!),
    ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
    values = [
      ...shown,
      if (counts['null'] case final nulls?) FieldValue._('null', 'null', nulls),
      if (missing > 0) FieldValue._(missingKey, missingKey, missing),
    ];
  }

  /// The field's name, e.g. `fuel`, `engine.hp`, or `tires[].size`.
  final String name;

  /// How the field is filtered.
  late final FieldKind kind;

  /// The values to offer as chips: every value for [FieldKind.chips], and
  /// for the other kinds just `null` and `missing`, if any items have them.
  late final List<FieldValue> values;

  /// How many different values other than `null` the field has.
  late final int distinct;

  /// The smallest value, for [FieldKind.number].
  late final num? min;

  /// The biggest value, for [FieldKind.number].
  late final num? max;

  /// The label of the value with [key], e.g. `diesel` for `s:diesel`.
  String labelOf(String key) =>
      values
          .firstWhere(
            (value) => value.key == key,
            orElse: () => FieldValue._(key, key, 0),
          )
          .label;
}

/// What a field's values must be for an item to match: any of the chosen
/// [values], or a number in a range, or text that contains [text].
class FieldFilter {
  /// Creates a filter. One with nothing chosen matches every item.
  const FieldFilter({
    this.values = const {},
    this.min,
    this.max,
    this.text = '',
  });

  /// The keys of the chosen values, from [FieldValue.key].
  final Set<String> values;

  /// The smallest number to match.
  final num? min;

  /// The biggest number to match.
  final num? max;

  /// Text the value must contain, in any case.
  final String text;

  /// Whether a range of numbers is set.
  bool get hasRange => min != null || max != null;

  /// Whether nothing is chosen, so it matches every item.
  bool get isEmpty =>
      values.isEmpty && !hasRange && normalizeText(text).isEmpty;

  /// Whether an item whose field has [found] values matches. `null` or empty
  /// means the item doesn't have the field.
  bool matches(List<Object?>? found) {
    if (isEmpty) return true;
    if (found == null || found.isEmpty) return values.contains(missingKey);
    return found.any(matchesValue);
  }

  /// Whether [value] is one this filter looks for.
  bool matchesValue(Object? value) {
    if (values.contains(valueKey(value))) return true;
    if (hasRange &&
        value is num &&
        (min == null || value >= min!) &&
        (max == null || value <= max!)) {
      return true;
    }
    final query = normalizeText(text);
    return query.isNotEmpty &&
        value != null &&
        normalizeText('$value').contains(query);
  }
}

/// A key that tells values of different types apart, so `"4"` isn't `4`.
String valueKey(Object? value) => switch (value) {
  null => 'null',
  String() => 's:$value',
  num() => 'n:$value',
  bool() => 'b:$value',
  _ => 'o:$value',
};

/// [value] as shown on a chip, shortened if it's long.
String valueLabel(Object? value) {
  final text = switch (value) {
    String() when value.isEmpty => '""',
    _ => '$value',
  };
  return text.length > 40 ? '${text.substring(0, 39)}…' : text;
}
