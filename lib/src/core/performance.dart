import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';

import 'calls.dart';

/// One frame drawn while a screen was showing.
@immutable
class TracklyFrame {
  /// Creates a frame that started building at [time].
  const TracklyFrame({
    required this.time,
    required this.build,
    required this.raster,
  });

  /// When the frame started building.
  final DateTime time;

  /// The time spent building it on the UI thread.
  final Duration build;

  /// The time spent drawing it on the raster thread.
  final Duration raster;

  /// The total work for the frame: [build] plus [raster].
  Duration get total => build + raster;
}

/// One visit to a screen: from when it appeared until another screen
/// replaced it.
class TracklyScreenVisit {
  TracklyScreenVisit._(this.id, this.name, this.start, this.frameBudget);

  /// Frames that take longer than this to build and draw are frozen.
  static const frozenFrameTime = Duration(milliseconds: 700);

  /// A unique, increasing id.
  final int id;

  /// The route's name, or the type of its page widget, e.g. `ProductsPage`.
  final String name;

  /// When the screen appeared.
  final DateTime start;

  /// The time a frame has at the display's refresh rate, e.g. 16.7 ms at
  /// 60 Hz. A frame that takes longer to build or draw is slow.
  final Duration frameBudget;

  DateTime? _end;
  final _calls = <TracklyHttpCall>[];
  var _frames = 0;
  var _slowFrames = 0;
  var _frozenFrames = 0;
  var _buildTime = Duration.zero;
  var _rasterTime = Duration.zero;
  final _slowest = <TracklyFrame>[];
  int? _peakMemory;

  /// When another screen replaced this one, or `null` while it's showing.
  DateTime? get end => _end;

  /// How long the screen has been showing.
  Duration get duration => (_end ?? DateTime.now()).difference(start);

  /// The requests made while the screen was showing, oldest first.
  List<TracklyHttpCall> get calls => List.unmodifiable(_calls);

  /// The number of frames drawn while the screen was showing.
  int get frames => _frames;

  /// The number of frames that took longer than [frameBudget] to build or
  /// to draw.
  int get slowFrames => _slowFrames;

  /// The number of frames that took longer than [frozenFrameTime].
  int get frozenFrames => _frozenFrames;

  /// The average time to build a frame, or `null` if none were drawn.
  Duration? get averageBuild => _frames == 0 ? null : _buildTime ~/ _frames;

  /// The average time to draw a frame, or `null` if none were drawn.
  Duration? get averageRaster => _frames == 0 ? null : _rasterTime ~/ _frames;

  /// Up to 5 of the slowest frames, slowest first.
  List<TracklyFrame> get slowestFrames => List.unmodifiable(_slowest);

  /// The most memory the app used while the screen was showing, in bytes.
  /// `null` on the web, where it can't be measured.
  int? get peakMemory => _peakMemory;

  /// The requests the screen made while loading: the ones it made when it
  /// appeared, and any that started less than half a second after the
  /// previous ones finished.
  List<TracklyHttpCall> get loadCalls {
    final load = <TracklyHttpCall>[];
    DateTime? busyUntil;
    for (final call in _calls) {
      final limit =
          busyUntil == null
              ? start.add(_firstCallWindow)
              : busyUntil.add(_quietTime);
      if (call.startTime.isAfter(limit)) break;
      load.add(call);
      final end = call.endTime ?? _forever;
      if (busyUntil == null || end.isAfter(busyUntil)) busyUntil = end;
    }
    return load;
  }

  /// The time from the screen appearing until its [loadCalls] finished.
  ///
  /// `null` if it made no requests when it appeared, or while they're still
  /// in progress.
  Duration? get loadTime {
    final load = loadCalls;
    if (load.isEmpty || load.any((call) => call.isPending)) return null;
    var begin = start;
    var finish = start;
    for (final call in load) {
      if (call.startTime.isBefore(begin)) begin = call.startTime;
      if (call.endTime!.isAfter(finish)) finish = call.endTime!;
    }
    return finish.difference(begin);
  }

  // Requests that start this soon after the screen appears are part of
  // loading it, e.g. ones that wait for a token first.
  static const _firstCallWindow = Duration(seconds: 1);

  // Loading ends once no request starts for this long.
  static const _quietTime = Duration(milliseconds: 500);

  static final _forever = DateTime(9999);

  void _addFrame(TracklyFrame frame) {
    _frames++;
    _buildTime += frame.build;
    _rasterTime += frame.raster;
    if (frame.build > frameBudget || frame.raster > frameBudget) {
      _slowFrames++;
    }
    if (frame.total > frozenFrameTime) _frozenFrames++;

    if (_slowest.length < 5 || frame.total > _slowest.last.total) {
      _slowest
        ..add(frame)
        ..sort((a, b) => b.total.compareTo(a.total));
      if (_slowest.length > 5) _slowest.removeLast();
    }
  }
}

/// Records which screen is showing, and the frames and requests of each one.
///
/// Kept apart from the controller's calls and logs, so frames, which arrive
/// several times a second, only rebuild the Performance tab.
class ScreenTimeline extends ChangeNotifier {
  /// Creates the timeline of [controller].
  ScreenTimeline(this.controller);

  /// Where requests come from, and whether recording is enabled.
  final TracklyInspectorController controller;

