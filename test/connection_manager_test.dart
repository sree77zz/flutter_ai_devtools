import 'dart:async';
import 'package:flutter_ai_devtools/src/bridge/connection_manager.dart';
import 'package:flutter_ai_devtools/src/bridge/vm_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

class FakeSession implements VmSession {
  FakeSession();
  final _disconnect = StreamController<void>.broadcast();
  bool disposed = false;
  void killApp() => _disconnect.add(null);

  @override
  String get endpoint => 'ws://fake/ws';
  @override
  String get mainIsolateId => 'iso-1';
  @override
  Stream<vm.Event> get stdout => const Stream.empty();
  @override
  Stream<vm.Event> get stderr => const Stream.empty();
  @override
  Stream<vm.Event> get logging => const Stream.empty();
  @override
  Stream<void> get disconnected => _disconnect.stream;
  @override
  Future<Map<String, dynamic>> callExtension(String m, Map<String, String> a) async => {};
  @override
  Future<void> reloadSources() async {}
  @override
  Future<Map<String, dynamic>> memoryUsage() async => {};
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('ConnectionManager', () {
    test('stays disconnected and keeps retrying while app absent', () async {
      var attempts = 0;
      final mgr = ConnectionManager(
        candidates: () async => ['ws://x/ws'],
        connector: (_) async {
          attempts++;
          return null; // app not running
        },
        retryDelay: const Duration(milliseconds: 5),
      );
      mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(mgr.status.connected, isFalse);
      expect(attempts, greaterThan(1));
      await mgr.dispose();
      final countAfterDispose = attempts;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, equals(countAfterDispose));
    });

    test('connects when the app appears', () async {
      FakeSession? created;
      var ready = false;
      final mgr = ConnectionManager(
        candidates: () async => ['ws://x/ws'],
        connector: (_) async => ready ? (created = FakeSession()) : null,
        retryDelay: const Duration(milliseconds: 5),
      );
      mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mgr.status.connected, isFalse);
      ready = true;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(mgr.status.connected, isTrue);
      expect(mgr.session, same(created));
      await mgr.dispose();
    });

    test('auto-reconnects after the session disconnects', () async {
      final sessions = <FakeSession>[];
      final mgr = ConnectionManager(
        candidates: () async => ['ws://x/ws'],
        connector: (_) async {
          final s = FakeSession();
          sessions.add(s);
          return s;
        },
        retryDelay: const Duration(milliseconds: 5),
      );
      mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mgr.status.connected, isTrue);
      sessions.first.killApp(); // hot restart / app exit
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(mgr.status.connected, isTrue);
      expect(sessions.first.disposed, isTrue,
          reason: 'old session must be disposed after disconnect');
      expect(sessions.length, greaterThanOrEqualTo(2)); // reconnected
      await mgr.dispose();
    });
  });
}
