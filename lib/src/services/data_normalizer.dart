import '../models/runtime_event.dart';
import '../logging/analyst_logger.dart';

/// Validates and normalizes [RuntimeEvent]s before they enter [RuntimeStore].
///
/// Strips null payload values, truncates oversized strings, and tags events
/// with standard metadata. Acts as a firewall so the store always holds
/// clean, bounded data.
class DataNormalizer {
  DataNormalizer({this.maxPayloadStringLength = 2048});

  final int maxPayloadStringLength;
  final _log = AnalystLogger.forName('DataNormalizer');

  RuntimeEvent normalize(RuntimeEvent event) {
    try {
      final cleanPayload = _cleanPayload(event.payload);
      return event.copyWith(payload: cleanPayload);
    } catch (e, st) {
      _log.warning('Failed to normalize event ${event.id}', e, st);
      return event;
    }
  }

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.length > maxPayloadStringLength) {
        result[entry.key] =
            '${value.substring(0, maxPayloadStringLength)}…[truncated]';
      } else if (value is Map) {
        result[entry.key] =
            _cleanPayload(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[entry.key] = _cleanList(value);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  List<dynamic> _cleanList(List<dynamic> list) => list.map((item) {
        if (item is Map) return _cleanPayload(Map<String, dynamic>.from(item));
        if (item is List) return _cleanList(item);
        if (item is String && item.length > maxPayloadStringLength) {
          return '${item.substring(0, maxPayloadStringLength)}…[truncated]';
        }
        return item;
      }).toList();
}
