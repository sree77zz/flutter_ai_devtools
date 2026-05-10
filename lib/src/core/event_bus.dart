import 'dart:async';

import '../models/runtime_event.dart';
import '../logging/analyst_logger.dart';

/// Central broadcast event bus for the analyst engine.
///
/// All collectors and adapters publish [RuntimeEvent]s here. The analyzer
/// engine, notifier service, and MCP transport layer subscribe independently —
/// no component couples directly to another.
class EventBus {
  EventBus() : _controller = StreamController<RuntimeEvent>.broadcast();

  final StreamController<RuntimeEvent> _controller;
  final _log = AnalystLogger.forName('EventBus');

  /// All events as a broadcast stream.
  Stream<RuntimeEvent> get events => _controller.stream;

  /// Filtered stream for a specific event type.
  Stream<RuntimeEvent> on(RuntimeEventType type) =>
      events.where((e) => e.type == type);

  /// Filtered stream for a specific source.
  Stream<RuntimeEvent> from(String source) =>
      events.where((e) => e.source == source);

  /// Filtered stream matching any of [types].
  Stream<RuntimeEvent> onAny(Set<RuntimeEventType> types) =>
      events.where((e) => types.contains(e.type));

  void publish(RuntimeEvent event) {
    if (_controller.isClosed) return;
    _log.debug('publish ${event.type.name} from ${event.source}');
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
