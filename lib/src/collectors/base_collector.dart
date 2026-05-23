// lib/src/collectors/base_collector.dart
import '../config.dart';
import '../store/runtime_store.dart';

abstract class BaseCollector {
  BaseCollector({required this.store, required this.config});

  final RuntimeStore store;
  final CollectorConfig config;

  bool _running = false;
  bool get isRunning => _running;

  String get id;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await onStart();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await onStop();
  }

  Future<void> onStart();
  Future<void> onStop();
}
