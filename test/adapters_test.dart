import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trackly_inspector/dio.dart';
import 'package:trackly_inspector/http.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late TracklyInspectorController controller;

  setUp(() => controller = TracklyInspectorController());

  group('TracklyDioInterceptor', () {
    Dio dioWith(Future<ResponseBody> Function(RequestOptions) respond) =>
        Dio(BaseOptions(baseUrl: 'https://api.example.com'))
          ..httpClientAdapter = _FakeAdapter(respond)
          ..interceptors.add(TracklyDioInterceptor(controller: controller));

    test('records a successful request', () async {
      final dio = dioWith((_) async => _json({'id': 1}, 200));
      final response = await dio.post(
        '/users',
        queryParameters: {'invite': true},
        data: {'name': 'Ali'},
        options: Options(headers: {'Authorization': 'Bearer t'}),
      );

      expect(response.data, {'id': 1});
      final call = controller.calls.single;
      expect(call.client, 'dio');
      expect(call.method, 'POST');
      expect('${call.uri}', 'https://api.example.com/users?invite=true');
      expect(call.requestHeaders['Authorization'], 'Bearer t');
      expect(call.requestBody, '{"name":"Ali"}');
      expect(call.statusCode, 200);
      expect(call.responseBody, '{"id":1}');
      expect(call.responseHeaders['content-type'], 'application/json');
    });

    test('records error responses with their body', () async {
      final dio = dioWith((_) async => _json({'error': 'missing'}, 404));
      await expectLater(dio.get('/users/9'), throwsA(isA<DioException>()));

      final call = controller.calls.single;
      expect(call.statusCode, 404);
      expect(call.responseBody, '{"error":"missing"}');
      expect(call.error, isNull);
      expect(call.isFailure, isTrue);
    });

    test('records failures without a response', () async {
      final dio = dioWith((_) async => throw Exception('offline'));
      await expectLater(dio.get('/users'), throwsA(isA<DioException>()));

      final call = controller.calls.single;
      expect(call.statusCode, isNull);
      expect(call.error, contains('offline'));
      expect(call.isPending, isFalse);
    });

    test('records form data fields and files', () async {
      final dio = dioWith((_) async => _json({}, 200));
      await dio.post(
        '/upload',
        data: FormData.fromMap({
          'name': 'avatar',
          'file': MultipartFile.fromString('abc', filename: 'a.txt'),
        }),
      );

      final form = controller.calls.single.requestFormData!;
      expect(form.map((f) => f.name), ['name', 'file']);
      expect(form.first.value, 'avatar');
      expect(form.last.fileName, 'a.txt');
      expect(form.last.fileSize, 3);
    });
  });

  group('TracklyHttpClient', () {
    test('records the call and returns the response intact', () async {
      final client = TracklyHttpClient(
        controller: controller,
        inner: MockClient(
          (request) async => http.Response(
            '{"ok":true}',
            201,
            headers: {'content-type': 'application/json'},
            reasonPhrase: 'Created',
          ),
        ),
      );
      final response = await client.post(
        Uri.parse('https://api.example.com/items'),
        headers: {'content-type': 'application/json'},
        body: '{"name":"pen"}',
      );

      expect(response.statusCode, 201);
      expect(response.body, '{"ok":true}');
      final call = controller.calls.single;
      expect(call.client, 'http');
      expect(call.requestBody, '{"name":"pen"}');
      expect(call.responseBody, '{"ok":true}');
      expect(call.reasonPhrase, 'Created');
    });

    test('records failures and rethrows them', () async {
      final client = TracklyHttpClient(
        controller: controller,
        inner: MockClient((_) async => throw http.ClientException('no route')),
      );
      await expectLater(
        client.get(Uri.parse('https://api.example.com')),
        throwsA(isA<http.ClientException>()),
      );
      expect(controller.calls.single.error, contains('no route'));
    });

    test('records multipart fields and files', () async {
      final client = TracklyHttpClient(
        controller: controller,
        inner: MockClient.streaming(
          (request, body) async =>
              http.StreamedResponse(Stream.value(utf8.encode('done')), 200),
        ),
      );
      final request =
          http.MultipartRequest('POST', Uri.parse('https://api.example.com'))
            ..fields['name'] = 'avatar'
            ..files.add(
              http.MultipartFile.fromString('file', 'abcd', filename: 'a.txt'),
            );
      await client.send(request);

      final form = controller.calls.single.requestFormData!;
      expect(form.first.value, 'avatar');
      expect(form.last.fileName, 'a.txt');
      expect(form.last.fileSize, 4);
      expect(controller.calls.single.responseBody, 'done');
    });

    test('passes requests through untouched when disabled', () async {
      controller.enabled = false;
      final client = TracklyHttpClient(
        controller: controller,
        inner: MockClient((_) async => http.Response('hi', 200)),
      );
      expect((await client.get(Uri.parse('https://x.dev'))).body, 'hi');
      expect(controller.calls, isEmpty);
    });
  });
}
