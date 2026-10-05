import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

TracklyInspectorController get controller => TracklyInspector.controller;

TracklyHttpCall addCall(
  String method,
  String url,
  int status, {
  String? responseBody,
}) {
  final call =
      controller.startCall(
        client: 'test',
        method: method,
        uri: Uri.parse(url),
        headers: {'Accept': 'application/json'},
      )!;
  controller.completeCall(
    call,
    statusCode: status,
    headers: {'content-type': 'application/json'},
    body: responseBody,
  );
  return call;
}

Widget app({Set<TracklyTrigger>? triggers}) => MaterialApp(
  builder:
      (context, child) => TracklyInspector(
        triggers:
            triggers ?? const {TracklyTrigger.bubble, TracklyTrigger.longPress},
        child: child!,
      ),
  home: const Scaffold(body: Center(child: Text('Home'))),
);

void main() {
  setUp(() {
    controller
      ..clearCalls()
      ..clearLogs();
  });

  testWidgets('opens from the bubble and lists calls', (tester) async {
    await tester.pumpWidget(app());
    addCall('GET', 'https://api.example.com/users', 200, responseBody: '[]');
    addCall('POST', 'https://api.example.com/orders', 500);
    await tester.pump();

    expect(find.text('2'), findsOneWidget); // The bubble's badge.
    await tester.tap(find.byIcon(Icons.radar_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Trackly Inspector'), findsOneWidget);
    expect(find.text('Network (2)'), findsOneWidget);
    expect(find.text('/users'), findsOneWidget);
    expect(find.text('/orders'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(TracklyInspector.isOpen, isTrue);
  });

  testWidgets('filters calls by search and status', (tester) async {
    await tester.pumpWidget(app());
    addCall('GET', 'https://api.example.com/users', 200);
    addCall('GET', 'https://api.example.com/orders', 404);
    TracklyInspector.show();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'orders');
    await tester.pumpAndSettle();
    expect(find.text('/users'), findsNothing);
    expect(find.text('/orders'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('2xx'));
    await tester.pumpAndSettle();
    expect(find.text('/users'), findsOneWidget);
    expect(find.text('/orders'), findsNothing);
  });

  testWidgets('shows call details and copies cURL', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(app());
    addCall(
      'GET',
      'https://api.example.com/users?page=2',
      200,
      responseBody: '{"name":"Ali","roles":["admin"]}',
    );
    TracklyInspector.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('/users?page=2'));
    await tester.pumpAndSettle();

    expect(find.text('200'), findsWidgets);

    await tester.tap(find.byIcon(Icons.terminal_rounded));
    await tester.pumpAndSettle();
    expect(copied, contains("curl 'https://api.example.com/users?page=2'"));
    expect(find.text('cURL command copied'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(find.text('Pretty'), findsOneWidget);
    expect(find.textContaining('"Ali"'), findsOneWidget);
  });

  testWidgets('shows trackly_logger logs', (tester) async {
    await tester.pumpWidget(app());
    const TracklyLogger('Auth').warning('Token expires soon');
    TracklyInspector.show();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logs (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Token expires soon'), findsOneWidget);

    // Expanding the log shows the full, clickable location.
    await tester.tap(find.text('Token expires soon'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'inspector_test\.dart:\d+:\d+$')),
      findsOneWidget,
    );
    expect(find.text('Auth'), findsOneWidget);
  });

  testWidgets('opens with a two-finger long press', (tester) async {
    await tester.pumpWidget(app());

    final first = await tester.startGesture(const Offset(100, 300));
    final second = await tester.startGesture(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 800));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(find.text('Trackly Inspector'), findsOneWidget);
  });

  testWidgets('ignores a one-finger long press', (tester) async {
    await tester.pumpWidget(app());

    final finger = await tester.startGesture(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 800));
    await finger.up();
    await tester.pumpAndSettle();

    expect(find.text('Trackly Inspector'), findsNothing);
  });

  testWidgets('hide() and the close button close the inspector', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    addCall('GET', 'https://api.example.com/users', 200);

    TracklyInspector.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();
    TracklyInspector.hide();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(TracklyInspector.isOpen, isFalse);

    TracklyInspector.show();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(TracklyInspector.isOpen, isFalse);
  });

  testWidgets('has no bubble when it is not a trigger', (tester) async {
    await tester.pumpWidget(app(triggers: const {}));
    expect(find.byIcon(Icons.radar_rounded), findsNothing);
  });

  testWidgets('works in right-to-left apps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: TracklyInspector(child: child!),
            ),
        home: const Scaffold(body: Text('الرئيسية')),
      ),
    );
    addCall('GET', 'https://api.example.com/users', 200);
    TracklyInspector.show();
    await tester.pumpAndSettle();

    final direction = Directionality.of(tester.element(find.text('/users')));
    expect(direction, TextDirection.ltr);
  });
}
