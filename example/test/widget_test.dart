import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_devtools_example/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('flutter_ai_devtools'), findsOneWidget);
  });
}