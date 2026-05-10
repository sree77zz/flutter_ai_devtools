import 'dart:async';

import '../models/runtime_event.dart';
import '../logging/analyst_logger.dart';

typedef NotificationHandler = Future<void> Function(RuntimeEvent event);

/// Threshold-based notification system.
///
/// Callers register [NotificationRule]s; when the event bus delivers an event,
/// every matching rule is evaluated and its handler invoked asynchronously.
class NotifierService {
  NotifierService();

  final _rules = <NotificationRule>[];
  final _log = AnalystLogger.forName('NotifierService');

  void addRule(NotificationRule rule) => _rules.add(rule);
  void removeRule(NotificationRule rule) => _rules.remove(rule);

  Future<void> evaluate(RuntimeEvent event) async {
    for (final rule in List.of(_rules)) {
      if (!rule.matches(event)) continue;
      try {
        await rule.handler(event);
      } catch (e, st) {
        _log.warning('Notification rule "${rule.name}" threw', e, st);
      }
    }
  }
}

class NotificationRule {
  NotificationRule({
    required this.name,
    required this.predicate,
    required this.handler,
  });

  final String name;
  final bool Function(RuntimeEvent) predicate;
  final NotificationHandler handler;

  bool matches(RuntimeEvent event) {
    try {
      return predicate(event);
    } catch (_) {
      return false;
    }
  }
}
