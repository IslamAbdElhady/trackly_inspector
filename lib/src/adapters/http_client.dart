import 'package:http/http.dart' as http;

import '../core/calls.dart';
import '../ui/inspector.dart';

/// An `http` client that records every request in the inspector.
///
/// ```dart
/// final client = TracklyHttpClient();
/// final response = await client.get(Uri.parse('https://example.com'));
/// ```
///
/// Wrap your own client to keep its behavior:
///
/// ```dart
/// final client = TracklyHttpClient(inner: RetryClient(http.Client()));
/// ```
///
/// Response bodies are read fully so they can be recorded, except for
/// `text/event-stream` responses, which are passed through untouched.
class TracklyHttpClient extends http.BaseClient {
  /// Creates a client that sends requests with [inner] and records them in
  /// [controller], or in `TracklyInspector.controller` if it's `null`.
  TracklyHttpClient({
    http.Client? inner,
    TracklyInspectorController? controller,
  }) : _inner = inner ?? http.Client(),
       _controller = controller;

  final http.Client _inner;
  final TracklyInspectorController? _controller;

  TracklyInspectorController get _target =>
      _controller ?? TracklyInspector.controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final call = _target.startCall(
      client: 'http',
      method: request.method,
      uri: request.url,
      headers: request.headers,
      body: switch (request) {
        http.Request() => request.bodyBytes.isEmpty ? null : request.bodyBytes,
        http.StreamedRequest() => '<streamed request>',
        _ => null,
      },
      formData:
          request is http.MultipartRequest
              ? [
                for (final field in request.fields.entries)
                  TracklyFormField(field.key, value: field.value),
                for (final file in request.files)
                  TracklyFormField(
                    file.field,
                    fileName: file.filename ?? 'file',
                    fileSize: file.length,
                  ),
              ]
              : null,
    );
    if (call == null) return _inner.send(request);

    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error) {
      _target.failCall(call, error);
      rethrow;
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/event-stream')) {
      _target.completeCall(
        call,
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: response.headers,
        body: '<event stream>',
      );
      return response;
    }

    final List<int> bytes;
    try {
      bytes = await response.stream.toBytes();
    } catch (error) {
      _target.failCall(call, error);
      rethrow;
    }
    _target.completeCall(
      call,
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: response.headers,
      body: bytes,
    );

    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
