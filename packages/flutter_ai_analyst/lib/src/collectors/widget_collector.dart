import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../core/runtime_store.dart';
import '../models/runtime_event.dart';
import '../models/widget_snapshot.dart';
import 'base_collector.dart';

/// Collects widget-tree snapshots and per-widget rebuild counts.
///
/// Hooks into [WidgetInspectorService] and [debugPrintRebuildDirtyWidgets]
/// to capture rebuild events without modifying user code.
class WidgetCollector extends BaseCollector {
  WidgetCollector({
    required super.eventBus,
    required super.config,
    required RuntimeStore store,
  }) : _store = store;

  final RuntimeStore _store;
  final _uuid = const Uuid();
  Timer? _snapshotTimer;

  @override
  String get id => 'widget_collector';

  @override
  Future<void> onStart() async {
    // Enable rebuild tracking in debug mode.
    if (kDebugMode) {
      debugPrintRebuildDirtyWidgets = true;
    }

    // Periodic widget-tree snapshots.
    _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _captureWidgetTree();
    });
  }

  @override
  Future<void> onStop() async {
    _snapshotTimer?.cancel();
    if (kDebugMode) {
      debugPrintRebuildDirtyWidgets = false;
    }
  }

  void _captureWidgetTree() {
    try {
      final root = _buildWidgetNode(
        WidgetsBinding.instance.rootElement,
        depth: 0,
        maxDepth: config.current.widgetSnapshotMaxDepth,
      );
      final snapshot = WidgetTreeSnapshot(
        capturedAt: DateTime.now(),
        root: root,
        totalNodes: root?.totalNodes ?? 0,
        maxDepth: root?.maxDepth ?? 0,
      );
      _store.updateWidgetTree(snapshot);
      eventBus.publish(RuntimeEvent(
        id: _uuid.v4(),
        type: RuntimeEventType.widgetTreeSnapshot,
        timestamp: DateTime.now(),
        source: id,
        payload: {
          'totalNodes': snapshot.totalNodes,
          'maxDepth': snapshot.maxDepth,
        },
      ));
    } catch (e, st) {
      log.warning('Widget tree capture failed', e, st);
    }
  }

  WidgetNode? _buildWidgetNode(
    Element? element, {
    required int depth,
    required int maxDepth,
  }) {
    if (element == null) return null;
    if (depth > maxDepth) return null;

    final widget = element.widget;
    final type = widget.runtimeType.toString();
    final key = widget.key?.toString();

    Rect? rect;
    if (element is RenderObjectElement) {
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final offset = ro.localToGlobal(Offset.zero);
        final size = ro.size;
        rect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      }
    }

    final children = <WidgetNode>[];
    var nodeCount = 0;
    final maxNodes = config.current.widgetSnapshotMaxNodes;

    element.visitChildren((child) {
      if (nodeCount >= maxNodes) return;
      final node = _buildWidgetNode(child, depth: depth + 1, maxDepth: maxDepth);
      if (node != null) {
        children.add(node);
        nodeCount += node.totalNodes;
      }
    });

    return WidgetNode(
      id: '${type}_$depth',
      type: type,
      depth: depth,
      key: key,
      bounds: rect == null
          ? null
          : WidgetBounds(
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
            ),
      children: children,
      rebuildCount: _store.widgetRebuildCounts[type] ?? 0,
    );
  }

  /// Called by the engine when a rebuild event is detected externally.
  void recordRebuild(String widgetType) {
    _store.incrementRebuild(widgetType);
    eventBus.publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.widgetRebuilt,
      timestamp: DateTime.now(),
      source: id,
      payload: {
        'widgetType': widgetType,
        'totalRebuilds': _store.widgetRebuildCounts[widgetType] ?? 0,
      },
    ));
  }
}
