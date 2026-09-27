import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/calls.dart';
import 'theme.dart';

/// A draggable button that sticks to the nearest side of the screen and
/// shows the number of calls and the status of the latest one.
class InspectorBubble extends StatefulWidget {
  /// Creates the bubble. It must be a direct child of a [Stack].
  const InspectorBubble({
    super.key,
    required this.controller,
    required this.visible,
    required this.onTap,
    required this.onLongPress,
  });

  /// Where the calls come from.
  final TracklyInspectorController controller;

  /// Whether the bubble is shown. It keeps its position while hidden.
  final bool visible;

  /// Called when the bubble is tapped.
  final VoidCallback onTap;

  /// Called when the bubble is long-pressed.
  final VoidCallback onLongPress;

  @override
  State<InspectorBubble> createState() => _InspectorBubbleState();
}

class _InspectorBubbleState extends State<InspectorBubble> {
  static const _size = 54.0;
  static const _margin = 8.0;

  Offset? _position;
  var _dragging = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final minX = media.padding.left + _margin;
    final maxX = media.size.width - media.padding.right - _size - _margin;
    final minY = media.padding.top + _margin;
    final maxY = media.size.height - media.padding.bottom - _size - _margin;

    final wanted = _position ?? Offset(maxX, media.size.height * 0.62);
    final position = Offset(
      wanted.dx.clamp(minX, math.max(minX, maxX)),
      wanted.dy.clamp(minY, math.max(minY, maxY)),
    );

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onPanStart:
                (_) => setState(() {
                  _dragging = true;
                  _position = position;
                }),
            onPanUpdate:
                (details) =>
                    setState(() => _position = _position! + details.delta),
            onPanEnd:
                (_) => setState(() {
                  _dragging = false;
                  final centerX = _position!.dx + _size / 2;
                  _position = Offset(
                    centerX < media.size.width / 2 ? minX : maxX,
                    _position!.dy.clamp(minY, math.max(minY, maxY)),
                  );
                }),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder:
                  (context, _) => _BubbleFace(
                    size: _size,
                    count: widget.controller.calls.length,
                    pending: widget.controller.pendingCount > 0,
                    ring: statusColor(widget.controller.lastCall),
                    hasCalls: widget.controller.lastCall != null,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleFace extends StatelessWidget {
  const _BubbleFace({
    required this.size,
    required this.count,
    required this.pending,
    required this.ring,
    required this.hasCalls,
  });

  final double size;
  final int count;
  final bool pending;
  final Color ring;
  final bool hasCalls;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open Trackly Inspector',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xF0111827),
                border: Border.all(
                  color: hasCalls ? ring : Colors.white24,
                  width: 2.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.radar_rounded, color: Colors.white, size: 26),
              ),
            ),
            if (pending)
              const Positioned.fill(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ring == grey ? blue : ring,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 999 ? '999+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Calls [onTrigger] when [fingers] fingers are held still on the screen for
/// [duration].
///
/// Listens to raw pointer events, so it never blocks the app's own gestures.
class MultiFingerLongPress extends StatefulWidget {
  /// Creates the detector.
  const MultiFingerLongPress({
    super.key,
    required this.enabled,
    required this.onTrigger,
    required this.child,
    this.fingers = 2,
    this.duration = const Duration(milliseconds: 700),
  });

  /// Whether the gesture is detected.
  final bool enabled;

  /// Called when the gesture is detected.
  final VoidCallback onTrigger;

  /// The number of fingers to hold down.
  final int fingers;

  /// How long to hold them.
  final Duration duration;

  /// The app.
  final Widget child;

  @override
  State<MultiFingerLongPress> createState() => _MultiFingerLongPressState();
}

class _MultiFingerLongPressState extends State<MultiFingerLongPress> {
  static const _slop = 24.0;

  final _starts = <int, Offset>{};
  Timer? _timer;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || event.kind != PointerDeviceKind.touch) return;
    _starts[event.pointer] = event.position;
    _timer?.cancel();
    _timer =
        _starts.length == widget.fingers ? Timer(widget.duration, _fire) : null;
  }

  void _move(PointerMoveEvent event) {
    final start = _starts[event.pointer];
    if (start != null && (event.position - start).distance > _slop) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _up(PointerEvent event) {
    _starts.remove(event.pointer);
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    _starts.clear();
    HapticFeedback.mediumImpact();
    widget.onTrigger();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}

/// Calls [onShake] when the device is shaken. Works on Android and iOS
/// devices; simulators don't report motion.
class ShakeDetector extends StatefulWidget {
  /// Creates the detector.
  const ShakeDetector({
    super.key,
    required this.enabled,
    required this.onShake,
    required this.child,
  });

  /// Whether shaking is detected.
  final bool enabled;

  /// Called when the device is shaken.
  final VoidCallback onShake;

  /// The app.
  final Widget child;

  @override
  State<ShakeDetector> createState() => _ShakeDetectorState();
}

class _ShakeDetectorState extends State<ShakeDetector> {
  // Acceleration in m/s², without gravity, that counts as a jolt.
  static const _threshold = 13.0;
  static const _window = Duration(milliseconds: 800);
  static const _cooldown = Duration(milliseconds: 1500);

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  final _jolts = <DateTime>[];
  DateTime? _lastShake;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ShakeDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.enabled && _supported && _subscription == null) {
      _subscription = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(_onEvent, onError: (Object _) {}, cancelOnError: true);
    } else if (!widget.enabled) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _onEvent(UserAccelerometerEvent event) {
    final force = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (force < _threshold) return;

    final now = DateTime.now();
    _jolts
      ..removeWhere((time) => now.difference(time) > _window)
      ..add(now);
    final coolingDown =
        _lastShake != null && now.difference(_lastShake!) < _cooldown;
    if (_jolts.length >= 3 && !coolingDown) {
      _lastShake = now;
      _jolts.clear();
      widget.onShake();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
