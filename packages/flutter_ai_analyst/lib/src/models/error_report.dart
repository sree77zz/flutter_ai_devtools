import 'package:meta/meta.dart';

enum ErrorCategory { flutter, platform, dart, network, unknown }

@immutable
class ErrorReport {
  const ErrorReport({
    required this.id,
    required this.capturedAt,
    required this.category,
    required this.message,
    this.stackTrace,
    this.context,
    this.isFatal = false,
    this.occurrenceCount = 1,
  });

  final String id;
  final DateTime capturedAt;
  final ErrorCategory category;
  final String message;
  final String? stackTrace;
  final Map<String, dynamic>? context;
  final bool isFatal;
  final int occurrenceCount;

  ErrorReport incrementOccurrence() => ErrorReport(
        id: id,
        capturedAt: capturedAt,
        category: category,
        message: message,
        stackTrace: stackTrace,
        context: context,
        isFatal: isFatal,
        occurrenceCount: occurrenceCount + 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'capturedAt': capturedAt.toIso8601String(),
        'category': category.name,
        'message': message,
        if (stackTrace != null) 'stackTrace': stackTrace,
        if (context != null) 'context': context,
        'isFatal': isFatal,
        'occurrenceCount': occurrenceCount,
      };

  factory ErrorReport.fromJson(Map<String, dynamic> json) => ErrorReport(
        id: json['id'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        category:
            ErrorCategory.values.byName(json['category'] as String? ?? 'unknown'),
        message: json['message'] as String,
        stackTrace: json['stackTrace'] as String?,
        context: json['context'] as Map<String, dynamic>?,
        isFatal: json['isFatal'] as bool? ?? false,
        occurrenceCount: json['occurrenceCount'] as int? ?? 1,
      );
}
