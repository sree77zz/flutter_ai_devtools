import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Canonical event categories emitted by collectors.
enum RuntimeEventType {
  widgetTreeSnapshot,
  widgetRebuilt,
  navigationPush,
  navigationPop,
  navigationReplace,
  frameRendered,
  frameJanked,
  renderIssueDetected,
  flutterError,
  platformError,
  lifecycleChanged,
  adapterEvent,
}

/// Severity level attached to every [RuntimeEvent].
enum EventSeverity { debug, info, warning, error, critical }

/// Immutable, normalized event envelope produced by every collector and adapter.
///
/// All collector output is reduced to this type before being stored in
/// [RuntimeStore] or published on [EventBus], giving the analyzer engine and
/// MCP tools a single schema to reason about.
@immutable
class RuntimeEvent extends Equatable {
  const RuntimeEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.source,
    required this.payload,
    this.severity = EventSeverity.info,
    this.tags = const {},
  });

  final String id;
  final RuntimeEventType type;
  final DateTime timestamp;

  /// Logical source identifier, e.g. 'widget_collector', 'bloc_adapter'.
  final String source;

  /// Arbitrary structured payload. Kept as Map for schema flexibility.
  final Map<String, dynamic> payload;
  final EventSeverity severity;
  final Set<String> tags;

  factory RuntimeEvent.fromJson(Map<String, dynamic> json) => RuntimeEvent(
        id: json['id'] as String,
        type: RuntimeEventType.values.byName(json['type'] as String),
        timestamp: DateTime.parse(json['timestamp'] as String),
        source: json['source'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        severity: EventSeverity.values.byName(
          json['severity'] as String? ?? 'info',
        ),
        tags: Set<String>.from(json['tags'] as List? ?? []),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'payload': payload,
        'severity': severity.name,
        'tags': tags.toList(),
      };

  RuntimeEvent copyWith({
    String? id,
    RuntimeEventType? type,
    DateTime? timestamp,
    String? source,
    Map<String, dynamic>? payload,
    EventSeverity? severity,
    Set<String>? tags,
  }) =>
      RuntimeEvent(
        id: id ?? this.id,
        type: type ?? this.type,
        timestamp: timestamp ?? this.timestamp,
        source: source ?? this.source,
        payload: payload ?? this.payload,
        severity: severity ?? this.severity,
        tags: tags ?? this.tags,
      );

  @override
  List<Object?> get props => [id, type, timestamp, source, severity];

  @override
  String toString() =>
      'RuntimeEvent(id: $id, type: ${type.name}, source: $source, '
      'severity: ${severity.name}, ts: ${timestamp.toIso8601String()})';
}
