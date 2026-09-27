import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'element_picker.dart';
import 'theme.dart';

/// Covers the app while inspecting: highlights what's under the finger, and
/// reports it when the finger lifts. Touches never reach the app.
class InspectOverlay extends StatefulWidget {
  /// Creates the overlay.
  const InspectOverlay({
    super.key,
    required this.pick,
    required this.onPicked,
    required this.onCancel,
  });

  /// Finds what's at a global position.
  final PickedElement? Function(Offset globalPosition) pick;

  /// Called with what the user picked.
  final ValueChanged<PickedElement> onPicked;

  /// Called when the user leaves inspect mode.
  final VoidCallback onCancel;

  @override
  State<InspectOverlay> createState() => _InspectOverlayState();
}

class _InspectOverlayState extends State<InspectOverlay> {
  PickedElement? _picked;
  var _nothingHere = false;

  void _update(PointerEvent event) {
    setState(() {
      _picked = widget.pick(event.position);
      _nothingHere = false;
    });
  }

  void _finish(PointerUpEvent event) {
    final picked = widget.pick(event.position);
    if (picked == null || picked.isEmpty) {
      setState(() {
        _picked = null;
        _nothingHere = true;
      });
      return;
    }
    widget.onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final origin =
        (context.findRenderObject() as RenderBox?)?.localToGlobal(
          Offset.zero,
        ) ??
        Offset.zero;
    final rect = _picked?.rect.shift(-origin);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _update,
              onPointerMove: _update,
              onPointerUp: _finish,
              onPointerCancel: (_) => setState(() => _picked = null),
              child: CustomPaint(painter: _HighlightPainter(rect)),
            ),
          ),
          if (rect != null && _picked != null)
            _Label(rect: rect, picked: _picked!),
          _Banner(
            message:
                _nothingHere
                    ? 'No text or image here. Try another spot.'
                    : 'Touch any text or image to find its request',
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(this.rect);

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = this.rect;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x1A000000),
    );
    if (rect == null) return;
    canvas
      ..drawRect(rect, Paint()..color = const Color(0x332563EB))
      ..drawRect(
        rect,
        Paint()
          ..color = blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => old.rect != rect;
}

class _Label extends StatelessWidget {
  const _Label({required this.rect, required this.picked});

  final Rect rect;
  final PickedElement picked;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final below = rect.bottom + 40 < screen.height;
    final summary = picked.isEmpty ? 'Nothing to inspect' : picked.summary;
    return Positioned(
      // Leave room for the label itself, so something flush against the
      // right edge doesn't get a zero-width box.
      left: math.max(8.0, math.min(rect.left, screen.width - 160)),
      top: below ? rect.bottom + 6 : null,
      bottom: below ? null : screen.height - rect.top + 6,
      right: 8,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xF0111827),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${picked.kind}  ',
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: summary),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono(size: 11.5, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onCancel});

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: const Color(0xF0111827),
            borderRadius: BorderRadius.circular(14),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  const Icon(Icons.ads_click, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Stop inspecting',
                    child: InkResponse(
                      onTap: onCancel,
                      radius: 22,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
