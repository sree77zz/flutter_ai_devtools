import 'package:flutter/material.dart';
import 'package:flutter_ai_devtools/src/collectors/widget_collector.dart';
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('counts rebuilds silently without flooding stdout',
      (tester) async {
    final store = RuntimeStore();
    final collector =
        WidgetCollector(store: store, config: const CollectorConfig());
    await collector.start();

    var n = 0;
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return Text('n=$n', textDirection: TextDirection.ltr);
        },
      ),
    ));

    // The noisy print flag must NOT be enabled — it floods the live log.
    expect(debugPrintRebuildDirtyWidgets, isFalse);

    // Trigger rebuilds; they must be counted into the store.
    setOuter(() => n++);
    await tester.pump();
    setOuter(() => n++);
    await tester.pump();

    expect(store.widgetRebuildCounts, isNotEmpty,
        reason: 'rebuilds should be counted via debugOnRebuildDirtyWidget');

    await collector.stop(); // cancels the snapshot timer + restores the hook
  });
}
