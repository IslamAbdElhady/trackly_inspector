import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/src/core/json_filter.dart';
import 'package:trackly_inspector/src/core/source_finder.dart';

final _body = {
  'total': 4,
  'cars': [
    {
      'brand': 'BMW',
      'fuel': 'diesel',
      'engine': {'hp': 258, 'type': 'V6'},
      'tires': [
        {'size': 18},
        {'size': 18},
      ],
    },
    {
      'brand': 'Kia',
      'fuel': 'petrol',
      'engine': {'hp': 120},
      'tires': [
        {'size': 16},
      ],
    },
    {
      'brand': 'BMW',
      'fuel': null,
      'engine': {'hp': 190},
      'tires': <Object>[],
    },
    {
      'brand': 'Tesla',
      'engine': {'hp': 450},
      'tags': ['electric', 'fast'],
    },
  ],
  'dealers': [
    {'name': 'A'},
    {'name': 'B'},
  ],
};

FilterableList get _cars => findFilterableLists(_body).first;

List<String> _chips(FilterField field) => [
  for (final value in field.values) '${value.label} ${value.count}',
];

void main() {
  group('findFilterableLists', () {
    test('finds lists of objects, biggest first', () {
      final lists = findFilterableLists(_body);
      expect([for (final list in lists) list.path], [r'$.cars', r'$.dealers']);
      expect(lists.first.name, 'cars');
    });

    test('finds a body that is a list itself', () {
      final lists = findFilterableLists([
        {'id': 1},
        {'id': 2},
      ]);
      expect(lists.single.path, r'$');
      expect(lists.single.name, 'items');
    });

    test('finds lists inside objects at any depth', () {
      final lists = findFilterableLists({
        'data': {
          'page': {
            'items': [
              {'id': 1},
              {'id': 2},
            ],
          },
        },
      });
      expect(lists.single.path, r'$.data.page.items');
    });

    test('skips lists of values and lists with one object', () {
      expect(
        findFilterableLists({
          'ids': [1, 2, 3],
          'one': [
            {'id': 1},
          ],
        }),
        isEmpty,
      );
    });
  });

  group('fields', () {
    test('names nested objects with dots and nested lists with []', () {
      expect(
        [for (final field in _cars.fields) field.name],
        ['brand', 'fuel', 'engine.hp', 'engine.type', 'tires[].size', 'tags[]'],
      );
    });

    test('counts each value, null, and the items missing the field', () {
      final fuel = _cars.field('fuel')!;
      expect(fuel.kind, FieldKind.chips);
      expect(_chips(fuel), ['diesel 1', 'petrol 1', 'null 1', 'missing 1']);
      expect(_chips(_cars.field('brand')!), ['BMW 2', 'Kia 1', 'Tesla 1']);
    });

    test('counts a value once per item', () {
      // The BMW has two 18" tires; the last two cars have none.
      expect(_chips(_cars.field('tires[].size')!), [
        '16 1',
        '18 1',
        'missing 2',
      ]);
    });

    test('gives numbers with many values a range', () {
      final list =
          findFilterableLists([
            for (var i = 1; i <= 10; i++) {'price': i * 1.5},
          ]).single;
      final price = list.field('price')!;
      expect(price.kind, FieldKind.number);
      expect(price.min, 1.5);
      expect(price.max, 15);
      expect(price.values, isEmpty);
    });

    test('gives values that no two items share a box or a range', () {
      final list =
          findFilterableLists([
            for (var i = 0; i < 5; i++)
              {'id': i, 'email': 'user$i@example.com'},
          ]).single;
      expect(list.field('id')!.kind, FieldKind.number);
      expect(list.field('email')!.kind, FieldKind.text);
    });

    test('gives text with many values a "contains" box', () {
      final list =
          findFilterableLists([
            for (var i = 0; i < 20; i++) {'name': 'User $i'},
            {'name': null},
          ]).single;
      final name = list.field('name')!;
      expect(name.kind, FieldKind.text);
      expect(name.distinct, 20);
      // Only null is offered as a chip.
      expect(_chips(name), ['null 1']);
    });
  });

  group('apply', () {
    List<int> apply(Map<String, FieldFilter> filters) => _cars.apply(filters);

    test('matches everything without filters', () {
      expect(apply({}), [0, 1, 2, 3]);
      expect(apply({'fuel': const FieldFilter()}), [0, 1, 2, 3]);
    });

    test('matches any chosen value of a field', () {
      expect(
        apply({
          'fuel': const FieldFilter(values: {'s:diesel'}),
        }),
        [0],
      );
      expect(
        apply({
          'fuel': const FieldFilter(values: {'s:diesel', 's:petrol'}),
        }),
        [0, 1],
      );
    });

    test('matches every field', () {
      expect(
        apply({
          'brand': const FieldFilter(values: {'s:BMW'}),
          'engine.hp': const FieldFilter(min: 200),
        }),
        [0],
      );
    });

    test('matches null and missing values', () {
      expect(
        apply({
          'fuel': const FieldFilter(values: {'null'}),
        }),
        [2],
      );
      expect(
        apply({
          'fuel': const FieldFilter(values: {missingKey}),
        }),
        [3],
      );
    });

    test('matches ranges of numbers', () {
      expect(apply({'engine.hp': const FieldFilter(min: 190, max: 300)}), [
        0,
        2,
      ]);
      expect(apply({'engine.hp': const FieldFilter(max: 150)}), [1]);
    });

    test('matches values inside nested lists', () {
      expect(
        apply({
          'tires[].size': const FieldFilter(values: {'n:16'}),
        }),
        [1],
      );
      expect(apply({'tags[]': const FieldFilter(text: 'ELEC')}), [3]);
    });

    test('matches text typed with Arabic digits', () {
      expect(apply({'engine.hp': const FieldFilter(text: '٤٥')}), [3]);
    });

    test('tells text and numbers apart', () {
      expect(valueKey('4'), isNot(valueKey(4)));
    });
  });

  test('jsonLinePaths gives the path of every printed line', () {
    final json = {
      'a': 1,
      'b': {'c': <Object>[], 'd': <String, Object>{}},
      'e': [
        1,
        {'f': true},
      ],
    };
    final printed = const JsonEncoder.withIndent('  ').convert(json);
    final paths = jsonLinePaths(json);
    expect(paths, hasLength('\n'.allMatches(printed).length + 1));
    expect(paths, [
      r'$',
      r'$.a',
      r'$.b',
      r'$.b.c',
      r'$.b.d',
      r'$.b',
      r'$.e',
      r'$.e[0]',
      r'$.e[1]',
      r'$.e[1].f',
      r'$.e[1]',
      r'$.e',
      r'$',
    ]);
  });
}
