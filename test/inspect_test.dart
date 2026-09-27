import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

TracklyInspectorController get controller => TracklyInspector.controller;

void addCall(String url, String body) {
  final call =
      controller.startCall(client: 'test', method: 'GET', uri: Uri.parse(url))!;
  controller.completeCall(
    call,
    statusCode: 200,
    headers: {'content-type': 'application/json'},
    body: body,
  );
}

const _banner = 'Touch any text or image to find its request';

void main() {
  var pressed = false;

  Widget app() => MaterialApp(
    builder: (context, child) => TracklyInspector(child: child!),
    home: Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 100),
          const Text('Leanne Graham'),
          const Text('Not from any request'),
          ElevatedButton(
            onPressed: () => pressed = true,
            child: const Text('Buy'),
          ),
        ],
      ),
    ),
  );

  setUp(() {
    pressed = false;
    controller
      ..clearCalls()
      ..clearLogs();
  });

  Future<void> startInspecting(WidgetTester tester) async {
    await tester.pumpWidget(app());
    addCall('https://api.dev/users/1', '{"id":1,"name":"Leanne Graham"}');
    addCall('https://api.dev/posts', '[{"id":1,"title":"Hello"}]');
    await tester.pump();
    TracklyInspector.inspect();
    await tester.pump();
  }

  testWidgets('finds the request a text came from', (tester) async {
    await startInspecting(tester);
    expect(find.text(_banner), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('Leanne Graham')));
    await tester.pumpAndSettle();

    expect(TracklyInspector.isInspecting, isFalse);
    expect(find.text('FOUND IN 1 REQUEST'), findsOneWidget);
    expect(find.text('/users/1'), findsOneWidget);
    expect(find.textContaining('name = Leanne Graham'), findsOneWidget);
  });

  testWidgets('opens the call with the matching field highlighted', (
    tester,
  ) async {
    await startInspecting(tester);
    await tester.tapAt(tester.getCenter(find.text('Leanne Graham')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('/users/1'));
    await tester.pumpAndSettle();

    // The Response tab opens on the JSON tree, with the field revealed.
    expect(find.text('Preview'), findsOneWidget);
    final row = find.ancestor(
      of: find.textContaining('"Leanne Graham"'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                const Color(0x55FACC15),
      ),
    );
    expect(row, findsOneWidget);
  });

  testWidgets('lists requests from this screen when nothing matches', (
    tester,
  ) async {
    await startInspecting(tester);
    await tester.tapAt(tester.getCenter(find.text('Not from any request')));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't in any response"), findsOneWidget);
    expect(find.text('REQUESTS FROM THIS SCREEN'), findsOneWidget);
    expect(find.text('/users/1'), findsOneWidget);
    expect(find.text('/posts'), findsOneWidget);
  });

  testWidgets("touches don't reach the app while inspecting", (tester) async {
    await startInspecting(tester);
    await tester.tapAt(tester.getCenter(find.text('Buy')));
    await tester.pumpAndSettle();

    expect(pressed, isFalse);
  });

  testWidgets('can inspect again from the results', (tester) async {
    await startInspecting(tester);
    await tester.tapAt(tester.getCenter(find.text('Leanne Graham')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inspect again'));
    await tester.pumpAndSettle();
    expect(find.text(_banner), findsOneWidget);
  });

  testWidgets('the close button leaves inspect mode', (tester) async {
    await startInspecting(tester);
    await tester.tap(find.bySemanticsLabel('Stop inspecting'));
    await tester.pumpAndSettle();

    expect(find.text(_banner), findsNothing);
    await tester.tap(find.text('Buy'));
    expect(pressed, isTrue);
  });

  testWidgets('long-pressing the bubble starts inspect mode', (tester) async {
    await tester.pumpWidget(app());
    await tester.longPress(find.byIcon(Icons.radar_rounded));
    await tester.pumpAndSettle();

    expect(TracklyInspector.isInspecting, isTrue);
    expect(find.text(_banner), findsOneWidget);
  });

  testWidgets('the arrow in the inspector starts inspect mode', (tester) async {
    await tester.pumpWidget(app());
    TracklyInspector.show();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Inspect an element'));
    await tester.pumpAndSettle();

    expect(TracklyInspector.isOpen, isFalse);
    expect(find.text(_banner), findsOneWidget);
  });

  testWidgets('shows which screen made a call', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TracklyInspector(child: child!),
        initialRoute: '/products',
        routes: {'/products': (_) => const Scaffold(body: Text('Products'))},
      ),
    );
    addCall('https://api.dev/products', '[]');
    await tester.pump();

    TracklyInspector.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('/products'));
    await tester.pumpAndSettle();

    expect(find.text('Screen'), findsOneWidget);
  });
}
