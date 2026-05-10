import '../adapters/base_adapter.dart';
import '../logging/analyst_logger.dart';

/// Registry for optional extension adapters (Bloc, Riverpod, GetX, …).
///
/// Adapters are started/stopped with the engine lifecycle. Each adapter
/// receives a reference to the event bus on [attach] so it can publish
/// normalized [RuntimeEvent]s.
class ExtensionRegistry {
  ExtensionRegistry();

  final _adapters = <String, AnalystAdapter>{};
  final _log = AnalystLogger.forName('ExtensionRegistry');

  void register(AnalystAdapter adapter) {
    if (_adapters.containsKey(adapter.id)) {
      _log.warning('Adapter already registered: ${adapter.id}');
      return;
    }
    _adapters[adapter.id] = adapter;
    _log.info('Registered adapter: ${adapter.id}');
  }

  Future<void> startAll() async {
    for (final a in _adapters.values) {
      try {
        await a.start();
        _log.info('Started adapter: ${a.id}');
      } catch (e, st) {
        _log.error('Failed to start adapter ${a.id}', e, st);
      }
    }
  }

  Future<void> stopAll() async {
    for (final a in _adapters.values) {
      try {
        await a.stop();
      } catch (e, st) {
        _log.warning('Error stopping adapter ${a.id}', e, st);
      }
    }
  }

  AnalystAdapter? find(String id) => _adapters[id];

  List<AnalystAdapter> get all => List.unmodifiable(_adapters.values);
}
