import 'dart:async';

import '../logging/analyst_logger.dart';

/// Manages periodic background tasks for the analyst engine.
///
/// Each scheduled task is identified by a string key. Scheduling the same key
/// twice replaces the previous timer, preventing duplicate timers on hot
/// restart.
class SchedulerService {
  SchedulerService();

  final _timers = <String, Timer>{};
  final _log = AnalystLogger.forName('Scheduler');

  void schedule({
    required String key,
    required Duration interval,
    required void Function() task,
    bool runImmediately = false,
  }) {
    cancel(key);
    if (runImmediately) {
      try {
        task();
      } catch (e, st) {
        _log.warning('Immediate task "$key" threw', e, st);
      }
    }
    _timers[key] = Timer.periodic(interval, (_) {
      try {
        task();
      } catch (e, st) {
        _log.warning('Periodic task "$key" threw', e, st);
      }
    });
    _log.debug('Scheduled "$key" every ${interval.inMilliseconds}ms');
  }

  void cancel(String key) {
    _timers.remove(key)?.cancel();
  }

  void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  bool isScheduled(String key) => _timers.containsKey(key);
}
