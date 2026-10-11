import 'package:flutter/widgets.dart';

import '../core/calls.dart';

/// Route name shared by all inspector pages, used to close them together.
const inspectorRoutePrefix = 'trackly_inspector';

/// Whether [route] is one of the inspector's own pages.
bool isInspectorRoute(Route<dynamic> route) =>
    route.settings.name?.startsWith(inspectorRoutePrefix) ?? false;

class _Screen {
  _Screen(Route<dynamic> route)
    : route = WeakReference(route),
      name = describeRoute(route);

  final WeakReference<Route<dynamic>> route;
  final String? name;
}

final _screens = Expando<_Screen>('trackly_inspector.screen');

/// A name for the screen [route] shows: the route's name, or else the type
/// of its page widget, e.g. `ProductsPage`.
String describeRoute(Route<dynamic> route) {
  final name = route.settings.name;
  if (name != null && name.isNotEmpty) return name;

  // A ModalRoute builds its page inside a RepaintBoundary, a Builder, and
  // often a Semantics. The first other widget is the page.
  var element = switch (route) {
    ModalRoute<dynamic>(:final subtreeContext?) => subtreeContext as Element,
    _ => null,
  };
  for (var depth = 0; element != null && depth < 6; depth++) {
    final widget = element.widget;
    if (widget is! RepaintBoundary &&
        widget is! Builder &&
        widget is! Semantics) {
      return widget.runtimeType.toString();
    }
    Element? child;
    element.visitChildElements((found) => child ??= found);
    element = child;
  }
  return route.runtimeType.toString();
}

/// The route on top of [navigator].
Route<dynamic>? topRouteOf(NavigatorState navigator) {
  Route<dynamic>? top;
  // A predicate that's true for the top route stops popUntil before it pops
  // anything, so this only reads the top route.
  navigator.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// Records that [call] was made while [route] was on screen.
void recordScreen(TracklyHttpCall call, Route<dynamic> route) {
  _screens[call] ??= _Screen(route);
}

/// Whether [call] was made while [route] was on screen.
bool wasMadeOn(TracklyHttpCall call, Route<dynamic> route) =>
    identical(_screens[call]?.route.target, route);

/// The name of the route that was on screen when [call] was made, if known.
String? screenNameOf(TracklyHttpCall call) => _screens[call]?.name;
