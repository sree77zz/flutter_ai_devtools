import 'package:flutter/foundation.dart';
import 'package:flutter_ai_devtools/src/collectors/error_collector.dart';
import 'package:flutter_ai_devtools/src/collectors/render_collector.dart';
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overflow yields only a layoutRender issue when renders enabled', () async {
    final store = RuntimeStore();
    const cfg = CollectorConfig();
    final err = ErrorCollector(store: store, config: cfg);
    final render = RenderCollector(store: store, config: cfg);
    await err.start();
    await render.start(); // render chains over error
    addTearDown(() async { await render.stop(); await err.stop(); });

    FlutterError.onError!(FlutterErrorDetails(
      exception: FlutterError('A RenderFlex overflowed by 12 pixels.'),
      library: 'rendering library',
    ));

    final cats = store.issues.map((i) => i.category).toList();
    expect(cats, contains(IssueCategory.layoutRender));
    expect(cats, isNot(contains(IssueCategory.exception)),
        reason: 'no generic exception duplicate when render collector handles it');
  });

  test('overflow still yields an exception issue when renders disabled', () async {
    final store = RuntimeStore();
    const cfg = CollectorConfig(renders: false, lifecycle: false);
    final err = ErrorCollector(store: store, config: cfg);
    await err.start();
    addTearDown(() => err.stop());

    FlutterError.onError!(FlutterErrorDetails(
      exception: FlutterError('A RenderFlex overflowed by 12 pixels.'),
      library: 'rendering library',
    ));

    final cats = store.issues.map((i) => i.category).toList();
    expect(cats, contains(IssueCategory.exception),
        reason: 'with no specialized collector, the error must not be dropped');
  });
}
