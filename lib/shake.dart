/// Opens the inspector when the device is shaken.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => TracklyInspector(
///     child: TracklyShakeDetector(child: child!),
///   ),
/// )
/// ```
///
/// Kept apart from `package:trackly_inspector/trackly_inspector.dart` because
/// it uses `sensors_plus`, which supports only Android, iOS, and the web. The
/// rest of the package supports every platform.
library;

export 'src/ui/shake_detector.dart';
