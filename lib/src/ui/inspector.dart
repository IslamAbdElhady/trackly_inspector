import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trackly_logger/trackly_logger.dart';

import '../core/calls.dart';
import '../core/source_finder.dart';
import 'call_page.dart';
import 'element_picker.dart';
import 'home_page.dart';
import 'inspect_overlay.dart';
import 'screens.dart';
import 'source_sheet.dart';
import 'triggers.dart';

/// Ways to open the inspector.
enum TracklyTrigger {
  /// A floating button that can be dragged to either side of the screen.
  bubble,

  /// Holding two fingers on the screen for a moment.
  longPress,

  /// Shaking the device. Needs a real Android or iOS device.
  shake,
}

/// Adds an in-app inspector for network calls and logs.
///
/// Wrap your app in it through `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => TracklyInspector(child: child!),
/// )
/// ```
///
/// Then record calls with `TracklyDioInterceptor` or `TracklyHttpClient`.
/// Logs from `trackly_logger` are recorded automatically.
///
/// Long-press the bubble, tap the arrow in the inspector, or call [inspect]
/// to pick anything on screen and find the request its data came from.
///
/// Does nothing in release builds unless [controller]'s `enabled` is set.
class TracklyInspector extends StatefulWidget {
  /// Creates the inspector around [child].
  const TracklyInspector({
    super.key,
    required this.child,
    this.triggers = const {TracklyTrigger.bubble, TracklyTrigger.longPress},
    this.captureLogs = true,
    this.navigatorKey,
  });

  /// The app.
  final Widget child;

  /// The ways the inspector can be opened. Use [show] to open it from code.
  final Set<TracklyTrigger> triggers;

  /// Whether to add [controller]'s log output to `TracklyLogger.output`, so
  /// logs show up in the Logs tab.
  final bool captureLogs;

  /// The navigator to open the inspector in. Found automatically if `null`.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The controller that stores calls and logs, shared by the whole app.
  static final controller = TracklyInspectorController();

  /// A `MaterialApp.builder` that adds the inspector with default settings.
  static Widget builder(BuildContext context, Widget? child) =>
      TracklyInspector(child: child ?? const SizedBox.shrink());

  /// Opens the inspector.
  static void show() => _state?._open();

  /// Closes the inspector.
  static void hide() => _state?._close();

  /// Starts inspect mode: touch any text or image on screen to find the
  /// request its data came from.
  static void inspect() => _state?._startInspect();

  /// Whether the inspector is open.
  static bool get isOpen => _state?._isOpen ?? false;

  /// Whether inspect mode is on.
  static bool get isInspecting => _state?._inspecting ?? false;

  static _TracklyInspectorState? _state;

  @override
  State<TracklyInspector> createState() => _TracklyInspectorState();
}

class _TracklyInspectorState extends State<TracklyInspector> {
  final _appKey = GlobalKey();
  var _isOpen = false;
  var _inspecting = false;
  var _lastAttributedCall = 0;
  NavigatorState? _navigator;
  TracklyOutput? _previousOutput;
  TracklyOutput? _installedOutput;

  TracklyInspectorController get _controller => TracklyInspector.controller;

  @override
  void initState() {
    super.initState();
    TracklyInspector._state = this;
    _controller.addListener(_recordScreens);
    if (widget.captureLogs && _controller.enabled) {
      _previousOutput = TracklyLogger.output;
      _installedOutput = TracklyMultiOutput([
        _previousOutput!,
        _controller.logOutput,
      ]);
      TracklyLogger.output = _installedOutput!;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_recordScreens);
    if (TracklyInspector._state == this) TracklyInspector._state = null;
    if (_installedOutput != null &&
        identical(TracklyLogger.output, _installedOutput)) {
      TracklyLogger.output = _previousOutput!;
    }
    super.dispose();
  }

  NavigatorState? _findNavigator() {
    final fromKey = widget.navigatorKey?.currentState;
    if (fromKey != null) return fromKey;
    final cached = _navigator;
    if (cached != null && cached.mounted) return cached;

    // The first Navigator below this widget is the app's root navigator.
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return _navigator = found;
  }

