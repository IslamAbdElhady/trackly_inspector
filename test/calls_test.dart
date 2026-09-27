import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackly_inspector/src/core/body.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

void main() {
  late TracklyInspectorController controller;

  setUp(() => controller = TracklyInspectorController());

  TracklyHttpCall start({
    String method = 'GET',
    String url = 'https://api.example.com/users?page=2',
    Map<String, String> headers = const {},
    Object? body,
    List<TracklyFormField>? formData,
  }) =>
      controller.startCall(
        client: 'test',
        method: method,
        uri: Uri.parse(url),
        headers: headers,
        body: body,
        formData: formData,
      )!;

  group('TracklyInspectorController', () {
    test('records the request and then the response', () {
      final call = start(method: 'post', body: {'name': 'Ali'});
      expect(call.method, 'POST');
      expect(call.isPending, isTrue);
      expect(call.requestBody, '{"name":"Ali"}');
      expect(call.requestSize, 14);

      controller.completeCall(
        call,
        statusCode: 201,
        reasonPhrase: 'Created',
        headers: {'content-type': 'application/json'},
        body: utf8.encode('{"id":7}'),
      );
      expect(call.isPending, isFalse);
      expect(call.statusCode, 201);
      expect(call.responseBody, '{"id":7}');
      expect(call.responseSize, 8);
      expect(call.duration, isNotNull);
      expect(call.isFailure, isFalse);
    });

    test('marks 4xx, 5xx, and errors as failures', () {
      final notFound = start();
      controller.completeCall(notFound, statusCode: 404);
      final offline = start();
      controller.failCall(offline, 'SocketException: offline');

      expect(notFound.isFailure, isTrue);
      expect(offline.isFailure, isTrue);
      expect(offline.statusCode, isNull);
      expect(offline.error, 'SocketException: offline');
    });

    test('keeps only the newest maxCalls calls', () {
      controller.maxCalls = 2;
      final ids = [for (var i = 0; i < 3; i++) start().id];
      expect(controller.calls.map((c) => c.id), ids.skip(1));
    });

    test('records nothing when disabled', () {
      controller.enabled = false;
      expect(
        controller.startCall(client: 'x', method: 'GET', uri: Uri()),
        isNull,
      );
      controller.addLog(
        TracklyRecord(
          level: TracklyLevel.info,
          message: 'm',
          time: DateTime(2024),
        ),
      );
      expect(controller.calls, isEmpty);
      expect(controller.logs, isEmpty);
    });

    test('hides redacted headers in requests and responses', () {
      controller.redactedHeaders = {'authorization', 'set-cookie'};
      final call = start(
        headers: {'Authorization': 'Bearer secret', 'Accept': '*/*'},
      );
      controller.completeCall(
        call,
        statusCode: 200,
        headers: {'set-cookie': 'sid=secret'},
      );

      expect(call.requestHeaders, {'Authorization': '••••••', 'Accept': '*/*'});
      expect(call.responseHeaders['set-cookie'], '••••••');
      expect(call.toCurl(), isNot(contains('secret')));
    });

    test(
      'merges changes into one notification after the current task',
      () async {
        var notifications = 0;
        controller.addListener(() => notifications++);
        final call = start();
        controller.completeCall(call, statusCode: 200);
        expect(notifications, 0);

        await Future<void>.delayed(Duration.zero);
        expect(notifications, 1);
      },
    );

    test('records logs through logOutput', () {
      controller.logOutput.write(
        TracklyRecord(
          level: TracklyLevel.warning,
          message: 'careful',
          time: DateTime(2024),
        ),
      );
      expect(controller.logs.single.message, 'careful');
    });

    test('clears calls and logs', () {
      start();
      controller.addLog(
        TracklyRecord(
          level: TracklyLevel.info,
          message: 'm',
          time: DateTime(2024),
        ),
      );
      controller
        ..clearCalls()
        ..clearLogs();
      expect(controller.calls, isEmpty);
      expect(controller.logs, isEmpty);
    });
  });

  group('toCurl', () {
    test('builds a GET command', () {
      expect(
        start(headers: {'Accept': 'application/json'}).toCurl(),
        "curl 'https://api.example.com/users?page=2' \\\n"
        "  -H 'Accept: application/json'",
      );
    });

    test('adds the method and body, and escapes single quotes', () {
      final call = start(
        method: 'POST',
        headers: {'Content-Type': 'application/json', 'Content-Length': '20'},
        body: {'name': "O'Neil"},
      );
      expect(
        call.toCurl(),
        "curl -X POST 'https://api.example.com/users?page=2' \\\n"
        "  -H 'Content-Type: application/json' \\\n"
        "  --data-raw '{\"name\":\"O'\\''Neil\"}'",
      );
    });

    test('adds form fields and files', () {
      final call = start(
        method: 'POST',
        formData: const [
          TracklyFormField('name', value: 'avatar'),
          TracklyFormField('file', fileName: 'a.png', fileSize: 10),
        ],
      );
      expect(call.toCurl(), contains("-F 'name=avatar'"));
      expect(call.toCurl(), contains("-F 'file=@a.png'"));
      expect(call.requestSize, 10);
    });
  });

  group('captureBody', () {
    test('keeps strings and encodes maps as JSON', () {
      expect(captureBody('hi', maxLength: 100), (text: 'hi', size: 2));
      expect(captureBody([1, 'a'], maxLength: 100).text, '[1,"a"]');
    });

    test('decodes text bytes and describes binary bytes', () {
      expect(
        captureBody(utf8.encode('{"a":1}'), maxLength: 100).text,
        '{"a":1}',
      );
      expect(
        captureBody(
          [137, 80, 78, 71],
          contentType: 'image/png',
          maxLength: 100,
        ).text,
        '<binary: 4 bytes>',
      );
      expect(
        captureBody([0xff, 0xfe, 0x00], maxLength: 100).text,
        '<binary: 3 bytes>',
      );
    });

    test('truncates long bodies but reports the full size', () {
      final body = captureBody('x' * 50, maxLength: 10);
      expect(body.text, startsWith('x' * 10));
      expect(body.text, contains('truncated (50 characters in total)'));
      expect(body.size, 50);
    });

    test('returns nothing for a null body', () {
      expect(captureBody(null, maxLength: 10), (text: null, size: null));
    });
  });
}
