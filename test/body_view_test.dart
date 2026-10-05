import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

TracklyInspectorController get controller => TracklyInspector.controller;

/// Opens the details of a POST call with [body] and [headers], on the
/// Request tab.
Future<void> openRequest(
  WidgetTester tester, {
  Object? body,
  Map<String, String> headers = const {},
  List<TracklyFormField>? formData,
  String url = 'https://api.dev/login',
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => TracklyInspector(child: child!),
      home: const Scaffold(body: Text('Home')),
    ),
  );
  final call =
      controller.startCall(
        client: 'test',
        method: 'POST',
        uri: Uri.parse(url),
        headers: headers,
        body: body,
        formData: formData,
      )!;
  controller.completeCall(
    call,
    statusCode: 200,
    headers: {'content-type': 'application/json'},
    body: '{"token":"abc","user":{"id":7}}',
  );
  TracklyInspector.show();
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(Uri.parse(url).path).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Request'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => controller.clearCalls());

  testWidgets('shows JSON bodies pretty-printed with line numbers', (
    tester,
  ) async {
    await openRequest(
      tester,
      body: {'email': 'ali@example.com', 'remember': true},
      headers: {'content-type': 'application/json'},
    );

    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('Pretty'), findsOneWidget);
    // Line 1 is skipped because the bubble's call count also shows "1".
    for (final line in ['2', '3', '4']) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.textContaining('"email": "ali@example.com",'), findsOneWidget);
    expect(find.textContaining('"remember": true'), findsOneWidget);
  });

  testWidgets('switches between Pretty, Tree, and Raw', (tester) async {
    await openRequest(
      tester,
      body: {'email': 'ali@example.com'},
      headers: {'content-type': 'application/json'},
    );

    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();
    expect(find.text('{"email":"ali@example.com"}'), findsOneWidget);

    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Expand all'), findsNothing); // Shown as tooltips only.
    expect(find.byTooltip('Expand all'), findsOneWidget);
    expect(find.textContaining('"ali@example.com"'), findsOneWidget);
  });

  testWidgets('shows URL-encoded forms as a decoded table', (tester) async {
    await openRequest(
      tester,
      body: 'email=ali%40example.com&name=Ali+Hassan&remember=true',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );

    expect(find.text('Form URL-encoded'), findsOneWidget);
    expect(find.text('KEY'), findsOneWidget);
    expect(find.text('VALUE'), findsOneWidget);
    expect(find.text('ali@example.com'), findsOneWidget);
    expect(find.text('Ali Hassan'), findsOneWidget);

    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();
    expect(
      find.text('email=ali%40example.com&name=Ali+Hassan&remember=true'),
      findsOneWidget,
    );
  });

  testWidgets('shows multipart fields with their type', (tester) async {
    await openRequest(
      tester,
      formData: const [
        TracklyFormField('name', value: 'avatar'),
        TracklyFormField('file', fileName: 'a.png', fileSize: 2048),
      ],
    );

    expect(find.text('Form data'), findsOneWidget);
    expect(find.text('TYPE'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('a.png · 2.0 KB'), findsOneWidget);
  });

  testWidgets('splits the request into Params, Headers, and Body', (
    tester,
  ) async {
    await openRequest(
      tester,
      url: 'https://api.dev/login?lang=ar&v=2',
      body: 'hello',
      headers: {'content-type': 'text/plain', 'x-trace': 'abc'},
    );

    // Opens on the body, with counts on the other parts.
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Params  2'), findsOneWidget);
    expect(find.text('Headers  2'), findsOneWidget);

    await tester.tap(find.text('Params  2'));
    await tester.pumpAndSettle();
    expect(find.text('lang'), findsOneWidget);
    expect(find.text('ar'), findsOneWidget);

    await tester.tap(find.text('Headers  2'));
    await tester.pumpAndSettle();
    expect(find.text('x-trace'), findsOneWidget);
  });

  testWidgets('says when a request has no body', (tester) async {
    await openRequest(tester);
    expect(find.text('Headers  0'), findsOneWidget);

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();
    expect(find.text('No body'), findsOneWidget);
  });
}
