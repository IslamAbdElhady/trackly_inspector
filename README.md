# trackly_inspector

[![pub package](https://img.shields.io/pub/v/trackly_inspector.svg)](https://pub.dev/packages/trackly_inspector)
[![CI](https://github.com/IslamAbdElhady/trackly_inspector/actions/workflows/ci.yml/badge.svg)](https://github.com/IslamAbdElhady/trackly_inspector/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An in-app network and log inspector for Flutter, like the Network tab of your
browser's DevTools, inside your app. See every Dio and `http` call with its
headers and bodies, search them, and copy any request as a cURL command. Or
touch anything on screen to find the request its data came from.

<p>
  <img src="https://raw.githubusercontent.com/IslamAbdElhady/trackly_inspector/main/screenshots/network.png" width="200" alt="Request list">
  <img src="https://raw.githubusercontent.com/IslamAbdElhady/trackly_inspector/main/screenshots/inspect.png" width="200" alt="Inspect mode: the request a price came from">
  <img src="https://raw.githubusercontent.com/IslamAbdElhady/trackly_inspector/main/screenshots/source.png" width="200" alt="The matching field, highlighted in the response">
  <img src="https://raw.githubusercontent.com/IslamAbdElhady/trackly_inspector/main/screenshots/details.png" width="200" alt="Request details with cURL">
  <img src="https://raw.githubusercontent.com/IslamAbdElhady/trackly_inspector/main/screenshots/logs.png" width="200" alt="Logs">
</p>

## Features

- **Every request**: method, URL, status, duration, size, headers, and body, for
  requests that are in progress, succeeded, or failed (timeouts, no connection).
- **Search and filters**: search URLs, status codes, and bodies. Filter by
  status (2xx, 4xx, 5xx, failed, pending) and method.
- **Inspect mode**: touch any text or image in your app to find the request
  it came from, with the matching field highlighted in the response.
- **Copy as cURL**, or copy the URL, either body, or a full report.
- **Bodies laid out like Postman**: Params, Headers, and Body tabs. JSON is
  pretty-printed with line numbers and colors, or shown as a collapsible tree,
  or raw. Form bodies, URL-encoded or multipart, are shown as key/value tables.
  Search highlights matches and jumps to them.
- **Logs tab**: logs from [trackly_logger](https://pub.dev/packages/trackly_logger)
  next to your requests, with levels, tags, errors, and stack traces.
- **Three ways to open it**: a draggable floating button, a two-finger long
  press, or shaking the device. Or from code.
- **Dio and `http`** out of the box, and a small API for any other client.
- **Safe by default**: off in release builds, can hide sensitive headers, and
  never blocks your app's gestures.
- **Every platform**: Android, iOS, web, macOS, Windows, and Linux.
- Works in right-to-left apps; the inspector itself always reads left to right.

## Getting started

```sh
flutter pub add trackly_inspector
```

**1. Add the inspector** to your app through `MaterialApp.builder`:

```dart
import 'package:trackly_inspector/trackly_inspector.dart';

MaterialApp(
  builder: (context, child) => TracklyInspector(child: child!),
  home: const HomePage(),
);
```

**2. Record requests** from your HTTP client.

With [Dio](https://pub.dev/packages/dio), add the interceptor last:

```dart
import 'package:trackly_inspector/dio.dart';

final dio = Dio()..interceptors.add(TracklyDioInterceptor());
```

With [http](https://pub.dev/packages/http), use `TracklyHttpClient` wherever
you use a `Client`:

```dart
import 'package:trackly_inspector/http.dart';

final client = TracklyHttpClient();
final response = await client.get(Uri.parse('https://example.com/users'));

// Or wrap a client you already have:
final retrying = TracklyHttpClient(inner: RetryClient(http.Client()));
```

**3. Open the inspector** by tapping the floating button, or holding two
fingers on the screen. You can also open it from code, e.g. from a debug menu:

```dart
TracklyInspector.show();
```

## Inspect mode

Like the element picker in Chrome DevTools: touch any text or image in your
app, and see which request it came from.

1. **Long-press the floating bubble**, or tap the arrow at the top of the
   inspector. You can also start it from code with `TracklyInspector.inspect()`.
2. **Touch anything** that shows data: a name, a price, a picture. What's under
   your finger is outlined as you move it, and your touches don't reach the
   app, so nothing gets pressed by accident.
3. **Pick a request** from the results. It opens on the response, with the
   matching field revealed and highlighted.

The inspector finds the request by looking for what's on screen in every
recorded response:

| On screen | Matches |
| --- | --- |
| `Leanne Graham` | `"name": "Leanne Graham"` (ignoring case and spacing) |
| `EGP 1,250.00`, `١٢٥٠` | `"total": 1250` |
| `Sunt aut facere…` | `"title": "sunt aut facere repellat"` |
| A network image | Its URL in any response, or the image request itself |

When the app changes a value before showing it, like a formatted date or a
translated status, nothing matches. The inspector then lists the requests made
while the current screen was showing, which usually include the right one.

Images are recognized when they come from `Image.network`, `NetworkImage`, or
a provider with a `url`, such as `CachedNetworkImageProvider`. For
`Image.network` and `Image(image: ...)`, this needs a debug build.

## Logs

`trackly_inspector` includes
[trackly_logger](https://pub.dev/packages/trackly_logger), so you can log
without adding another package, and your logs show up in the Logs tab:

```dart
import 'package:trackly_inspector/trackly_inspector.dart';

trackly.info('App started');
trackly.error('Payment failed', error: e, stackTrace: st);

class CartService with TracklyLoggerMixin {
  void add(String id) => logger.debug('Added $id');
}
```

## Configuration

Choose how the inspector opens:

```dart
TracklyInspector(
  triggers: const {
    TracklyTrigger.bubble,    // Draggable floating button.
    TracklyTrigger.longPress, // Two fingers held on the screen.
  },
  child: child!,
)
```

Pass an empty set to open it only from code. By default, the bubble and the
long press are on.

To also open it by shaking the device, wrap your app in `TracklyShakeDetector`:

```dart
import 'package:trackly_inspector/shake.dart';

MaterialApp(
  builder: (context, child) => TracklyInspector(
    child: TracklyShakeDetector(child: child!),
  ),
);
```

Shaking works on real Android and iOS devices. It lives in its own import
because the sensor plugin it uses supports only Android, iOS, and the web, but
it does nothing on other platforms, so it's safe in apps that also run on the
desktop.

Tune what's recorded through the shared controller, e.g. in `main()`:

```dart
TracklyInspector.controller
  ..maxCalls = 500 // Oldest calls are dropped first. Default: 300.
  ..maxBodyLength = 1024 * 1024 // Longer bodies are truncated. Default: 512K.
  ..redactedHeaders = {'authorization', 'cookie'}; // Shown as ••••••.
```

Redacted values are replaced when a call is recorded, so they are never kept
in memory or included in copied cURL commands.

If the inspector can't find your app's navigator, for example with a custom
`WidgetsApp`, pass it in:

```dart
TracklyInspector(navigatorKey: navigatorKey, child: child!)
```

## Release builds

The inspector does nothing in release builds: no bubble, no gestures, and no
calls or logs are recorded. To use it in a release build, such as an internal
QA build, turn it on before `runApp`:

```dart
TracklyInspector.controller.enabled = true;
```

## Other HTTP clients

Record calls from any client, such as Chopper or GraphQL, with the controller:

```dart
final controller = TracklyInspector.controller;

final call = controller.startCall(
  client: 'graphql',
  method: 'POST',
  uri: Uri.parse('https://api.example.com/graphql'),
  headers: {'content-type': 'application/json'},
  body: {'query': '{ me { id } }'},
);

// When the response arrives:
if (call != null) {
  controller.completeCall(call, statusCode: 200, body: responseJson);
  // Or, if it failed without a response:
  controller.failCall(call, error);
}
```

## Notes

- `TracklyHttpClient` reads each response fully so it can record the body.
  Server-sent event streams (`text/event-stream`) are passed through untouched.
- Shaking uses the accelerometer, which simulators and computers don't have.
  Use the bubble or the long press there.

## License

MIT. See [LICENSE](LICENSE).
