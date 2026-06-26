import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'collectors/base_collector.dart';
import 'collectors/error_collector.dart';
import 'collectors/frame_collector.dart';
import 'collectors/lifecycle_collector.dart';
import 'collectors/render_collector.dart';
import 'collectors/route_collector.dart';
import 'collectors/widget_collector.dart';
import 'config.dart';
import 'lockfile.dart';
import 'models/issue.dart';
import 'service_extensions.dart';
import 'store/runtime_store.dart';

class FlutterAiDevtools {
  FlutterAiDevtools._();

  static RuntimeStore? _store;
  static RouteCollector? _routeCollector;
  static final List<BaseCollector> _collectors = [];
  static bool _running = false;
  static bool _extensionsRegistered = false;

  static final NavigatorObserver observer = _DelegatingNavigatorObserver();

  static RuntimeStore? get store => _store;

  static Future<void> start({
    CollectorConfig collectors = const CollectorConfig(),
  }) async {
    if (_running) await stop();
    _running = true;

    _store = RuntimeStore(
      maxErrors: collectors.maxErrors,
      maxFrames: collectors.maxFrames,
      maxRenderIssues: collectors.maxRenderIssues,
      maxIssues: collectors.maxIssues,
      recurrenceThreshold: collectors.recurrenceThreshold,
    );

    if (collectors.routes) {
      _routeCollector = RouteCollector(store: _store!, config: collectors);
    }

    _collectors.clear();
    if (collectors.widgets) {
      _collectors.add(WidgetCollector(store: _store!, config: collectors));
    }
    if (collectors.errors) {
      _collectors.add(ErrorCollector(store: _store!, config: collectors));
    }
    if (collectors.frames) {
      _collectors.add(FrameCollector(store: _store!, config: collectors));
    }
    if (collectors.renders) {
      _collectors.add(RenderCollector(store: _store!, config: collectors));
    }
    if (collectors.lifecycle) {
      _collectors.add(LifecycleCollector(store: _store!, config: collectors));
    }

    for (final c in _collectors) {
      await c.start();
    }

    await _registerExtensions(_store!);
  }

  static Future<void> stop() async {
    for (final c in _collectors.reversed) {
      await c.stop();
    }
    _collectors.clear();
    _routeCollector = null;
    await deleteLockfile();
    _store = null;
    _running = false;
  }

  static Future<void> _registerExtensions(RuntimeStore store) async {
    if (kIsWeb) return;
    if (!_extensionsRegistered) {
      registerServiceExtensions(store);
      _extensionsRegistered = true;
    }
    // Write VM URI to lockfile so bin/serve.dart can discover it on desktop.
    try {
      final info = await dev.Service.getInfo();
      await writeLockfile(vmServiceUri: info.serverUri?.toString());
    } catch (_) {
      // VM service not available (release mode or unsupported platform).
    }
  }

  /// Reports a handled error so it surfaces in `get_issues`. No-op when devtools
  /// is not started, so calls are safe to leave in production code paths.
  static void reportError(
    Object error,
    StackTrace stackTrace, {
    String? category,
    Map<String, dynamic>? context,
  }) {
    final store = _store;
    if (store == null) return;
    final message = error.toString();
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.reported, '${category ?? ''}|$message'),
      category: IssueCategory.reported,
      severity: IssueSeverity.error,
      source: IssueSource.reported,
      title: message.length > 80 ? '${message.substring(0, 80)}…' : message,
      detail: '$message\n$stackTrace',
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {...?context},
      domainCategory: category,
    ));
  }

  /// Reports a non-exception problem (validation failure, invariant break) so it
  /// surfaces in `get_issues`. No-op when devtools is not started.
  static void reportIssue(
    String title, {
    IssueSeverity severity = IssueSeverity.warning,
    String? category,
    Map<String, dynamic>? context,
  }) {
    final store = _store;
    if (store == null) return;
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.reported, '${category ?? ''}|$title'),
      category: IssueCategory.reported,
      severity: severity,
      source: IssueSource.reported,
      title: title,
      detail: title,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {...?context},
      domainCategory: category,
    ));
  }
}

class _DelegatingNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer.didPush(route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer.didPop(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      FlutterAiDevtools._routeCollector?.observer
          .didReplace(newRoute: newRoute, oldRoute: oldRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      FlutterAiDevtools._routeCollector?.observer
          .didRemove(route, previousRoute);
}
