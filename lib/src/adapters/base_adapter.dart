import '../core/event_bus.dart';
import '../logging/analyst_logger.dart';
import '../models/runtime_event.dart';

/// Contract for optional framework/library adapters.
///
/// Adapters are registered with [ExtensionRegistry] and started/stopped
/// alongside the engine. They have direct access to [EventBus] to publish
/// normalized [RuntimeEvent]s.
abstract class AnalystAdapter {
  AnalystAdapter(EventBus eventBus) : _eventBus = eventBus;

  final EventBus _eventBus;
  late final AnalystLogger log = AnalystLogger.forName(id);

  bool _active = false;
  bool get isActive => _active;

  /// Stable adapter identifier.
  String get id;

  /// Human-readable display name.
  String get displayName;

  Future<void> start() async {
    if (_active) return;
    _active = true;
    await onStart();
    log.info('Adapter started: $id');
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    await onStop();
    log.info('Adapter stopped: $id');
  }

  Future<void> onStart();
  Future<void> onStop();

  void publish(RuntimeEvent event) => _eventBus.publish(event);

  EventBus get eventBus => _eventBus;
}
