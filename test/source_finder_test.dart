import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/src/core/source_finder.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

void main() {
  late TracklyInspectorController controller;

  setUp(() => controller = TracklyInspectorController());

  TracklyHttpCall call(String url, String? body, {int status = 200}) {
    final call =
        controller.startCall(
          client: 'test',
          method: 'GET',
          uri: Uri.parse(url),
        )!;
    controller.completeCall(call, statusCode: status, body: body);
    return call;
  }

  List<SourceMatch> find(
    List<String> texts, {
    List<String> imageUrls = const [],
  }) => findSources(
    texts: texts,
    imageUrls: imageUrls,
    calls: controller.calls.reversed.toList(),
  );

  test('finds the exact field a text came from', () {
    call('https://api.dev/posts', '[{"id":1,"title":"Hello"}]');
    final user = call(
      'https://api.dev/users/1',
      '{"data":{"user":{"name":"Leanne Graham","city":"Gwenborough"}}}',
    );

    final match = find(['Leanne Graham']).single;
    expect(match.call, same(user));
    expect(match.path, r'$.data.user.name');
    expect(displayPath(match.path), 'data.user.name');
    expect(match.kind, MatchKind.exact);
  });

  test('ignores case and extra spaces', () {
    call('https://api.dev/u', '{"name":"Leanne Graham"}');
    expect(find(['  LEANNE   graham ']).single.kind, MatchKind.exact);
  });

  test('matches formatted numbers and Arabic digits', () {
    call('https://api.dev/cart', '{"total":1250,"items":[{"qty":3}]}');

    expect(find(['EGP 1,250.00']).single.path, r'$.total');
    expect(find(['١٢٥٠ ج.م']).single.path, r'$.total');
    expect(find(['EGP 1,250.00']).single.kind, MatchKind.number);
  });

  test("doesn't read several numbers as one", () {
    call('https://api.dev/x', '{"a":1230}');
    expect(find(['12:30']), isEmpty);
    expect(find(['Order 12 of 30']), isEmpty);
  });

  test('matches text the app shortened', () {
    call('https://api.dev/p', '{"body":"quia et suscipit recusandae"}');
    final match = find(['quia et susc…']).single;
    expect(match.kind, MatchKind.prefix);
  });

  test('matches text that contains a value, or is part of one', () {
    call(
      'https://api.dev/u',
      '{"first":"Leanne","address":"12 Main St, Cairo"}',
    );

    expect(find(['Welcome, Leanne']).single.path, r'$.first');
    expect(find(['Cairo']).single.path, r'$.address');
    expect(find(['Cairo']).single.kind, MatchKind.partial);
  });

  test('matches image URLs in responses and image requests', () {
    const url = 'https://cdn.dev/avatar.png';
    call('https://api.dev/me', '{"avatar":"$url"}');
    call(url, '<binary: 10 bytes>');

    final matches = find(const [], imageUrls: [url]);
    expect(matches.map((m) => m.path), unorderedEquals([null, r'$.avatar']));
    expect(matches.every((m) => m.kind == MatchKind.url), isTrue);
  });

  test('searches text bodies that are not JSON', () {
    call('https://api.dev/page', '<h1>Welcome to Cairo Store</h1>');
    final match = find(['Cairo Store']).single;
    expect(match.path, r'$');
    expect(match.kind, MatchKind.partial);
  });

  test('ranks better matches first, then newer calls', () {
    final older = call('https://api.dev/a', '{"name":"Leanne Graham"}');
    final partial = call(
      'https://api.dev/b',
      '{"bio":"Leanne Graham is here"}',
    );
    final newer = call('https://api.dev/c', '{"n":"Leanne Graham"}');

    expect(find(['Leanne Graham']).map((m) => m.call), [newer, older, partial]);
  });

  test('counts every matching value in a call', () {
    call('https://api.dev/u', '{"a":"Leanne","b":{"c":"Leanne"}}');
    expect(find(['Leanne']).single.count, 2);
  });

  test('skips calls without a response', () {
    final pending =
        controller.startCall(
          client: 'test',
          method: 'GET',
          uri: Uri.parse('https://api.dev/slow'),
        )!;
    expect(pending.isPending, isTrue);
    expect(find(['anything']), isEmpty);
  });

  test('lists the paths leading to a value', () {
    expect(ancestorPaths(r'$.data.users[2].name'), [
      r'$',
      r'$.data',
      r'$.data.users',
      r'$.data.users[2]',
    ]);
    expect(displayPath(r'$[0].name'), '[0].name');
    expect(displayPath(r'$'), 'Body');
    expect(displayPath(null), 'Request URL');
  });
}
