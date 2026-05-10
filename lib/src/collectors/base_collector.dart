import '../core/event_bus.dart';
import '../services/config_manager.dart';
import '../logging/analyst_logger.dart';

/// Contract for all runtime data collectors.
///
/// Collectors attach to Flutter binding hooks (WidgetInspectorService,
/// SchedulerBinding, etc.) and publish normalized [RuntimeEvent]s to
/// [EventBus]. They are started/stopped by [AnalystEngine].
abstract class BaseCollector {
  BaseCollector({required EventBus eventBus, required ConfigManager config})
      : _eventBus = eventBus,
        _config = config;

  final EventBus _eventBus;
  final ConfigManager _config;

  late final AnalystLogger log = AnalystLogger.forName(id);

  /// Stable identifier used as the event [source] field.
  String get id;

  /// Whether this collector is currently active.
  bool _running = false;
  bool get isRunning => _running;

  /// Called once by the engine. Subclasses hook into Flutter bindings here.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await onStart();
    log.info('Collector started: $id');
  }

  /// Called once by the engine on shutdown.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await onStop();
    log.info('Collector stopped: $id');
  }

  /// Subclass hook for start-up logic.
  Future<void> onStart();

  /// Subclass hook for clean-up logic.
  Future<void> onStop();

  EventBus get eventBus => _eventBus;
  ConfigManager get config => _config;
}
