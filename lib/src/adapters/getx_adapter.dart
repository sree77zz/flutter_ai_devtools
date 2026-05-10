import 'package:uuid/uuid.dart';

import '../models/runtime_event.dart';
import 'base_adapter.dart';

/// Observes GetX controller states and navigation events.
///
/// Since `get` (GetX) is not a compile-time dependency, integration is
/// done by calling the tracking methods from your GetX workers / controllers:
///
/// ```dart
/// ever(myController.state, (s) => getxAdapter.trackStateChange(
///   controllerType: myController.runtimeType.toString(),
///   newState: s.runtimeType.toString(),
/// ));
/// ```
class GetXAdapter extends AnalystAdapter {
  GetXAdapter(super.eventBus);

  final _uuid = const Uuid();

  @override
  String get id => 'getx_adapter';

  @override
  String get displayName => 'GetX Adapter';

  @override
  Future<void> onStart() async {
    log.info('GetXAdapter started.');
  }

  @override
  Future<void> onStop() async {}

  void trackStateChange({
    required String controllerType,
    required String newState,
    Map<String, dynamic>? extra,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'getx', 'state_change'},
      payload: {
        'controller': controllerType,
        'newState': newState,
        if (extra != null) ...extra,
      },
    ));
  }

  void trackNavigation({
    required String toRoute,
    String? fromRoute,
    required String action,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.info,
      tags: const {'getx', 'navigation'},
      payload: {
        'to': toRoute,
        if (fromRoute != null) 'from': fromRoute,
        'action': action,
      },
    ));
  }

  void trackWorker({
    required String controllerType,
    required String workerType,
    required dynamic value,
  }) {
    publish(RuntimeEvent(
      id: _uuid.v4(),
      type: RuntimeEventType.adapterEvent,
      timestamp: DateTime.now(),
      source: id,
      severity: EventSeverity.debug,
      tags: const {'getx', 'worker'},
      payload: {
        'controller': controllerType,
        'workerType': workerType,
        'value': value?.toString() ?? 'null',
      },
    ));
  }
}
