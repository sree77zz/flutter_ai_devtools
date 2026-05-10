import 'package:meta/meta.dart';

enum RouteEventKind { push, pop, replace, remove, initial }

@immutable
class RouteInfo {
  const RouteInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.timestamp,
    this.arguments,
    this.previousRoute,
  });

  final String id;
  final String name;
  final RouteEventKind kind;
  final DateTime timestamp;
  final Object? arguments;
  final String? previousRoute;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'timestamp': timestamp.toIso8601String(),
        if (arguments != null) 'arguments': arguments.toString(),
        if (previousRoute != null) 'previousRoute': previousRoute,
      };
}

/// Tracks the current navigation stack.
class NavigationState {
  NavigationState({
    required this.currentRoute,
    required this.stack,
    required this.history,
  });

  final String currentRoute;
  final List<String> stack;
  final List<RouteInfo> history;

  Map<String, dynamic> toJson() => {
        'currentRoute': currentRoute,
        'stack': stack,
        'recentHistory':
            history.reversed.take(20).map((r) => r.toJson()).toList(),
      };
}
