import 'dart:convert';

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

/// Opens the response body of a GET call that returned [body] as JSON.
Future<void> openResponse(WidgetTester tester, Object body) async {
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
        method: 'GET',
        uri: Uri.parse('https://api.dev/cars'),
      )!;
  controller.completeCall(
    call,
    statusCode: 200,
    headers: {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
  TracklyInspector.show();
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('/cars').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Response'));
  await tester.pumpAndSettle();
}

final _cars = {
  'cars': [
    {
      'brand': 'BMW',
      'fuel': 'diesel',
      'engine': {'hp': 258},
    },
    {
      'brand': 'Kia',
      'fuel': 'petrol',
      'engine': {'hp': 120},
    },
    {
      'brand': 'BMW',
      'fuel': 'petrol',
      'engine': {'hp': 190},
    },
    {
      'brand': 'Tesla',
      'engine': {'hp': 450},
    },
  ],
};

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

  testWidgets('filters a list by the values of its fields', (tester) async {
    await openResponse(tester, _cars);

    await tester.tap(find.byTooltip('Filter cars'));
    await tester.pumpAndSettle();
    expect(find.text('brand'), findsOneWidget);
    expect(find.text('engine.hp'), findsOneWidget);
    expect(find.text('missing'), findsOneWidget); // The Tesla has no fuel.
    expect(find.text('Show all 4'), findsOneWidget);

    await tester.tap(find.text('petrol'));
    await tester.pump();
    expect(find.text('Show 2 of 4'), findsOneWidget);
    await tester.tap(find.text('BMW'));
    await tester.pump();
    await tester.tap(find.text('Show 1 of 4'));
    await tester.pumpAndSettle();

    // Just the BMW that runs on petrol, opened, with its index in the list.
    expect(find.text('1 of 4 cars'), findsOneWidget);
    expect(find.text('fuel: petrol'), findsOneWidget);
    expect(find.text('brand: BMW'), findsOneWidget);
    expect(find.textContaining('fuel: "petrol"'), findsOneWidget);
    expect(find.textContaining('hp: 190'), findsOneWidget);
    expect(find.textContaining('Kia'), findsNothing);
    expect(find.textContaining('258'), findsNothing);

    await tester.tap(find.byTooltip('Remove filter').last);
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 cars'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"brand": "Kia"'), findsOneWidget);
  });

  testWidgets('filters numbers by a range and text by what it contains', (
    tester,
  ) async {
    await openResponse(tester, [
      for (var i = 1; i <= 15; i++) {'id': i, 'name': 'Car $i'},
    ]);

    await tester.tap(find.byTooltip('Filter items'));
    await tester.pumpAndSettle();
    expect(find.text('1 to 15'), findsOneWidget);
    expect(find.text('15 different'), findsOneWidget);

    // Car 1 and Car 10 to Car 15.
    await tester.enterText(find.widgetWithText(TextField, 'Contains'), '1');
    await tester.pump();
    expect(find.text('Show 7 of 15'), findsOneWidget);
    // Typed with Arabic digits.
    await tester.enterText(find.widgetWithText(TextField, 'From'), '١٢');
    await tester.pump();
    expect(find.text('Show 4 of 15'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'To'), '13');
    await tester.pump();
    expect(find.text('Show 2 of 15'), findsOneWidget);

    await tester.tap(find.text('Show 2 of 15'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 15 items'), findsOneWidget);
    expect(find.text('id: 12 to 13'), findsOneWidget);
    expect(find.text('name: contains "1"'), findsOneWidget);
    expect(find.textContaining('"Car 12"'), findsOneWidget);
    expect(find.textContaining('"Car 14"'), findsNothing);
  });

  testWidgets('says when no items match', (tester) async {
    await openResponse(tester, _cars);

    await tester.tap(find.byTooltip('Filter cars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tesla'));
    await tester.tap(find.text('diesel'));
    await tester.pump();
    await tester.tap(find.text('Show 0 of 4'));
    await tester.pumpAndSettle();
    expect(find.text('No matching cars'), findsOneWidget);
  });

  testWidgets('steps through search matches and shows where each one is', (
    tester,
  ) async {
    await openResponse(tester, _cars);

    await tester.tap(find.byTooltip('Search in body'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bmw');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('cars[0].brand'), findsOneWidget);

    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('cars[2].brand'), findsOneWidget);

    // Wraps around at the end.
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous match'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    // The keyboard's search key goes to the next match too.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'audi');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.byTooltip('Next match'), findsNothing);
  });

  testWidgets('search replaces the filters', (tester) async {
    await openResponse(tester, _cars);

    await tester.tap(find.byTooltip('Filter cars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kia'));
    await tester.pump();
    await tester.tap(find.text('Show 1 of 4'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 cars'), findsOneWidget);

    await tester.tap(find.byTooltip('Search in body'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 cars'), findsNothing);
    await tester.enterText(find.byType(TextField), 'tesla');
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
  });
}
