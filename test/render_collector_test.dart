import 'package:flutter/foundation.dart';
import 'package:flutter_ai_devtools/src/collectors/render_collector.dart';
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RuntimeStore store;
  late RenderCollector collector;

  setUp(() async {
    store = RuntimeStore();
    collector = RenderCollector(store: store, config: const CollectorConfig());
    await collector.start();
  });
  tearDown(() => collector.stop());

  void emit(String message) {
    FlutterError.onError!(FlutterErrorDetails(
      exception: FlutterError(message),
      library: 'rendering library',
    ));
  }

  test('classifies a RenderFlex overflow as a layoutRender issue', () {
    emit('A RenderFlex overflowed by 42 pixels on the right.');
    final i = store.issues.single;
    expect(i.category, IssueCategory.layoutRender);
    expect(i.severity, IssueSeverity.error);
    expect(i.title.toLowerCase(), contains('overflow'));
  });

  test('classifies unbounded constraints', () {
    emit('BoxConstraints forces an infinite width.');
    final i = store.issues.single;
    expect(i.category, IssueCategory.layoutRender);
    expect(i.title.toLowerCase(), contains('constraint'));
  });

  test('ignores unrelated errors', () {
    emit('Some unrelated assertion.');
    expect(store.issues, isEmpty);
  });

  test('repeated identical overflow deduplicates', () {
    emit('A RenderFlex overflowed by 42 pixels on the right.');
    emit('A RenderFlex overflowed by 42 pixels on the right.');
    expect(store.issues, hasLength(1));
    expect(store.issues.single.count, 2);
  });
}
