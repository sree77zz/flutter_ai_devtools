import 'package:flutter/foundation.dart';
import 'package:flutter_ai_devtools/src/collectors/error_collector.dart';
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records an exception issue for a Flutter error', () async {
    final store = RuntimeStore();
    final c = ErrorCollector(store: store, config: const CollectorConfig());
    await c.start();
    addTearDown(() => c.stop());

    FlutterError.onError!(FlutterErrorDetails(
      exception: Exception('boom in build'),
      library: 'widgets library',
    ));

    final issues =
        store.issues.where((i) => i.category == IssueCategory.exception);
    expect(issues, isNotEmpty);
    expect(issues.first.source, IssueSource.detected);
    expect(issues.first.detail, contains('boom in build'));
  });
}
