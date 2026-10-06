import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'inspector.dart';

/// Opens the inspector when the device is shaken.
///
/// Wrap your app in it inside [TracklyInspector]:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => TracklyInspector(
///     child: TracklyShakeDetector(child: child!),
///   ),
/// )
/// ```
///
/// Works on real Android and iOS devices; simulators don't report motion. On
/// other platforms it does nothing, so it's safe in apps that also run on the
/// web or the desktop.
class TracklyShakeDetector extends StatefulWidget {
  /// Creates the detector around [child].
  const TracklyShakeDetector({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  State<TracklyShakeDetector> createState() => _TracklyShakeDetectorState();
}

class _TracklyShakeDetectorState extends State<TracklyShakeDetector> {
  // Acceleration in m/s², without gravity, that counts as a jolt.
  static const _threshold = 13.0;
  static const _window = Duration(milliseconds: 800);
  static const _cooldown = Duration(milliseconds: 1500);

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  final _jolts = <DateTime>[];
  DateTime? _lastShake;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (TracklyInspector.controller.enabled && _supported) {
      _subscription = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(_onEvent, onError: (Object _) {}, cancelOnError: true);
    }
  }

  void _onEvent(UserAccelerometerEvent event) {
    final force = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (force < _threshold) return;

    final now = DateTime.now();
    _jolts
      ..removeWhere((time) => now.difference(time) > _window)
      ..add(now);
    final coolingDown =
        _lastShake != null && now.difference(_lastShake!) < _cooldown;
    if (_jolts.length >= 3 && !coolingDown) {
      _lastShake = now;
      _jolts.clear();
      if (!TracklyInspector.isInspecting) TracklyInspector.show();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
