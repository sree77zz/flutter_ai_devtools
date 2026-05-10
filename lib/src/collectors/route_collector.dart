import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../models/route_info.dart';
import '../models/runtime_event.dart';
import 'base_collector.dart';

/// [NavigatorObserver] that tracks push/pop/replace events.
///
/// Attach [AnalystNavigatorObserver] to your app's Navigator via
/// [MaterialApp.navigatorObservers] or pass it through [FlutterAiAnalyst.navigatorObserver].
class AnalystNavigatorObserver extends NavigatorObserver {
  AnalystNavigatorObserver(this._collector);

  final RouteCollector _collector;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _collector._onRouteEvent(
        route,
        previousRoute,
        RouteEventKind.push,
      );

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _collector._onRouteEvent(
        previousRoute,
        route,
        RouteEventKind.pop,
      );

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

/// Collects navigation events and maintains a route stack in [RuntimeStore].
class RouteCollector extends BaseCollector {
  RouteCollector({
    required super.eventBus,
    required super.config,
    required RuntimeStore store,
  }) : _store = store;

  final RuntimeStore _store;
  final _uuid = const Uuid();
  final _stack = <String>[];
  final _history = <RouteInfo>[];

  late final AnalystNavigatorObserver observer =
      AnalystNavigatorObserver(this);

  @override
  String get id => 'route_collector';

  @override
  Future<void> onStart() async {
    // NavigatorObserver is attached externally by user; no binding hook needed.
    log.info('RouteCollector ready. Attach observer to your Navigator.');
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

    // Update the stack.
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

    final info = RouteInfo(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      timestamp: DateTime.now(),
      arguments: route?.settings.arguments,
      previousRoute: prevName,
    );

    final limit = config.current.routeHistorySize;
    if (_history.length >= limit) _history.removeAt(0);
    _history.add(info);

    _store.updateNavigation(NavigationState(
      currentRoute: _stack.isNotEmpty ? _stack.last : '/',
      stack: List.of(_stack),
      history: List.of(_history),
    ));

    eventBus.publish(RuntimeEvent(
      id: _uuid.v4(),
      type: _kindToEventType(kind),
      timestamp: info.timestamp,
      source: id,
      payload: info.toJson(),
    ));
  }

  String _routeName(Route<dynamic>? route) =>
      route?.settings.name ?? route.runtimeType.toString();

  RuntimeEventType _kindToEventType(RouteEventKind kind) => switch (kind) {
        RouteEventKind.push || RouteEventKind.initial =>
          RuntimeEventType.navigationPush,
        RouteEventKind.pop || RouteEventKind.remove =>
          RuntimeEventType.navigationPop,
        RouteEventKind.replace => RuntimeEventType.navigationReplace,
      };
}