  final _visits = ListQueue<TracklyScreenVisit>();
  TracklyScreenVisit? _current;
  var _paused = false;
  var _nextId = 1;

  // Which visit was showing from each time on, so frames, which arrive late,
  // are counted for the screen that was showing when they were built. A
  // `null` visit means the inspector was open.
  final _segments = <(DateTime, TracklyScreenVisit?)>[];

  // The latest frame, held until the next one arrives. Screens change while
  // a frame is built, e.g. when a new page builds for the first time, and
  // that frame belongs to the new screen. Only the next frame's start tells
  // whether a change happened during this one.
  TracklyFrame? _lastFrame;

  /// The time a frame has at the display's refresh rate.
  Duration frameBudget = const Duration(microseconds: 16667);

  /// The app's memory use in bytes when last measured, or `null` if it can't
  /// be measured.
  int? memory;

  /// The visits, oldest first.
  List<TracklyScreenVisit> get visits => List.unmodifiable(_visits);

  /// The visit to the screen that's showing.
  TracklyScreenVisit? get current => _current;

  /// Whether the inspector is covering the app.
  bool get isPaused => _paused;

  /// Starts a visit to the screen called [name].
  void start(String name, {DateTime? at}) {
    if (!controller.enabled) return;
    final time = at ?? DateTime.now();
    _current?._end = time;
    final visit = TracklyScreenVisit._(_nextId++, name, time, frameBudget);
    _visits.addLast(visit);
    while (_visits.length > controller.maxScreenVisits) {
      _visits.removeFirst();
    }
    _current = visit;
    _paused = false;
    _segments.add((time, visit));
    _scheduleNotify();
  }

  /// Stops counting frames while the inspector covers the app.
  void pause({DateTime? at}) {
    if (_paused) return;
    _paused = true;
    _segments.add((at ?? DateTime.now(), null));
  }

  /// Counts frames for the current screen again.
  void resume({DateTime? at}) {
    if (!_paused) return;
    _paused = false;
    _segments.add((at ?? DateTime.now(), _current));
  }

  /// Adds [call] to the screen that's showing.
  void addCall(TracklyHttpCall call) {
    final visit = _current;
    if (visit == null || visit._calls.contains(call)) return;
    visit._calls.add(call);
    _scheduleNotify();
  }

  /// Counts [timings] for the screens that were showing when they were
  /// built.
  ///
  /// The latest frame is counted when the next one arrives.
  void addFrames(List<FrameTiming> timings) {
    if (!controller.enabled || _segments.isEmpty || timings.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final latest = timings.last.timestampInMicroseconds(
      FramePhase.rasterFinish,
    );
    for (final timing in timings) {
      // Frame timestamps use the engine's clock. The wall-clock time the
      // frame finished drawing ties them to DateTime.
      var finished = timing.timestampInMicroseconds(
        FramePhase.rasterFinishWallTime,
      );
      // On the web it's the page's clock instead. Frames are reported right
      // after the latest one finishes, so tie that one to now.
      if ((finished - now).abs() > Duration.microsecondsPerDay) {
        finished =
            now -
            latest +
            timing.timestampInMicroseconds(FramePhase.rasterFinish);
      }
      final frame = TracklyFrame(
        time: DateTime.fromMicrosecondsSinceEpoch(finished - _since(timing)),
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
      if (_lastFrame case final previous?) {
        _visitBefore(frame.time)?._addFrame(previous);
      }
      _lastFrame = frame;
    }
    _pruneSegments();
    _scheduleNotify();
  }

  /// Records that the app uses [bytes] of memory now.
  void recordMemory(int? bytes) {
    memory = bytes;
    final visit = _current;
    if (bytes == null || visit == null || _paused) return;
    if (visit._peakMemory == null || bytes > visit._peakMemory!) {
      visit._peakMemory = bytes;
    }
  }

  /// Removes all visits except the current one, which starts over.
  void clear() {
    final current = _current;
    final paused = _paused;
    _visits.clear();
    _segments.clear();
    _lastFrame = null;
    _current = null;
    if (current != null) {
      start(current.name);
      if (paused) pause();
    }
    _scheduleNotify();
  }

  // The time from the frame's build start to its raster finish, in
  // microseconds.
  static int _since(FrameTiming timing) =>
      timing.timestampInMicroseconds(FramePhase.rasterFinish) -
      timing.timestampInMicroseconds(FramePhase.buildStart);

  // The visit showing just before [time].
  TracklyScreenVisit? _visitBefore(DateTime time) {
    for (var i = _segments.length - 1; i >= 0; i--) {
      final (from, visit) = _segments[i];
      if (from.isBefore(time)) return visit;
    }
    return null;
  }

  // Frames arrive within a second or so, so older segments aren't needed.
  void _pruneSegments() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    while (_segments.length > 1 && _segments[1].$1.isBefore(cutoff)) {
      _segments.removeAt(0);
    }
  }

  var _notifyScheduled = false;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

final _timelines = Expando<ScreenTimeline>('trackly_inspector.screens');

/// The screen timeline of [controller].
ScreenTimeline screenTimelineOf(TracklyInspectorController controller) =>
    _timelines[controller] ??= ScreenTimeline(controller);
