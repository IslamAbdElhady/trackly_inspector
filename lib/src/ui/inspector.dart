import 'package:flutter/material.dart';
import 'package:trackly_logger/trackly_logger.dart';

import '../core/calls.dart';
import 'home_page.dart';
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

  /// Whether the inspector is open.
  static bool get isOpen => _state?._isOpen ?? false;

  static _TracklyInspectorState? _state;

  @override
  State<TracklyInspector> createState() => _TracklyInspectorState();
}

class _TracklyInspectorState extends State<TracklyInspector> {
  var _isOpen = false;
  NavigatorState? _navigator;
  TracklyOutput? _previousOutput;
  TracklyOutput? _installedOutput;

  TracklyInspectorController get _controller => TracklyInspector.controller;

  @override
  void initState() {
    super.initState();
    TracklyInspector._state = this;
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
    return found;
  }

  Future<void> _open() async {
    if (_isOpen || !mounted) return;
    final navigator = _findNavigator();
    if (navigator == null) {
      debugPrint(
        'TracklyInspector: no Navigator found. Put TracklyInspector in '
        'MaterialApp.builder, or pass a navigatorKey.',
      );
      return;
    }
    _navigator = navigator;
    setState(() => _isOpen = true);
    await navigator.push(InspectorHomePage.route(_controller));
    if (mounted) setState(() => _isOpen = false);
  }

  void _close() {
    if (!_isOpen) return;
    _navigator?.popUntil(
      (route) =>
          !(route.settings.name?.startsWith(inspectorRoutePrefix) ?? false),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.enabled) return widget.child;

    final triggers = widget.triggers;
    return ShakeDetector(
      enabled: triggers.contains(TracklyTrigger.shake),
      onShake: _open,
      child: MultiFingerLongPress(
        enabled: triggers.contains(TracklyTrigger.longPress) && !_isOpen,
        onTrigger: _open,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (triggers.contains(TracklyTrigger.bubble))
              InspectorBubble(
                controller: _controller,
                visible: !_isOpen,
                onTap: _open,
              ),
          ],
        ),
      ),
    );
  }
}
