import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:trackly_logger/trackly_logger.dart';

import 'body.dart';

/// A field of a multipart form request body.
@immutable
class TracklyFormField {
  /// Creates a text field, or a file field when [fileName] is set.
  const TracklyFormField(this.name, {this.value, this.fileName, this.fileSize});

  /// The field name.
  final String name;

  /// The value of a text field.
  final String? value;

  /// The file name of a file field.
  final String? fileName;

  /// The size of a file field in bytes, if known.
  final int? fileSize;

  /// Whether this field is a file.
  bool get isFile => fileName != null;
}

/// A single HTTP request and, once it finishes, its response or error.
///
/// Created by [TracklyInspectorController.startCall] and updated by
/// [TracklyInspectorController.completeCall] or
/// [TracklyInspectorController.failCall].
class TracklyHttpCall {
  TracklyHttpCall._({
    required this.id,
    required this.client,
    required this.method,
    required this.uri,
    required this.startTime,
    required this.requestHeaders,
    required this.requestBody,
    required this.requestSize,
    required this.requestFormData,
  });

  /// A unique, increasing number for this call.
  final int id;

  /// The HTTP client that made the call, e.g. `dio` or `http`.
  final String client;

  /// The request method in upper case, e.g. `GET`.
  final String method;

  /// The full request URL, including query parameters.
  final Uri uri;

  /// When the request started.
  final DateTime startTime;

  /// The request headers.
  final Map<String, String> requestHeaders;

  /// The request body as text, or `null` if there is none.
  final String? requestBody;

  /// The request body size in bytes, if known.
  final int? requestSize;

  /// The fields of a multipart form request body.
  final List<TracklyFormField>? requestFormData;

  int? _statusCode;
  String? _reasonPhrase;
  Map<String, String> _responseHeaders = const {};
  String? _responseBody;
  int? _responseSize;
  DateTime? _endTime;
  String? _error;

  /// The response status code, or `null` if there is no response yet.
  int? get statusCode => _statusCode;

  /// The response status message, e.g. `Not Found`.
  String? get reasonPhrase => _reasonPhrase;

  /// The response headers.
  Map<String, String> get responseHeaders => _responseHeaders;

  /// The response body as text, or `null` if there is none.
  String? get responseBody => _responseBody;

  /// The response body size in bytes, if known.
  int? get responseSize => _responseSize;

  /// When the call finished, or `null` while it's in progress.
  DateTime? get endTime => _endTime;

  /// Why the call failed without a response, e.g. a timeout.
  String? get error => _error;

  /// Whether the call is still in progress.
  bool get isPending => _endTime == null;

  /// Whether the call finished with an error or a 4xx/5xx status.
  bool get isFailure =>
      _error != null || (_statusCode != null && _statusCode! >= 400);

  /// How long the call took, or `null` while it's in progress.
  Duration? get duration => _endTime?.difference(startTime);

  /// The request as a `curl` command that can be pasted into a terminal.
  String toCurl() {
    String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

    final hasBody = requestBody != null || requestFormData != null;
    final parts = <String>[
      [
        'curl',
        if (method != 'GET' || hasBody) '-X $method',
        quote('$uri'),
      ].join(' '),
    ];
    for (final header in requestHeaders.entries) {
      if (header.key.toLowerCase() == 'content-length') continue;
      parts.add('-H ${quote('${header.key}: ${header.value}')}');
    }
    for (final field in requestFormData ?? const <TracklyFormField>[]) {
      parts.add(
        field.isFile
            ? '-F ${quote('${field.name}=@${field.fileName}')}'
            : '-F ${quote('${field.name}=${field.value ?? ''}')}',
      );
    }
    if (requestBody != null) parts.add('--data-raw ${quote(requestBody!)}');
    return parts.join(' \\\n  ');
  }
}

/// Stores the calls and logs shown by the inspector, and notifies listeners
/// when they change.
///
/// Use the shared `TracklyInspector.controller` unless you need a separate
/// one.
class TracklyInspectorController extends ChangeNotifier {
  /// Creates a controller.
  TracklyInspectorController({
    this.maxCalls = 300,
    this.maxLogs = 1000,
    this.maxBodyLength = 512 * 1024,
    Set<String> redactedHeaders = const {},
  }) : redactedHeaders = {
         for (final name in redactedHeaders) name.toLowerCase(),
       };

  /// Whether calls and logs are recorded. Defaults to `false` in release
  /// builds.
  bool enabled = !kReleaseMode;

