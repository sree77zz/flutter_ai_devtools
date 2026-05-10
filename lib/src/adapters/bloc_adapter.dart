import 'package:uuid/uuid.dart';

import '../models/runtime_event.dart';
import 'base_adapter.dart';

/// Observes Bloc/Cubit state transitions.
///
/// To use, pass [AnalystBlocObserver] to [Bloc.observer] in your main():
///
/// ```dart
/// Bloc.observer = blocAdapter.observer;
/// ```
///
/// Requires `bloc` package in the host app. This adapter does NOT depend on
/// bloc at compile time â€” it uses a duck-typed observer pattern so the plugin
/// remains framework-agnostic.
class BlocAdapter extends AnalystAdapter {
  BlocAdapter(super.eventBus);

  final _uuid = const Uuid();
  late final AnalystBlocObserver observer = AnalystBlocObserver(this);

  @override
  String get id => 'bloc_adapter';

  @override
  String get displayName => 'Bloc/Cubit Adapter';

  @override
  Future<void> onStart() async {
    log.info(
      'BlocAdapter started. Set Bloc.observer = blocAdapter.observer in your app.',
    );
  }

  @override
  Future<void> onStop() async {}

  void onStateChange({
    required String blocType,
    required String stateName,
    required Map<String, dynamic>? stateJson,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      tags: const {'bloc', 'state_change'},
      payload: {
        'blocType': blocType,
        'newState': stateName,
        if (stateJson != null) 'stateData': stateJson,
      },
    ));
  }

  void onBlocError({
    required String blocType,
    required Object error,
    required StackTrace stack,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.error,
      tags: const {'bloc', 'error'},
      payload: {
        'blocType': blocType,
        'error': error.toString(),
        'stackTrace': stack.toString().split('\n').take(10).join('\n'),
      },
    ));
  }

  void onEventAdded({required String blocType, required String eventName}) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'bloc', 'event'},
      payload: {'blocType': blocType, 'event': eventName},
    ));
  }
}

/// Duck-typed Bloc observer. Extend this in your app and call the adapter
/// methods, or use [AnalystBlocObserver] directly if you use `package:bloc`.
///
/// If using `package:bloc`:
/// ```dart
/// class _AnalystBlocObserver extends BlocObserver {
///   final BlocAdapter _adapter;
///   _AnalystBlocObserver(this._adapter);
///
///   @override
///   void onChange(BlocBase bloc, Change change) {
///     super.onChange(bloc, change);
///     _adapter.onStateChange(
///       blocType: bloc.runtimeType.toString(),
///       stateName: change.nextState.runtimeType.toString(),
///       stateJson: null,
///     );
///   }
/// }
/// ```
///
/// A standalone observer is provided for apps not using `package:bloc`:
class AnalystBlocObserver {
  AnalystBlocObserver(this._adapter);

  final BlocAdapter _adapter;

  void onEvent(Object bloc, Object event) {
    _adapter.onEventAdded(
      blocType: bloc.runtimeType.toString(),
      eventName: event.runtimeType.toString(),
    );
  }

  void onChange(Object bloc, Object currentState, Object nextState) {
    _adapter.onStateChange(
      blocType: bloc.runtimeType.toString(),
      stateName: nextState.runtimeType.toString(),
      stateJson: null,
    );
  }

  void onError(Object bloc, Object error, StackTrace stack) {
    _adapter.onBlocError(
      blocType: bloc.runtimeType.toString(),
      error: error,
      stack: stack,
    );
  }
}
