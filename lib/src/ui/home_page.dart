import 'package:flutter/material.dart';

import '../core/calls.dart';
import 'logs_tab.dart';
import 'network_tab.dart';
import 'screens.dart';
import 'widgets.dart';

/// The inspector's main page, with Network and Logs tabs.
class InspectorHomePage extends StatelessWidget {
  /// Creates the page.
  const InspectorHomePage({
    super.key,
    required this.controller,
    required this.onInspect,
  });

  /// Where calls and logs come from.
  final TracklyInspectorController controller;

  /// Closes the inspector and starts picking an element on screen.
  final VoidCallback onInspect;

  /// A route to this page.
  static Route<void> route(
    TracklyInspectorController controller, {
    required VoidCallback onInspect,
  }) => MaterialPageRoute(
    settings: const RouteSettings(name: inspectorRoutePrefix),
    fullscreenDialog: true,
    builder:
        (_) => InspectorScope(
          child: InspectorHomePage(
            controller: controller,
            onInspect: onInspect,
          ),
        ),
  );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar_rounded, size: 22),
              SizedBox(width: 8),
              Text('Trackly Inspector'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Inspect an element',
              icon: const Icon(Icons.ads_click),
              onPressed: onInspect,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                child: ListenableBuilder(
                  listenable: controller,
                  builder:
                      (_, _) => Text('Network (${controller.calls.length})'),
                ),
              ),
              Tab(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => Text('Logs (${controller.logs.length})'),
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            NetworkTab(controller: controller),
            LogsTab(controller: controller),
          ],
        ),
      ),
    );
  }
}
