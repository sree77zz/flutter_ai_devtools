// lib/src/collectors/route_collector.dart
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import '../models/route_info.dart';
import 'base_collector.dart';

/// [NavigatorObserver] that tracks push/pop/replace/remove events.
///
/// Attach [AnalystNavigatorObserver] to your app's Navigator via
/// [MaterialApp.navigatorObservers] or through the devtools initialisation.
class AnalystNavigatorObserver extends NavigatorObserver {
  AnalystNavigatorObserver(this._collector);

  final RouteCollector _collector;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _collector._onRouteEvent(route, previousRoute, RouteEventKind.push);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _collector._onRouteEvent(previousRoute, route, RouteEventKind.pop);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _collector._onRouteEvent(newRoute, oldRoute, RouteEventKind.replace);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _collector._onRouteEvent(route, previousRoute, RouteEventKind.remove);
}

/// Collects navigation events and persists the latest [RouteInfo] in
/// [RuntimeStore].
class RouteCollector extends BaseCollector {
  RouteCollector({required super.store, required super.config});

  final _uuid = const Uuid();
  final _stack = <String>[];

  late final AnalystNavigatorObserver observer =
      AnalystNavigatorObserver(this);

  @override
  String get id => 'route_collector';

  @override
  Future<void> onStart() async {
    // NavigatorObserver is attached externally; no binding hook needed here.
  }

  @override
  Future<void> onStop() async {}

  void _onRouteEvent(
    Route<dynamic>? route,
    Route<dynamic>? previous,
    RouteEventKind kind,
  ) {
    final name = _routeName(route);
    final prevName = _routeName(previous);

    switch (kind) {
      case RouteEventKind.push:
      case RouteEventKind.initial:
        _stack.add(name);
      case RouteEventKind.pop:
      case RouteEventKind.remove:
        if (_stack.isNotEmpty) _stack.removeLast();
      case RouteEventKind.replace:
        if (_stack.isNotEmpty) _stack[_stack.length - 1] = name;
    }

    store.updateRoute(RouteInfo(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      timestamp: DateTime.now(),
      arguments: route?.settings.arguments,
      previousRoute: prevName,
    ));
  }

  String _routeName(Route<dynamic>? route) =>
      route?.settings.name ?? route.runtimeType.toString();
}
