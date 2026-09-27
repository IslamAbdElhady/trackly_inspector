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
