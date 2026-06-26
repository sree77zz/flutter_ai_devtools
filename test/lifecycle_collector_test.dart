import 'package:flutter/foundation.dart';
import 'package:flutter_ai_devtools/src/collectors/lifecycle_collector.dart';
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RuntimeStore store;
  late LifecycleCollector collector;

  setUp(() async {
    store = RuntimeStore();
    collector =
        LifecycleCollector(store: store, config: const CollectorConfig());
    await collector.start();
  });
  tearDown(() => collector.stop());

  void emit(String message) {
    FlutterError
        .onError!(FlutterErrorDetails(exception: FlutterError(message)));
  }

  test('detects setState after dispose', () {
    emit('setState() called after dispose(): _FooState#1234');
    final i = store.issues.single;
    expect(i.category, IssueCategory.lifecycle);
    expect(i.title.toLowerCase(), contains('dispose'));
  });

  test('detects use-after-dispose of a controller', () {
    emit('A TextEditingController was used after being disposed.');
    final i = store.issues.single;
    expect(i.category, IssueCategory.lifecycle);
  });

  test('ignores unrelated errors', () {
    emit('A RenderFlex overflowed by 3 pixels.');
    expect(store.issues, isEmpty);
  });
}
