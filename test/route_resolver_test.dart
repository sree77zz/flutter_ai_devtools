import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_devtools/src/routing/route_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves the current named route without an observer',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      initialRoute: '/',
      routes: {
        '/': (_) => const Scaffold(body: Text('home')),
        '/detail': (_) => const Scaffold(body: Text('detail')),
      },
    ));
    await tester.pumpAndSettle();

    expect(resolveCurrentRouteName(), '/');

    unawaited(key.currentState!.pushNamed('/detail'));
    await tester.pumpAndSettle();

    expect(resolveCurrentRouteName(), '/detail');
  });

  testWidgets('falls back to the route type for an unnamed route',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Text('home')),
    ));
    await tester.pumpAndSettle();

    // Anonymous route with no settings.name.
    unawaited(key.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('x'))),
    ));
    await tester.pumpAndSettle();

    final name = resolveCurrentRouteName();
    expect(name, isNotNull);
    expect(name, contains('MaterialPageRoute'));
  });

  testWidgets('returns null when there is no routed content', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('bare'),
    ));
    await tester.pumpAndSettle();
    expect(resolveCurrentRouteName(), isNull);
  });
}