  /// The number of calls kept. The oldest are dropped first.
  int maxCalls;

  /// The number of log records kept. The oldest are dropped first.
  int maxLogs;

  /// Bodies longer than this many characters are truncated.
  int maxBodyLength;

  /// Headers whose values are hidden, e.g. `{'authorization', 'cookie'}`.
  ///
  /// Values are replaced when the call is recorded, so they are never kept
  /// in memory or included in copied cURL commands.
  Set<String> redactedHeaders;

  final _calls = ListQueue<TracklyHttpCall>();
  final _logs = ListQueue<TracklyRecord>();
  var _nextId = 1;
  var _notifyScheduled = false;

  /// The recorded calls, oldest first.
  List<TracklyHttpCall> get calls => List.unmodifiable(_calls);

  /// The recorded log records, oldest first.
  List<TracklyRecord> get logs => List.unmodifiable(_logs);

  /// The most recent call, if any.
  TracklyHttpCall? get lastCall => _calls.isEmpty ? null : _calls.last;

  /// The number of calls still in progress.
  int get pendingCount => _calls.where((call) => call.isPending).length;

  /// A [TracklyOutput] that records log records in this controller.
  ///
  /// `TracklyInspector` adds it to `TracklyLogger.output` automatically.
  late final TracklyOutput logOutput = _ControllerLogOutput(this);

  /// Records the start of a request. Returns `null` when not [enabled].
  ///
  /// [body] can be a `String`, bytes, or a JSON-encodable `Map` or `List`.
  TracklyHttpCall? startCall({
    required String client,
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    Object? body,
    List<TracklyFormField>? formData,
  }) {
    if (!enabled) return null;

    final redacted = _redact(headers);
    final captured = captureBody(
      body,
      contentType: headerValue(redacted, 'content-type'),
      maxLength: maxBodyLength,
    );
    final call = TracklyHttpCall._(
      id: _nextId++,
      client: client,
      method: method.toUpperCase(),
      uri: uri,
      startTime: DateTime.now(),
      requestHeaders: redacted,
      requestBody: captured.text,
      requestSize:
          captured.size ??
          formData?.fold<int>(0, (sum, field) => sum + (field.fileSize ?? 0)),
      requestFormData: formData,
    );

    _calls.addLast(call);
    while (_calls.length > maxCalls) {
      _calls.removeFirst();
    }
    _scheduleNotify();
    return call;
  }

  /// Records the response of [call].
  void completeCall(
    TracklyHttpCall call, {
    required int statusCode,
    String? reasonPhrase,
    Map<String, String> headers = const {},
    Object? body,
  }) {
    final redacted = _redact(headers);
    final captured = captureBody(
      body,
      contentType: headerValue(redacted, 'content-type'),
      maxLength: maxBodyLength,
    );
    call
      .._statusCode = statusCode
      .._reasonPhrase = reasonPhrase
      .._responseHeaders = redacted
      .._responseBody = captured.text
      .._responseSize =
          captured.size ??
          int.tryParse(headerValue(redacted, 'content-length') ?? '')
      .._endTime = DateTime.now();
    _scheduleNotify();
  }

  /// Records that [call] failed without a response.
  void failCall(TracklyHttpCall call, Object error) {
    call
      .._error = '$error'
      .._endTime = DateTime.now();
    _scheduleNotify();
  }

  /// Records a log record.
  void addLog(TracklyRecord record) {
    if (!enabled) return;
    _logs.addLast(record);
    while (_logs.length > maxLogs) {
      _logs.removeFirst();
    }
    _scheduleNotify();
  }

  /// Removes all recorded calls.
  void clearCalls() {
    _calls.clear();
    _scheduleNotify();
  }

  /// Removes all recorded log records.
  void clearLogs() {
    _logs.clear();
    _scheduleNotify();
  }

  Map<String, String> _redact(Map<String, String> headers) => {
    for (final header in headers.entries)
      header.key:
          redactedHeaders.contains(header.key.toLowerCase())
              ? '••••••'
              : header.value,
  };

  // Calls and logs can be recorded while widgets are building, e.g. when a
  // request starts in initState, so listeners are notified in a microtask.
  // This also merges bursts of changes into one rebuild.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ControllerLogOutput extends TracklyOutput {
  _ControllerLogOutput(this.controller);

  final TracklyInspectorController controller;

  @override
  void write(TracklyRecord record) => controller.addLog(record);
}
