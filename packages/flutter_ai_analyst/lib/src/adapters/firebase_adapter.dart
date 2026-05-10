import 'package:uuid/uuid.dart';

import '../models/runtime_event.dart';
import 'base_adapter.dart';

/// Monitors Firebase service events (Crashlytics, Analytics, Firestore).
///
/// Firebase packages are not compile-time dependencies. Wire up events by
/// calling the tracking methods from your Firebase callbacks:
///
/// ```dart
/// // In FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled:
/// firebaseAdapter.trackCrash(message: error.toString(), stack: stack);
///
/// // In FirebaseAnalytics event logging:
/// firebaseAdapter.trackAnalyticsEvent(name: 'purchase', params: {...});
/// ```
class FirebaseAdapter extends AnalystAdapter {
  FirebaseAdapter(super.eventBus);

  final _uuid = const Uuid();

  @override
  String get id => 'firebase_adapter';

  @override
  String get displayName => 'Firebase Adapter';

  @override
  Future<void> onStart() async {
    log.info('FirebaseAdapter started.');
  }

  @override
  Future<void> onStop() async {}

  void trackCrash({
    required String message,
    StackTrace? stack,
    bool isFatal = false,
    Map<String, dynamic>? customKeys,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: isFatal ? EventSeverity.critical : EventSeverity.error,
      tags: const {'firebase', 'crashlytics'},
      payload: {
        'message': message,
        if (stack != null)
          'stackTrace': stack.toString().split('\n').take(15).join('\n'),
        'isFatal': isFatal,
        if (customKeys != null) 'customKeys': customKeys,
      },
    ));
  }

  void trackAnalyticsEvent({
    required String name,
    Map<String, dynamic>? params,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'firebase', 'analytics'},
      payload: {
        'event': name,
        if (params != null) 'params': params,
      },
    ));
  }

  void trackFirestoreOperation({
    required String operation,
    required String collection,
    String? documentId,
    bool success = true,
    String? errorMessage,
    int? durationMs,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: success ? EventSeverity.debug : EventSeverity.error,
      tags: const {'firebase', 'firestore'},
      payload: {
        'operation': operation,
        'collection': collection,
        if (documentId != null) 'documentId': documentId,
        'success': success,
        if (errorMessage != null) 'error': errorMessage,
        if (durationMs != null) 'durationMs': durationMs,
      },
    ));
  }

  void trackAuthStateChange({
    required String event,
    String? userId,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.info,
      tags: const {'firebase', 'auth'},
      payload: {
        'authEvent': event,
        if (userId != null) 'userId': userId,
      },
    ));
  }
}
