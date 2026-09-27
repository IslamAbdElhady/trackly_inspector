import 'package:flutter/material.dart';

import '../core/calls.dart';
import 'logs_tab.dart';
import 'network_tab.dart';
import 'widgets.dart';

/// Route name shared by all inspector pages, used to close them together.
const inspectorRoutePrefix = 'trackly_inspector';

/// The inspector's main page, with Network and Logs tabs.
class InspectorHomePage extends StatelessWidget {
  /// Creates the page.
  const InspectorHomePage({super.key, required this.controller});

  /// Where calls and logs come from.
  final TracklyInspectorController controller;

  /// A route to this page.
  static Route<void> route(
    TracklyInspectorController controller,
  ) => MaterialPageRoute(
    settings: const RouteSettings(name: inspectorRoutePrefix),
    fullscreenDialog: true,
    builder:
        (_) => InspectorScope(child: InspectorHomePage(controller: controller)),
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
