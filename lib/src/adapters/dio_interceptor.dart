import 'package:dio/dio.dart';

import '../core/calls.dart';
import '../ui/inspector.dart';

/// Records every request made by a [Dio] instance in the inspector.
///
/// ```dart
/// final dio = Dio()..interceptors.add(TracklyDioInterceptor());
/// ```
///
/// Add it after your other interceptors, so it records requests as they are
/// finally sent, e.g. with auth headers.
class TracklyDioInterceptor extends Interceptor {
  /// Creates an interceptor that records calls in [controller], or in
  /// `TracklyInspector.controller` if it's `null`.
  TracklyDioInterceptor({TracklyInspectorController? controller})
    : _controller = controller;

  final TracklyInspectorController? _controller;

  TracklyInspectorController get _target =>
      _controller ?? TracklyInspector.controller;

  static const _callKey = 'trackly_inspector.call';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    final call = _target.startCall(
      client: 'dio',
      method: options.method,
      uri: options.uri,
      headers: _flatten(options.headers),
      body: data is FormData ? null : _bodyOf(data),
      formData: data is FormData ? _formFields(data) : null,
    );
    if (call != null) options.extra[_callKey] = call;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _complete(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      _complete(response);
    } else {
      final call = err.requestOptions.extra[_callKey];
      if (call is TracklyHttpCall) {
        _target.failCall(call, _describe(err));
      }
    }
    handler.next(err);
  }

  void _complete(Response<dynamic> response) {
    final call = response.requestOptions.extra[_callKey];
    if (call is! TracklyHttpCall) return;
    _target.completeCall(
      call,
      statusCode: response.statusCode ?? 0,
      reasonPhrase: response.statusMessage,
      headers: {
        for (final header in response.headers.map.entries)
          header.key: header.value.join(', '),
      },
      body: _bodyOf(response.data),
    );
  }

  static Object? _bodyOf(Object? data) {
    if (data is ResponseBody) return '<streamed response>';
    if (data is Stream) return '<stream>';
    return data;
  }

  static Map<String, String> _flatten(Map<String, dynamic> headers) => {
    for (final header in headers.entries)
      if (header.value != null)
        header.key:
            header.value is Iterable
                ? (header.value as Iterable).join(', ')
                : '${header.value}',
  };

  static List<TracklyFormField> _formFields(FormData data) => [
    for (final field in data.fields)
      TracklyFormField(field.key, value: field.value),
    for (final file in data.files)
      TracklyFormField(
        file.key,
        fileName: file.value.filename ?? 'file',
        fileSize: file.value.length,
      ),
  ];

  static String _describe(DioException error) {
    final detail = error.message ?? error.error?.toString();
    return detail == null || detail.isEmpty
        ? error.type.name
        : '${error.type.name}: $detail';
  }
}
