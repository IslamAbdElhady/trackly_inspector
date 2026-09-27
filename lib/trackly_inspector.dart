/// An in-app inspector for network calls and logs.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => TracklyInspector(child: child!),
/// )
/// ```
///
/// Record calls with `TracklyDioInterceptor` from
/// `package:trackly_inspector/dio.dart`, or `TracklyHttpClient` from
/// `package:trackly_inspector/http.dart`.
///
/// Also exports `trackly_logger`, so `trackly.info('…')` works with this
/// import alone, and the logs show up in the inspector's Logs tab.
library;

export 'package:trackly_logger/trackly_logger.dart';

export 'src/core/calls.dart';
export 'src/ui/inspector.dart' show TracklyInspector, TracklyTrigger;
