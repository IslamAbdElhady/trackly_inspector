import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/src/core/performance.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

const ms = Duration(milliseconds: 1);

/// A frame that started building at [start]. The engine's clock is unrelated
/// to the wall clock, like on a device.
FrameTiming frame(DateTime start, {int build = 4, int raster = 4}) {
  final wall = start.microsecondsSinceEpoch;
  final engine = wall - 1700000000000000;
  final b = build * 1000;
  final r = raster * 1000;
  return FrameTiming(
    vsyncStart: engine,
    buildStart: engine,
    buildFinish: engine + b,
    rasterStart: engine + b,
    rasterFinish: engine + b + r,
    rasterFinishWallTime: wall + b + r,
  );
}

TracklyHttpCall startCall(TracklyInspectorController controller, String path) =>
    controller.startCall(
      client: 'test',
      method: 'GET',
      uri: Uri.parse('https://api.example.com$path'),
    )!;

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Details')));
}

void main() {
  group('ScreenTimeline', () {
    late TracklyInspectorController controller;
    late ScreenTimeline timeline;

    setUp(() {
      controller = TracklyInspectorController();
      timeline = screenTimelineOf(controller);
    });

    test('counts each frame for the screen it was built for', () {
      final t0 = DateTime.now();
      timeline
        ..start('A', at: t0)
        // B opens while the frame that starts at 990 ms builds it, so that
        // frame belongs to B.
        ..start('B', at: t0.add(ms * 1000))
        ..addFrames([
          frame(t0.add(ms * 100)),
          frame(t0.add(ms * 990), build: 30),
          frame(t0.add(ms * 1500)),
        ]);
      // The latest frame is counted when the next one arrives.
      expect(controller.screenVisits.last.frames, 1);
      timeline.addFrames([frame(t0.add(ms * 1600))]);

      final [a, b] = controller.screenVisits;
      expect(a.name, 'A');
      expect(a.frames, 1);
      expect(a.end, t0.add(ms * 1000));
      expect(b.name, 'B');
      expect(b.frames, 2);
      expect(b.end, isNull);
    });

    test('places frames on the web, where the wall time is the page clock', () {
      // On the web, timestamps count from page load, and the latest frame in
      // a batch has just finished.
      FrameTiming webFrame(int finishedAgo) {
        final finished = 30000000 - finishedAgo * 1000;
        return FrameTiming(
          vsyncStart: finished - 8000,
          buildStart: finished - 8000,
          buildFinish: finished - 4000,
          rasterStart: finished - 4000,
          rasterFinish: finished,
          rasterFinishWallTime: finished,
        );
      }

      final now = DateTime.now();
      timeline
        ..start('A', at: now.subtract(ms * 5000))
        // While the frame that finished a second ago was building.
        ..start('B', at: now.subtract(ms * 1005))
        ..addFrames([webFrame(4000), webFrame(1000), webFrame(0)]);

      final [a, b] = controller.screenVisits;
      expect(a.frames, 1);
      expect(b.frames, 1);
    });

    test('counts slow and frozen frames', () {
      final t0 = DateTime.now();
      timeline
        ..start('A', at: t0)
        ..addFrames([
          frame(t0.add(ms * 10), build: 5, raster: 5),
          frame(t0.add(ms * 20), build: 20, raster: 5),
          frame(t0.add(ms * 60), build: 5, raster: 30),
          frame(t0.add(ms * 100), build: 400, raster: 400),
          frame(t0.add(ms * 900)),
        ]);

      final visit = controller.screenVisits.single;
      expect(visit.frames, 4);
      expect(visit.slowFrames, 3);
      expect(visit.frozenFrames, 1);
      expect(visit.averageBuild, ms * 107.5);
      expect(visit.averageRaster, ms * 110);
      expect(visit.slowestFrames.map((f) => f.total), [
        ms * 800,
        ms * 35,
        ms * 25,
        ms * 10,
      ]);
      expect(visit.slowestFrames.first.time, t0.add(ms * 100));
    });

    test('skips frames while the inspector is open', () {
      final t0 = DateTime.now();
      timeline
        ..start('A', at: t0)
        ..pause(at: t0.add(ms * 1000))
        ..resume(at: t0.add(ms * 2000))
        ..addFrames([
          frame(t0.add(ms * 500)),
          // Opens the inspector.
          frame(t0.add(ms * 995)),
          frame(t0.add(ms * 1500)),
          // Closes it, showing A again.
          frame(t0.add(ms * 1995)),
          frame(t0.add(ms * 2500)),
          frame(t0.add(ms * 2600)),
        ]);

      expect(controller.screenVisits.single.frames, 3);
    });

    test('load time covers the requests made when the screen opened', () async {
      timeline.start('A');
      final first = startCall(controller, '/token');
      timeline.addCall(first);
      await Future<void>.delayed(ms * 50);
      controller.completeCall(first, statusCode: 200);

      // Started with the first one's result.
      final second = startCall(controller, '/products');
      timeline.addCall(second);
      final visit = controller.screenVisits.single;
      expect(visit.loadTime, isNull);
      await Future<void>.delayed(ms * 50);
      controller.completeCall(second, statusCode: 200);

      expect(visit.loadCalls, [first, second]);
      expect(visit.loadTime, greaterThanOrEqualTo(ms * 100));
      expect(visit.loadTime, lessThan(ms * 1000));

      // Made long after the screen loaded, e.g. after a tap.
      await Future<void>.delayed(ms * 600);
      final later = startCall(controller, '/cart');
      timeline.addCall(later);

      expect(visit.loadCalls, [first, second]);
      expect(visit.calls, [first, second, later]);
    });

    test('has no load time without requests when it opened', () {
      timeline.start('A', at: DateTime.now().subtract(ms * 2000));
      timeline.addCall(startCall(controller, '/cart'));

      final visit = controller.screenVisits.single;
      expect(visit.calls, hasLength(1));
      expect(visit.loadCalls, isEmpty);
      expect(visit.loadTime, isNull);
    });

    test('keeps maxScreenVisits, and clears all but the current one', () {
      controller
        ..maxScreenVisits = 2
        ..startScreen('A')
        ..startScreen('B')
        ..startScreen('C');
      expect(controller.screenVisits.map((v) => v.name), ['B', 'C']);

      final before = controller.screenVisits.last;
      controller.clearScreenVisits();
      final after = controller.screenVisits.single;
      expect(after.name, 'C');
      expect(after.id, greaterThan(before.id));
    });

    test('records nothing when disabled', () {
      controller
        ..enabled = false
        ..startScreen('A');
      timeline.addFrames([frame(DateTime.now())]);

      expect(controller.screenVisits, isEmpty);
    });
  });

  group('TracklyInspector', () {
    final controller = TracklyInspector.controller;
    final navigatorKey = GlobalKey<NavigatorState>();
    NavigatorState navigator() => navigatorKey.currentState!;

    Widget app() => MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => TracklyInspector(child: child!),
      home: const Scaffold(body: Center(child: Text('Home'))),
    );

    setUp(() {
      controller
        ..clearCalls()
        ..clearLogs();
    });

    testWidgets('records each page, named after its route or its widget', (
      tester,
    ) async {
      final since = controller.screenVisits.lastOrNull?.id ?? 0;
      List<String> names() => [
        for (final visit in controller.screenVisits)
          if (visit.id > since) visit.name,
      ];

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      navigator().push(
        MaterialPageRoute<void>(builder: (_) => const DetailsPage()),
      );
      await tester.pumpAndSettle();
      navigator().push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/settings'),
          builder: (_) => const Scaffold(),
        ),
      );
      await tester.pumpAndSettle();
      expect(names(), ['/', 'DetailsPage', '/settings']);

      // Dialogs and the inspector belong to the screen below them.
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Sure?')),
      );
      await tester.pumpAndSettle();
      navigator().pop();
      await tester.pumpAndSettle();
      TracklyInspector.show();
      await tester.pumpAndSettle();
      TracklyInspector.hide();
      await tester.pumpAndSettle();
      expect(names(), ['/', 'DetailsPage', '/settings']);

      navigator().pop();
      await tester.pumpAndSettle();
      expect(names(), ['/', 'DetailsPage', '/settings', 'DetailsPage']);
    });

    testWidgets('shows screens with their load time, requests, and frames', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      navigator().push(
        MaterialPageRoute<void>(builder: (_) => const DetailsPage()),
      );
      await tester.pumpAndSettle();
      controller.clearScreenVisits(); // Leaves only this screen.

      final call = startCall(controller, '/products');
      await tester.pump();
      controller.completeCall(call, statusCode: 200, body: '[]');
      final now = DateTime.now();
      tester.binding.platformDispatcher.onReportTimings!([
        frame(now, build: 30),
        frame(now.add(ms * 50)),
        frame(now.add(ms * 100)),
      ]);
      await tester.pump();

      TracklyInspector.show();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.textContaining('debug build'), findsOneWidget);
      expect(find.text('DetailsPage'), findsOneWidget);
      expect(
        find.textContaining('2 frames  ·  1 slow', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.text('DetailsPage'));
      await tester.pumpAndSettle();
      expect(find.text('LOADING'), findsOneWidget);
      expect(find.text('1 when it opened, 1 in total'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('build 30.0 ms  ·  raster 4.0 ms'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('SLOWEST FRAMES'), findsOneWidget);

      await tester.ensureVisible(find.text('/products'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('/products'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('DetailsPage'), findsWidgets); // The call's screen.
    });
  });
}
