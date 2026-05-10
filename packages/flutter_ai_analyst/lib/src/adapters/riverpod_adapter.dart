import 'package:uuid/uuid.dart';

import '../models/runtime_event.dart';
import 'base_adapter.dart';

/// Tracks Riverpod provider state changes.
///
/// Because `flutter_riverpod` is not a compile-time dependency, integration
/// is achieved by calling [trackProviderUpdate] from a ProviderObserver you
/// implement in your app:
///
/// ```dart
/// class _AnalystProviderObserver extends ProviderObserver {
///   final RiverpodAdapter adapter;
///   const _AnalystProviderObserver(this.adapter);
///
///   @override
///   void didUpdateProvider(
///     ProviderBase provider,
///     Object? previousValue,
///     Object? newValue,
///     ProviderContainer container,
///   ) {
///     adapter.trackProviderUpdate(
///       providerName: provider.name ?? provider.runtimeType.toString(),
///       previousType: previousValue?.runtimeType.toString(),
///       newType: newValue?.runtimeType.toString(),
///     );
///   }
/// }
/// ```
class RiverpodAdapter extends AnalystAdapter {
  RiverpodAdapter(super.eventBus);

  final _uuid = const Uuid();

  @override
  String get id => 'riverpod_adapter';

  @override
  String get displayName => 'Riverpod Adapter';

  @override
  Future<void> onStart() async {
    log.info(
      'RiverpodAdapter started. Register a ProviderObserver that calls '
      'trackProviderUpdate.',
    );
  }

  @override
  Future<void> onStop() async {}

  void trackProviderUpdate({
    required String providerName,
    String? previousType,
    String? newType,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'riverpod', 'provider_update'},
      payload: {
        'provider': providerName,
        if (previousType != null) 'previousType': previousType,
        if (newType != null) 'newType': newType,
      },
    ));
  }

  void trackProviderDisposed(String providerName) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'riverpod', 'provider_disposed'},
      payload: {'provider': providerName},
    ));
  }

  void trackProviderError({
    required String providerName,
    required Object error,
    required StackTrace stack,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.error,
      tags: const {'riverpod', 'provider_error'},
      payload: {
        'provider': providerName,
        'error': error.toString(),
        'stackTrace': stack.toString().split('\n').take(10).join('\n'),
      },
    ));
  }
}