  /// Remembers which screen was showing when each new call was made, so
  /// inspect mode can list the calls from the current screen.
  void _recordScreens() {
    final calls = _controller.calls;
    if (!mounted || calls.isEmpty || calls.last.id <= _lastAttributedCall) {
      return;
    }
    final navigator = _findNavigator();
    final route = navigator == null ? null : topRouteOf(navigator);
    if (route != null && !isInspectorRoute(route)) {
      for (final call in calls.reversed) {
        if (call.id <= _lastAttributedCall) break;
        recordScreen(call, route);
      }
    }
    _lastAttributedCall = calls.last.id;
  }

  /// Shows [route] with the bubble hidden, and returns its result.
  Future<T?> _push<T>(Route<T> route) async {
    final navigator = _findNavigator();
    if (navigator == null) {
      debugPrint(
        'TracklyInspector: no Navigator found. Put TracklyInspector in '
        'MaterialApp.builder, or pass a navigatorKey.',
      );
      return null;
    }
    setState(() => _isOpen = true);
    final result = await navigator.push(route);
    if (mounted) setState(() => _isOpen = false);
    return result;
  }

  Future<void> _open() async {
    if (_isOpen || !mounted) return;
    await _push(
      InspectorHomePage.route(
        _controller,
        onInspect: () {
          _close();
          _startInspect();
        },
      ),
    );
  }

  void _close() {
    if (!_isOpen) return;
    _findNavigator()?.popUntil((route) => !isInspectorRoute(route));
  }

  void _startInspect() {
    if (!mounted || _inspecting || !_controller.enabled) return;
    HapticFeedback.selectionClick();
    setState(() => _inspecting = true);
  }

  void _stopInspect() {
    if (mounted) setState(() => _inspecting = false);
  }

  PickedElement? _pick(Offset globalPosition) {
    final app = _appKey.currentContext?.findRenderObject();
    if (app is! RenderBox || !app.hasSize) return null;
    return pickElement(app, globalPosition);
  }

  Future<void> _showSources(PickedElement picked) async {
    _stopInspect();
    final navigator = _findNavigator();
    final screen = navigator == null ? null : topRouteOf(navigator);
    final calls = _controller.calls.reversed.toList();

    final action = await _push(
      SourceSheet.route(
        SourceSheet(
          picked: picked,
          matches: findSources(
            texts: picked.texts,
            imageUrls: picked.imageUrls,
            calls: calls,
          ),
          screenCalls: [
            if (screen != null)
              for (final call in calls)
                if (wasMadeOn(call, screen)) call,
          ],
          recentCalls: calls.take(10).toList(),
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case InspectAgainAction():
        _startInspect();
      case OpenCallAction(:final call, :final path, :final value):
        await _push(
          CallPage.route(
            _controller,
            call,
            initialTab: path == null ? 0 : 2,
            highlightPath: path,
            highlightValue: value,
          ),
        );
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.enabled) return widget.child;

    final triggers = widget.triggers;
    return ShakeDetector(
      enabled: triggers.contains(TracklyTrigger.shake) && !_inspecting,
      onShake: _open,
      child: MultiFingerLongPress(
        enabled:
            triggers.contains(TracklyTrigger.longPress) &&
            !_isOpen &&
            !_inspecting,
        onTrigger: _open,
        child: Stack(
          fit: StackFit.expand,
          children: [
            KeyedSubtree(key: _appKey, child: widget.child),
            if (triggers.contains(TracklyTrigger.bubble))
              InspectorBubble(
                controller: _controller,
                visible: !_isOpen && !_inspecting,
                onTap: _open,
                onLongPress: _startInspect,
              ),
            if (_inspecting)
              Positioned.fill(
                child: InspectOverlay(
                  pick: _pick,
                  onPicked: _showSources,
                  onCancel: _stopInspect,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
