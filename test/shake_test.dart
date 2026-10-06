import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:trackly_inspector/shake.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

class FakeSensors extends SensorsPlatform {
  final events = StreamController<UserAccelerometerEvent>.broadcast();

  @override
  Stream<UserAccelerometerEvent> userAccelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) => events.stream;

  void jolt(double force) =>
      events.add(UserAccelerometerEvent(force, 0, 0, DateTime.now()));
}

Widget app() => MaterialApp(
  builder:
      (context, child) =>
          TracklyInspector(child: TracklyShakeDetector(child: child!)),
  home: const Scaffold(body: Center(child: Text('Home'))),
);

void main() {
  late FakeSensors sensors;

  setUp(() => SensorsPlatform.instance = sensors = FakeSensors());

  testWidgets('opens the inspector when shaken', (tester) async {
    await tester.pumpWidget(app());

    for (var i = 0; i < 3; i++) {
      sensors.jolt(20);
    }
    await tester.pumpAndSettle();

    expect(find.text('Trackly Inspector'), findsOneWidget);
  });

  testWidgets('ignores small movements', (tester) async {
    await tester.pumpWidget(app());

    for (var i = 0; i < 10; i++) {
      sensors.jolt(5);
    }
    sensors.jolt(20);
    await tester.pumpAndSettle();

    expect(find.text('Trackly Inspector'), findsNothing);
  });

  testWidgets('does nothing on the desktop', (tester) async {
    await tester.pumpWidget(app());

    expect(sensors.events.hasListener, isFalse);
    expect(find.text('Home'), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('does nothing when the inspector is off', (tester) async {
    TracklyInspector.controller.enabled = false;
    addTearDown(() => TracklyInspector.controller.enabled = true);
    await tester.pumpWidget(app());

    expect(sensors.events.hasListener, isFalse);
  });
}
