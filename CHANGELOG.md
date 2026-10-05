## 0.3.1

* Requests and responses are laid out like Postman:
  * Separate **Params**, **Headers**, and **Body** tabs, with counts, instead
    of one long page. Responses have **Body** and **Headers**.
  * The body shows its type (JSON, Form URL-encoded, Form data, Text) and
    size.
  * JSON opens **Pretty**-printed with line numbers, and can switch to
    **Tree** or **Raw**.
  * URL-encoded form bodies are shown as a decoded key/value table, and
    multipart forms as a table with a Text/File type for each field.
  * Search scrolls to the first match.
* Clearer text: larger sizes, the system font for names and messages, a
  monospaced font only for code and values, and higher contrast.
* The title and the request tabs no longer overflow with large text sizes.

## 0.3.0

* Uses `trackly_logger` 0.2.0, which this package re-exports:
  * Logs end with a clickable location, such as
    `(package:app/login_page.dart:42:7)`, that opens the code in VS Code and
    Android Studio.
  * Colors are off by default on iOS, where logs showed the color codes as
    text.
  * **Breaking**: `TracklyRecord`'s `caller` constructor parameter is replaced
    by `location`. Reading `record.caller` still works.
* The Logs tab shows each log's full location.

## 0.2.1

* Inspect mode is much faster on apps with a lot of recorded traffic:
  response bodies are decoded once and reused, and one search budget is
  shared across calls instead of one per call.
* The label no longer collapses when you touch something flush against the
  right edge of the screen.

## 0.2.0

* **Inspect mode**: touch any text or image on screen to find the request its
  data came from. The matching field opens highlighted in the response.
  * Start it by long-pressing the bubble, from the arrow in the inspector, or
    with `TracklyInspector.inspect()`.
  * Matches exact text, formatted numbers (`EGP 1,250.00` and `1250`), Arabic
    digits, shortened text, and image URLs.
  * When nothing matches, lists the requests made on the current screen.
* Call details show which screen made the request.

## 0.1.1

* Retake the screenshots with a clean status bar.

## 0.1.0

* Initial release.
* Records Dio calls with `TracklyDioInterceptor` and `http` calls with
  `TracklyHttpClient`, plus `TracklyInspectorController` for any other client.
* Network tab: search, status and method filters, and live updates for calls
  in progress.
* Call details: overview, query parameters, headers, form data, and bodies.
* Copy as cURL, and copy the URL, bodies, or a full report.
* JSON bodies as a collapsible tree or as raw text with syntax colors and
  search highlighting.
* Logs tab for `trackly_logger`, which is re-exported by this package.
* Opens with a draggable bubble, a two-finger long press, shaking, or
  `TracklyInspector.show()`.
* Header redaction, body size limits, and nothing recorded in release builds.
