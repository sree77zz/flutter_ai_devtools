import 'package:uuid/uuid.dart';

import '../models/runtime_event.dart';
import 'base_adapter.dart';

/// Tracks Dio HTTP requests and responses.
///
/// Attach [AnalystDioInterceptor] to your Dio instance:
///
/// ```dart
/// dio.interceptors.add(dioAdapter.interceptor);
/// ```
class DioAdapter extends AnalystAdapter {
  DioAdapter(super.eventBus);

  final _uuid = const Uuid();
  final _inFlight = <String, DateTime>{};

  late final AnalystDioInterceptor interceptor = AnalystDioInterceptor(this);

  @override
  String get id => 'dio_adapter';

  @override
  String get displayName => 'Dio Network Adapter';

  @override
  Future<void> onStart() async {
    log.info('DioAdapter started. Add interceptor to Dio instance.');
  }

  @override
  Future<void> onStop() async {
    _inFlight.clear();
  }

  void onRequest({
    required String requestId,
    required String method,
    required String uri,
    Map<String, dynamic>? headers,
  }) {
    _inFlight[requestId] = DateTime.now();
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'dio', 'request'},
      payload: {
        'requestId': requestId,
        'method': method,
        'uri': uri,
        if (headers != null) 'headers': headers,
      },
    ));
  }

  void onResponse({
    required String requestId,
    required int statusCode,
    required String uri,
    int? responseBodySize,
  }) {
    final startTime = _inFlight.remove(requestId);
    final durationMs = startTime == null
        ? null
        : DateTime.now().difference(startTime).inMilliseconds;

    final severity = statusCode >= 400 ? EventSeverity.warning : EventSeverity.debug;

    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: severity,
      tags: const {'dio', 'response'},
      payload: {
        'requestId': requestId,
        'statusCode': statusCode,
        'uri': uri,
        if (durationMs != null) 'durationMs': durationMs,
        if (responseBodySize != null) 'responseBodySize': responseBodySize,
      },
    ));
  }

  void onError({
    required String requestId,
    required String message,
    required String uri,
    int? statusCode,
  }) {
    _inFlight.remove(requestId);
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.error,
      tags: const {'dio', 'error'},
      payload: {
        'requestId': requestId,
        'error': message,
        'uri': uri,
        if (statusCode != null) 'statusCode': statusCode,
      },
    ));
  }
}

/// Standalone Dio-compatible interceptor.
///
/// If you have `dio` in your project, you can extend `Interceptor` and
/// delegate to [DioAdapter]. This class provides the method signatures you
/// need to wire up without creating a compile-time dependency on `dio`.
class AnalystDioInterceptor {
  AnalystDioInterceptor(this._adapter);

  final DioAdapter _adapter;
  final _uuid = const Uuid();

  /// Call from `Interceptor.onRequest`.
  void onRequest(String method, String uri, {Map<String, dynamic>? headers}) {
    _adapter.onRequest(
      requestId: _uuid.v4(),
      method: method,
      uri: uri,
      headers: headers,
    );
  }

  /// Call from `Interceptor.onResponse`.
  void onResponse(String requestId, int statusCode, String uri) {
    _adapter.onResponse(
      requestId: requestId,
      statusCode: statusCode,
      uri: uri,
    );
  }

  /// Call from `Interceptor.onError`.
  void onError(String requestId, String message, String uri, {int? statusCode}) {
    _adapter.onError(
      requestId: requestId,
      message: message,
      uri: uri,
      statusCode: statusCode,
    );
  }
}
