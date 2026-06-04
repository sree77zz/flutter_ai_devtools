# Reliable Connection + Live Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the MCP bridge connect to a Flutter app reliably and terminal-free, and give Claude a live console (stdout/stderr/`developer.log`) it can read on demand.

**Architecture:** The `devtools_mcp` bridge becomes a resilient daemon: it never exits when the app is absent, retries connection on a loop, and auto-reconnects after hot restart. A bridge-side `LiveBuffer` continuously ingests the VM service's `Stdout`/`Stderr`/`Logging` streams into a cursor-indexed ring buffer. New MCP tools expose the log tail, connection status, hot reload, and memory info. The VM-service access is hidden behind a `VmSession` interface so the connection logic is unit-testable with a fake.

**Tech Stack:** Dart 3.3+, Flutter 3.41 (`flutter test` runner), `vm_service: ^14.2.4`, MCP JSON-RPC 2.0 over stdio.

---

## File Structure

**Create:**
- `lib/src/models/log_entry.dart` — `LogEntry`, `LogLevel`, `LogSource` (one normalized log record).
- `lib/src/bridge/live_buffer.dart` — `LiveBuffer` (ring buffer + monotonic seq cursor + filtered reads).
- `lib/src/bridge/log_normalizer.dart` — `normalizeVmEvent()` (vm_service `Event` → `LogEntry`).
- `lib/src/bridge/vm_session.dart` — `VmSession` interface + `VmServiceSession` real impl + `ConnectionStatus`.
- `lib/src/bridge/connection_manager.dart` — `ConnectionManager` (resilient connect/reconnect loop, transport-agnostic).
- `lib/src/setup/launch_config.dart` — pure functions to build/merge the debug config + `.mcp.json` (testable).
- `test/live_buffer_test.dart`, `test/log_normalizer_test.dart`, `test/connection_manager_test.dart`, `test/bridge_tools_test.dart`, `test/launch_config_test.dart`.

**Modify:**
- `lib/src/bridge/vm_bridge.dart` — build on `VmSession`/`ConnectionManager`, add daemon ingestion, status, hot reload, memory.
- `lib/src/mcp/tool_definitions.dart` — register the four new tools.
- `bin/devtools_mcp.dart` — daemon wiring (start, ingest, never-die).
- `bin/serve.dart` — share the same `LiveBuffer`.
- `bin/setup.dart` — call the testable `launch_config.dart` functions (idempotent merge).

---

## Task 1: `LogEntry` model

**Files:**
- Create: `lib/src/models/log_entry.dart`
- Test: `test/log_normalizer_test.dart` (model assertions live with normalizer tests in Task 3; this task is implementation-only and verified by Task 2/3 tests that consume it)

- [ ] **Step 1: Write the model**

Create `lib/src/models/log_entry.dart`:

```dart
import 'package:meta/meta.dart';

/// Severity of a captured log line. Ordered: debug < info < warning < error.
enum LogLevel { debug, info, warning, error }

/// Where a log line came from.
enum LogSource { stdout, stderr, developerLog, flutter }

/// One normalized log record in the live console buffer.
@immutable
class LogEntry {
  const LogEntry({
    required this.seq,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.loggerName,
    this.error,
    this.stackTrace,
  });

  /// Monotonic cursor assigned by [LiveBuffer]. Drafts use 0 until stored.
  final int seq;
  final DateTime timestamp;
  final LogLevel level;
  final LogSource source;
  final String message;
  final String? loggerName;
  final String? error;
  final String? stackTrace;

  LogEntry withSeq(int newSeq) => LogEntry(
        seq: newSeq,
        timestamp: timestamp,
        level: level,
        source: source,
        message: message,
        loggerName: loggerName,
        error: error,
        stackTrace: stackTrace,
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'ts': timestamp.toIso8601String(),
        'level': level.name,
        'source': source.name,
        'message': message,
        if (loggerName != null) 'logger': loggerName,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stack': stackTrace,
      };
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/src/models/log_entry.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/src/models/log_entry.dart
git commit -m "feat: add LogEntry model for live console"
```

---

## Task 2: `LiveBuffer` ring buffer with cursor

**Files:**
- Create: `lib/src/bridge/live_buffer.dart`
- Test: `test/live_buffer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/live_buffer_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/bridge/live_buffer.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry draft(String msg, {LogLevel level = LogLevel.info}) => LogEntry(
      seq: 0,
      timestamp: DateTime(2026),
      level: level,
      source: LogSource.stdout,
      message: msg,
    );

void main() {
  group('LiveBuffer', () {
    test('assigns monotonic seq and advances nextSeq', () {
      final buf = LiveBuffer();
      final a = buf.addLog(draft('a'));
      final b = buf.addLog(draft('b'));
      expect(a.seq, 0);
      expect(b.seq, 1);
      expect(buf.nextSeq, 2);
    });

    test('logsSince returns only entries at/after the cursor', () {
      final buf = LiveBuffer();
      buf.addLog(draft('a')); // seq 0
      buf.addLog(draft('b')); // seq 1
      buf.addLog(draft('c')); // seq 2
      final tail = buf.logsSince(1);
      expect(tail.map((e) => e.message), ['b', 'c']);
    });

    test('evicts oldest beyond maxLogs but keeps seq monotonic', () {
      final buf = LiveBuffer(maxLogs: 2);
      buf.addLog(draft('a')); // seq 0 (evicted)
      buf.addLog(draft('b')); // seq 1
      buf.addLog(draft('c')); // seq 2
      final all = buf.logsSince(0);
      expect(all.map((e) => e.seq), [1, 2]);
    });

    test('filters by minLevel and grep', () {
      final buf = LiveBuffer();
      buf.addLog(draft('hello info'));
      buf.addLog(draft('BAD thing', level: LogLevel.error));
      buf.addLog(draft('other info'));
      expect(buf.logsSince(0, minLevel: LogLevel.warning).map((e) => e.message),
          ['BAD thing']);
      expect(buf.logsSince(0, grep: 'info').map((e) => e.message),
          ['hello info', 'other info']);
    });

    test('limit returns the most recent N', () {
      final buf = LiveBuffer();
      for (var i = 0; i < 5; i++) {
        buf.addLog(draft('m$i'));
      }
      final tail = buf.logsSince(0, limit: 2);
      expect(tail.map((e) => e.message), ['m3', 'm4']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/live_buffer_test.dart`
Expected: FAIL — `live_buffer.dart` does not exist / `LiveBuffer` undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/src/bridge/live_buffer.dart`:

```dart
import 'dart:collection';
import '../models/log_entry.dart';

/// Bridge-side rolling buffer of normalized log lines with a monotonic cursor.
///
/// Continuously fed by the VM-service stream ingestion; read by the `get_logs`
/// tool via [logsSince]. Bounded so a chatty app cannot exhaust memory.
class LiveBuffer {
  LiveBuffer({this.maxLogs = 2000});

  final int maxLogs;
  final Queue<LogEntry> _logs = Queue<LogEntry>();
  int _seq = 0;

  /// Stores [draft] (its [LogEntry.seq] is overwritten) and returns the stored
  /// entry with its assigned seq.
  LogEntry addLog(LogEntry draft) {
    final entry = draft.withSeq(_seq++);
    _logs.addLast(entry);
    while (_logs.length > maxLogs) {
      _logs.removeFirst();
    }
    return entry;
  }

  /// The seq the next [addLog] will assign. Callers persist this as a cursor.
  int get nextSeq => _seq;

  /// Entries with `seq >= sinceSeq`, optionally filtered by level/substring,
  /// returning at most [limit] (the most recent ones when truncated).
  List<LogEntry> logsSince(
    int sinceSeq, {
    LogLevel? minLevel,
    String? grep,
    int limit = 200,
  }) {
    Iterable<LogEntry> it = _logs.where((e) => e.seq >= sinceSeq);
    if (minLevel != null) {
      it = it.where((e) => e.level.index >= minLevel.index);
    }
    if (grep != null && grep.isNotEmpty) {
      final needle = grep.toLowerCase();
      it = it.where((e) => e.message.toLowerCase().contains(needle));
    }
    final list = it.toList(growable: false);
    if (list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/live_buffer_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/bridge/live_buffer.dart test/live_buffer_test.dart
git commit -m "feat: add LiveBuffer ring buffer with seq cursor"
```

---

## Task 3: VM event → `LogEntry` normalizer

**Files:**
- Create: `lib/src/bridge/log_normalizer.dart`
- Test: `test/log_normalizer_test.dart`

Notes: `Stdout`/`Stderr` streams deliver `EventKind.kWriteEvent` with base64 `bytes`. The `Logging` stream delivers `EventKind.kLogging` with a `LogRecord` whose `message`/`loggerName`/`error`/`stackTrace` are `InstanceRef`s exposing `valueAsString`, and `level` is an int (`dart:logging` numeric levels: 900 = SEVERE, 1000 = SHOUT, 800 = WARNING).

- [ ] **Step 1: Write the failing test**

Create `test/log_normalizer_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_ai_devtools/src/bridge/log_normalizer.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  group('normalizeVmEvent', () {
    test('decodes a stdout WriteEvent', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('hello world\n')),
      );
      final entry = normalizeVmEvent(e, source: LogSource.stdout);
      expect(entry, isNotNull);
      expect(entry!.message, 'hello world');
      expect(entry.source, LogSource.stdout);
      expect(entry.level, LogLevel.info);
    });

    test('marks stderr WriteEvent as error level', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('boom')),
      );
      final entry = normalizeVmEvent(e, source: LogSource.stderr);
      expect(entry!.level, LogLevel.error);
      expect(entry.source, LogSource.stderr);
    });

    test('returns null for empty/whitespace write', () {
      final e = vm.Event(
        kind: vm.EventKind.kWriteEvent,
        bytes: base64.encode(utf8.encode('   \n')),
      );
      expect(normalizeVmEvent(e, source: LogSource.stdout), isNull);
    });

    test('maps a Logging record with level + logger name', () {
      final e = vm.Event(
        kind: vm.EventKind.kLogging,
        logRecord: vm.LogRecord(
          level: 900, // SEVERE
          message: vm.InstanceRef(kind: 'String', valueAsString: 'db failed'),
          loggerName: vm.InstanceRef(kind: 'String', valueAsString: 'AuthRepo'),
        ),
      );
      final entry = normalizeVmEvent(e, source: LogSource.developerLog);
      expect(entry!.message, 'db failed');
      expect(entry.loggerName, 'AuthRepo');
      expect(entry.level, LogLevel.error);
      expect(entry.source, LogSource.developerLog);
    });

    test('returns null for unrelated event kinds', () {
      final e = vm.Event(kind: vm.EventKind.kGC);
      expect(normalizeVmEvent(e, source: LogSource.stdout), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/log_normalizer_test.dart`
Expected: FAIL — `log_normalizer.dart` / `normalizeVmEvent` undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/src/bridge/log_normalizer.dart`:

```dart
import 'dart:convert';
import 'package:vm_service/vm_service.dart' as vm;
import '../models/log_entry.dart';

/// Converts a vm_service [vm.Event] into a [LogEntry] draft (seq = 0), or null
/// if the event carries no log payload. [source] disambiguates the originating
/// stream (Stdout vs Stderr vs Logging), which the event itself does not encode.
LogEntry? normalizeVmEvent(vm.Event e, {required LogSource source}) {
  switch (e.kind) {
    case vm.EventKind.kWriteEvent:
      final raw = e.bytes;
      if (raw == null) return null;
      final text = utf8.decode(base64.decode(raw)).trimRight();
      if (text.trim().isEmpty) return null;
      return LogEntry(
        seq: 0,
        timestamp: DateTime.now(),
        level: source == LogSource.stderr ? LogLevel.error : LogLevel.info,
        source: source,
        message: text,
      );
    case vm.EventKind.kLogging:
      final rec = e.logRecord;
      if (rec == null) return null;
      return LogEntry(
        seq: 0,
        timestamp: DateTime.now(),
        level: _levelFromInt(rec.level ?? 0),
        source: LogSource.developerLog,
        message: rec.message?.valueAsString ?? '',
        loggerName: rec.loggerName?.valueAsString,
        error: rec.error?.valueAsString,
        stackTrace: rec.stackTrace?.valueAsString,
      );
    default:
      return null;
  }
}

/// Maps `dart:logging` numeric levels onto [LogLevel].
/// (FINE=500, INFO=800, WARNING=900? — see note) We use the conventional
/// thresholds: >=1000 SHOUT→error, >=900 SEVERE→error, >=700 WARNING→warning,
/// >=500 INFO→info, else debug.
LogLevel _levelFromInt(int level) {
  if (level >= 900) return LogLevel.error;
  if (level >= 700) return LogLevel.warning;
  if (level >= 500) return LogLevel.info;
  return LogLevel.debug;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/log_normalizer_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/bridge/log_normalizer.dart test/log_normalizer_test.dart
git commit -m "feat: add vm_service Event to LogEntry normalizer"
```

---

## Task 4: `VmSession` interface + real implementation

**Files:**
- Create: `lib/src/bridge/vm_session.dart`
- Test: covered indirectly by Task 5 (`ConnectionManager`) with a fake; the real impl is a thin wrapper verified at integration time.

- [ ] **Step 1: Write the implementation**

Create `lib/src/bridge/vm_session.dart`:

```dart
import 'dart:io';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Snapshot of the bridge's link to the running app.
class ConnectionStatus {
  const ConnectionStatus({
    required this.connected,
    this.endpoint,
    this.isolateId,
    this.connectedAt,
    this.lastError,
  });

  final bool connected;
  final String? endpoint;
  final String? isolateId;
  final DateTime? connectedAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'connected': connected,
        if (endpoint != null) 'endpoint': endpoint,
        if (isolateId != null) 'isolateId': isolateId,
        if (connectedAt != null) 'connectedAt': connectedAt!.toIso8601String(),
        if (lastError != null) 'lastError': lastError,
      };
}

/// Minimal surface the bridge needs from the VM service. Abstracted so the
/// connection logic can be unit-tested with a fake (no live VM required).
abstract class VmSession {
  String get endpoint;
  String get mainIsolateId;

  Stream<vm.Event> get stdout;
  Stream<vm.Event> get stderr;
  Stream<vm.Event> get logging;

  /// Fires when the main isolate exits / is restarted (hot restart).
  Stream<void> get disconnected;

  Future<Map<String, dynamic>> callExtension(
      String method, Map<String, String> args);
  Future<void> reloadSources();
  Future<Map<String, dynamic>> memoryUsage();
  Future<void> dispose();
}

/// Connects to a real VM service and exposes it as a [VmSession].
/// Returns null on any failure (no isolates, refused connection, etc.).
typedef VmConnector = Future<VmSession?> Function(String wsUri);

Future<VmSession?> connectVmService(String wsUri) async {
  try {
    final service = await vmServiceConnectUri(wsUri);
    final vmObj = await service.getVM();
    final isolates = vmObj.isolates;
    if (isolates == null || isolates.isEmpty) {
      await service.dispose();
      return null;
    }
    final isolateId = isolates.first.id!;
    await service.streamListen(vm.EventStreams.kStdout);
    await service.streamListen(vm.EventStreams.kStderr);
    await service.streamListen(vm.EventStreams.kLogging);
    await service.streamListen(vm.EventStreams.kIsolate);
    return VmServiceSession(service, wsUri, isolateId);
  } catch (e) {
    stderr.writeln('[VmSession] connect failed: $e');
    return null;
  }
}

class VmServiceSession implements VmSession {
  VmServiceSession(this._service, this.endpoint, this.mainIsolateId);

  final vm.VmService _service;
  @override
  final String endpoint;
  @override
  final String mainIsolateId;

  @override
  Stream<vm.Event> get stdout => _service.onStdoutEvent;
  @override
  Stream<vm.Event> get stderr => _service.onStderrEvent;
  @override
  Stream<vm.Event> get logging => _service.onLoggingEvent;

  @override
  Stream<void> get disconnected => _service.onIsolateEvent
      .where((e) => e.kind == vm.EventKind.kIsolateExit)
      .map((_) {});

  @override
  Future<Map<String, dynamic>> callExtension(
      String method, Map<String, String> args) async {
    final r = await _service.callServiceExtension(
      method,
      isolateId: mainIsolateId,
      args: args,
    );
    return r.json ?? {};
  }

  @override
  Future<void> reloadSources() async {
    await _service.reloadSources(mainIsolateId);
  }

  @override
  Future<Map<String, dynamic>> memoryUsage() async {
    final m = await _service.getMemoryUsage(mainIsolateId);
    return {
      'heapUsage': m.heapUsage,
      'heapCapacity': m.heapCapacity,
      'externalUsage': m.externalUsage,
    };
  }

  @override
  Future<void> dispose() async {
    await _service.dispose();
  }
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/src/bridge/vm_session.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/src/bridge/vm_session.dart
git commit -m "feat: add VmSession interface + real vm_service implementation"
```

---

## Task 5: `ConnectionManager` resilient connect/reconnect loop

**Files:**
- Create: `lib/src/bridge/connection_manager.dart`
- Test: `test/connection_manager_test.dart`

The manager owns the never-die retry loop and reconnect-on-disconnect behavior, injected with a `VmConnector` and the candidate URI resolver so tests drive it with a fake.

- [ ] **Step 1: Write the failing test**

Create `test/connection_manager_test.dart`:

```dart
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
      expect(sessions.length, greaterThanOrEqualTo(2)); // reconnected
      await mgr.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/connection_manager_test.dart`
Expected: FAIL — `connection_manager.dart` / `ConnectionManager` undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/src/bridge/connection_manager.dart`:

```dart
import 'dart:async';
import 'vm_session.dart';

/// Resolves the ordered list of candidate WebSocket URIs to try.
typedef CandidateResolver = Future<List<String>> Function();

/// Owns the never-die connect loop and reconnect-on-disconnect behavior.
///
/// [start] kicks off a background loop that keeps trying [candidates] through
/// [connector] until one yields a [VmSession]. When that session signals
/// [VmSession.disconnected] (app exit / hot restart), the loop resumes.
class ConnectionManager {
  ConnectionManager({
    required CandidateResolver candidates,
    required VmConnector connector,
    this.retryDelay = const Duration(seconds: 1),
  })  : _candidates = candidates,
        _connector = connector;

  final CandidateResolver _candidates;
  final VmConnector _connector;
  final Duration retryDelay;

  VmSession? _session;
  ConnectionStatus _status = const ConnectionStatus(connected: false);
  bool _running = false;
  StreamSubscription<void>? _disconnectSub;
  Completer<void>? _loopDone;

  VmSession? get session => _session;
  ConnectionStatus get status => _status;

  void start() {
    if (_running) return;
    _running = true;
    _loopDone = Completer<void>();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_running) {
      if (_session == null) {
        await _tryConnectOnce();
      }
      if (_session == null) {
        await Future<void>.delayed(retryDelay);
      } else {
        // Connected: wait until a disconnect signal clears the session.
        await Future<void>.delayed(retryDelay);
      }
    }
    _loopDone?.complete();
  }

  Future<void> _tryConnectOnce() async {
    String? lastError;
    for (final uri in await _candidates()) {
      final wsUri = _toWs(uri);
      try {
        final s = await _connector(wsUri);
        if (s != null) {
          _session = s;
          _status = ConnectionStatus(
            connected: true,
            endpoint: s.endpoint,
            isolateId: s.mainIsolateId,
            connectedAt: DateTime.now(),
          );
          _disconnectSub = s.disconnected.listen((_) => _onDisconnect());
          return;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }
    _status = ConnectionStatus(connected: false, lastError: lastError);
  }

  void _onDisconnect() {
    _disconnectSub?.cancel();
    _disconnectSub = null;
    final old = _session;
    _session = null;
    _status = const ConnectionStatus(connected: false, lastError: 'app disconnected');
    unawaited(old?.dispose());
  }

  Future<void> dispose() async {
    _running = false;
    await _disconnectSub?.cancel();
    await _session?.dispose();
    _session = null;
    await _loopDone?.future;
  }

  static String _toWs(String uri) {
    final normalized = uri.endsWith('/') ? uri : '$uri/';
    final wsBase = normalized
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return wsBase.endsWith('ws') ? wsBase : '${wsBase}ws';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/connection_manager_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/bridge/connection_manager.dart test/connection_manager_test.dart
git commit -m "feat: add resilient ConnectionManager with auto-reconnect"
```

---

## Task 6: Rebuild `VmBridge` on the new foundation

**Files:**
- Modify: `lib/src/bridge/vm_bridge.dart` (full rewrite)
- Test: `test/bridge_tools_test.dart` (added in Task 7; this task is verified by `flutter analyze` + existing callers compiling)

The new `VmBridge` composes `ConnectionManager` + `LiveBuffer`, ingests log streams, and exposes the operations the tools need. It keeps the existing candidate-URI discovery (pinned port → lockfile → env).

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `lib/src/bridge/vm_bridge.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart' as vm;
import '../lockfile.dart';
import '../models/log_entry.dart';
import 'connection_manager.dart';
import 'live_buffer.dart';
import 'log_normalizer.dart';
import 'vm_session.dart';

/// Resilient bridge between the MCP server and a running Flutter app's VM service.
///
/// Never throws on a missing app: [start] launches a background connect loop,
/// and [liveBuffer] fills from the app's stdout/stderr/logging streams whenever
/// a session is live. Tool handlers call [callTool]/[hotReload]/[memoryInfo]/
/// [status]; when disconnected these return a clear, actionable result.
class VmBridge {
  VmBridge({
    LiveBuffer? liveBuffer,
    VmConnector connector = connectVmService,
    Duration retryDelay = const Duration(seconds: 1),
  })  : liveBuffer = liveBuffer ?? LiveBuffer(),
        _manager = ConnectionManager(
          candidates: _candidateUris,
          connector: connector,
          retryDelay: retryDelay,
        );

  final LiveBuffer liveBuffer;
  final ConnectionManager _manager;
  final _logSubs = <StreamSubscription<vm.Event>>[];
  VmSession? _ingestingSession;
  Timer? _ingestionTimer;

  /// Begins the resilient connect loop and (re)attaches log ingestion as
  /// sessions come and go.
  void start() {
    _manager.start();
    _ingestionTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _syncIngestion());
  }

  void _syncIngestion() {
    final s = _manager.session;
    if (identical(s, _ingestingSession)) return;
    for (final sub in _logSubs) {
      sub.cancel();
    }
    _logSubs.clear();
    _ingestingSession = s;
    if (s == null) return;
    _logSubs.add(s.stdout.listen((e) => _ingest(e, LogSource.stdout)));
    _logSubs.add(s.stderr.listen((e) => _ingest(e, LogSource.stderr)));
    _logSubs.add(s.logging.listen((e) => _ingest(e, LogSource.developerLog)));
  }

  void _ingest(vm.Event event, LogSource source) {
    final entry = normalizeVmEvent(event, source: source);
    if (entry != null) liveBuffer.addLog(entry);
  }

  ConnectionStatus get status => _manager.status;
  bool get connected => _manager.status.connected;

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> args) async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      return await s.callExtension(
        'ext.flutter_ai_devtools.$name',
        args.map((k, v) => MapEntry(k, v.toString())),
      );
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> hotReload() async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      await s.reloadSources();
      return {'reloaded': true};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> memoryInfo() async {
    final s = _manager.session;
    if (s == null) return _notConnected();
    try {
      return await s.memoryUsage();
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> dispose() async {
    _ingestionTimer?.cancel();
    _ingestionTimer = null;
    for (final sub in _logSubs) {
      await sub.cancel();
    }
    _logSubs.clear();
    await _manager.dispose();
  }

  static Map<String, dynamic> _notConnected() => {
        'error': 'Flutter app not connected. Launch the "Flutter + AI DevTools" '
            'run configuration (or: flutter run --vm-service-port=8181 '
            '--disable-service-auth-codes).',
      };

  /// Ordered discovery: pinned port → desktop lockfile → env override.
  static Future<List<String>> _candidateUris() async {
    final candidates = <String>['http://127.0.0.1:8181/'];
    final lockData = await readLockfile();
    if (lockData != null) {
      final lockUri = lockData['vmServiceUri'] as String?;
      final lockPid = lockData['pid'] as int?;
      if (lockUri != null && (lockPid == null || isProcessAlive(lockPid))) {
        candidates.add(lockUri);
      }
    }
    final envUri = Platform.environment['DART_VM_SERVICE_URI'];
    if (envUri != null) candidates.add(envUri);
    return candidates;
  }
}
```

Note: `_logSubs` is typed `List<StreamSubscription<vm.Event>>` and `_ingest(vm.Event …)` consumes the `Stream<vm.Event>` that `VmSession` exposes; `normalizeVmEvent` (Task 3) already accepts `vm.Event`, so no signature change is needed there.

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/src/bridge/vm_bridge.dart`
Expected: "No issues found!" The old `bin/devtools_mcp.dart` and `bin/serve.dart` still reference the previous `VmBridge.connect()` API and will show analysis errors until Tasks 8 and 10 rewrite them — that is expected and resolved there.

- [ ] **Step 3: Commit**

```bash
git add lib/src/bridge/vm_bridge.dart
git commit -m "feat: rebuild VmBridge as resilient daemon with log ingestion"
```

---

## Task 7: `get_logs` tool + register on dispatcher

**Files:**
- Modify: `lib/src/mcp/tool_definitions.dart`
- Test: `test/bridge_tools_test.dart`

The four new tools read from the bridge/LiveBuffer directly (in-process), not via a service extension. `registerBridgeTools` gains access to the `VmBridge` (which owns the `LiveBuffer`).

- [ ] **Step 1: Write the failing test**

Create `test/bridge_tools_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/bridge/live_buffer.dart';
import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/models/log_entry.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bridge tools', () {
    late LiveBuffer buffer;
    late VmBridge bridge;
    late ToolDispatcher d;

    setUp(() {
      buffer = LiveBuffer();
      // connector that never connects keeps the bridge offline for the test.
      bridge = VmBridge(liveBuffer: buffer, connector: (_) async => null);
      d = ToolDispatcher();
      registerBridgeTools(d, bridge);
    });

    tearDown(() => bridge.dispose());

    test('get_logs returns tail entries and nextSeq', () async {
      buffer.addLog(LogEntry(
        seq: 0,
        timestamp: DateTime(2026),
        level: LogLevel.info,
        source: LogSource.stdout,
        message: 'first',
      ));
      buffer.addLog(LogEntry(
        seq: 0,
        timestamp: DateTime(2026),
        level: LogLevel.error,
        source: LogSource.stderr,
        message: 'second',
      ));

      final res = await d.dispatch('get_logs', {'sinceSeq': 0});
      final logs = res['logs'] as List;
      expect(logs, hasLength(2));
      expect((logs.first as Map)['message'], 'first');
      expect(res['nextSeq'], 2);
    });

    test('get_logs honors sinceSeq cursor and level filter', () async {
      buffer.addLog(LogEntry(
          seq: 0, timestamp: DateTime(2026), level: LogLevel.info,
          source: LogSource.stdout, message: 'a'));
      buffer.addLog(LogEntry(
          seq: 0, timestamp: DateTime(2026), level: LogLevel.error,
          source: LogSource.stderr, message: 'b'));

      final res = await d.dispatch('get_logs', {'sinceSeq': 1, 'level': 'error'});
      final logs = res['logs'] as List;
      expect(logs, hasLength(1));
      expect((logs.first as Map)['message'], 'b');
    });

    test('get_connection_status reports disconnected when offline', () async {
      final res = await d.dispatch('get_connection_status', {});
      expect(res['connected'], isFalse);
    });

    test('hot_reload returns actionable error when offline', () async {
      final res = await d.dispatch('hot_reload', {});
      expect(res['error'], contains('not connected'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/bridge_tools_test.dart`
Expected: FAIL — `registerBridgeTools` arity/handlers don't match (no `get_logs`).

- [ ] **Step 3: Rewrite `registerBridgeTools`**

Replace the entire contents of `lib/src/mcp/tool_definitions.dart`:

```dart
import '../bridge/vm_bridge.dart';
import '../models/log_entry.dart';
import 'tool_dispatcher.dart';

/// Registers every MCP tool against [d]. App-state tools proxy to the running
/// app via service extensions ([bridge.callTool]); live/console/connection
/// tools read directly from the bridge and its [VmBridge.liveBuffer].
void registerBridgeTools(ToolDispatcher d, VmBridge bridge) {
  // ── App-state tools (service-extension proxies) ──────────────────────────
  d.register('get_runtime_summary', (a) => bridge.callTool('get_runtime_summary', a),
      description: 'Complete runtime health snapshot');
  d.register('get_widget_tree', (a) => bridge.callTool('get_widget_tree', a),
      description: 'Current widget tree snapshot',
      schema: {
        'type': 'object',
        'properties': {'maxDepth': {'type': 'integer', 'default': 10}},
      });
  d.register('get_current_route', (a) => bridge.callTool('get_current_route', a),
      description: 'Active navigation route');
  d.register('get_recent_errors', (a) => bridge.callTool('get_recent_errors', a),
      description: 'Recent error history',
      schema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'default': 20},
          'fatalOnly': {'type': 'boolean', 'default': false},
        },
      });
  d.register('get_render_issues', (a) => bridge.callTool('get_render_issues', a),
      description: 'Rendering problems (overflow, constraints)');
  d.register('get_frame_stats', (a) => bridge.callTool('get_frame_stats', a),
      description: 'Frame timing metrics (FPS, jank)');
  d.register('analyze_performance', (a) => bridge.callTool('analyze_performance', a),
      description: 'Performance analysis pipeline');
  d.register('analyze_rebuilds', (a) => bridge.callTool('analyze_rebuilds', a),
      description: 'Most frequently rebuilding widgets');

  // ── Live / console / connection tools (bridge-direct) ────────────────────
  d.register('get_logs', (a) async {
    final sinceSeq = _asInt(a['sinceSeq']) ?? 0;
    final limit = _asInt(a['limit']) ?? 200;
    final grep = a['grep'] as String?;
    final level = _levelFromName(a['level'] as String?);
    final entries = bridge.liveBuffer
        .logsSince(sinceSeq, minLevel: level, grep: grep, limit: limit);
    return {
      'logs': entries.map((e) => e.toJson()).toList(),
      'nextSeq': bridge.liveBuffer.nextSeq,
    };
  },
      description:
          'Live console tail (stdout/stderr/developer.log) since a cursor',
      schema: {
        'type': 'object',
        'properties': {
          'sinceSeq': {'type': 'integer', 'default': 0},
          'level': {'type': 'string', 'enum': ['debug', 'info', 'warning', 'error']},
          'grep': {'type': 'string'},
          'limit': {'type': 'integer', 'default': 200},
        },
      });

  d.register('get_connection_status', (a) async => bridge.status.toJson(),
      description: 'Whether the bridge is connected to the running app');

  d.register('hot_reload', (a) => bridge.hotReload(),
      description: 'Trigger a hot reload of the running app');

  d.register('get_memory_info', (a) => bridge.memoryInfo(),
      description: 'Current heap usage of the running app');
}

int? _asInt(Object? v) =>
    v is int ? v : (v is String ? int.tryParse(v) : null);

LogLevel? _levelFromName(String? name) {
  if (name == null) return null;
  for (final l in LogLevel.values) {
    if (l.name == name) return l;
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/bridge_tools_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/mcp/tool_definitions.dart test/bridge_tools_test.dart
git commit -m "feat: add get_logs, get_connection_status, hot_reload, get_memory_info tools"
```

---

## Task 8: Wire the daemon into `bin/devtools_mcp.dart`

**Files:**
- Modify: `bin/devtools_mcp.dart` (full rewrite of `main` + dispatch)
- Test: manual smoke (no automated test — entry-point process); covered by `flutter analyze`.

The bridge now starts as a daemon and never blocks startup on the app being present. `tools/call` no longer gates on a synchronous connect.

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `bin/devtools_mcp.dart`:

```dart
// bin/devtools_mcp.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

Future<void> main(List<String> args) async {
  final bridge = VmBridge();
  bridge.start(); // resilient connect loop; never blocks, never dies.

  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  await _serveStdio(dispatcher);
  await bridge.dispose();
}

Future<void> _serveStdio(ToolDispatcher dispatcher) async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _write(_error(null, -32700, 'Parse error'));
      continue;
    }
    if (!req.containsKey('id')) continue; // notification

    final id = req['id'];
    final method = req['method'] as String?;
    final params = req['params'] as Map<String, dynamic>? ?? {};
    try {
      final result = await _dispatch(method, params, dispatcher);
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});
    } catch (e) {
      _write(_error(id, -32603, e.toString()));
    }
  }
}

Future<Object?> _dispatch(
  String? method,
  Map<String, dynamic> params,
  ToolDispatcher dispatcher,
) async {
  switch (method) {
    case 'initialize':
      return {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {'name': 'flutter_ai_devtools', 'version': '0.1.0'},
      };
    case 'tools/list':
      return {'tools': dispatcher.toolManifests};
    case 'tools/call':
      final name = params['name'] as String?;
      if (name == null) throw const FormatException('"name" is required');
      final toolArgs = params['arguments'] as Map<String, dynamic>? ?? {};
      final content = await dispatcher.dispatch(name, toolArgs);
      return ToolDispatcher.mcpResult(content);
    case 'ping':
      return {'pong': true};
    default:
      throw FormatException('Method not found: $method');
  }
}

void _write(Map<String, dynamic> msg) => stdout.writeln(jsonEncode(msg));

Map<String, dynamic> _error(dynamic id, int code, String message) => {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
```

Note: a `tools/call` while disconnected no longer errors at the protocol level — the tool handler returns `{'error': '…not connected…'}` wrapped as a normal MCP result, so Claude reads an actionable message instead of a JSON-RPC failure.

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze bin/devtools_mcp.dart`
Expected: "No issues found!"

- [ ] **Step 3: Smoke-test the protocol handshake (no app required)**

Run:
```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | dart run flutter_ai_devtools:devtools_mcp
```
Expected: two JSON lines on stdout — the `initialize` result, then a `tools/list` result whose `tools` array includes `get_logs`, `get_connection_status`, `hot_reload`, and `get_memory_info`. The process keeps running (Ctrl+C to exit) because the bridge daemon stays alive.

- [ ] **Step 4: Commit**

```bash
git add bin/devtools_mcp.dart
git commit -m "feat: run devtools_mcp as resilient daemon (no connect-or-die)"
```

---

## Task 9: Idempotent `setup` debug config (testable core)

**Files:**
- Create: `lib/src/setup/launch_config.dart`
- Test: `test/launch_config_test.dart`
- Modify: `bin/setup.dart`

Extract the JSON-merge logic into pure functions so the "don't clobber the user's existing configs" behavior is unit-tested.

- [ ] **Step 1: Write the failing test**

Create `test/launch_config_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_ai_devtools/src/setup/launch_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeLaunchConfig', () {
    test('adds the AI DevTools config to an empty launch.json', () {
      final out = mergeLaunchConfig(null);
      final configs = out['configurations'] as List;
      expect(configs, hasLength(1));
      expect((configs.first as Map)['name'], 'Flutter + AI DevTools');
      expect((configs.first as Map)['args'],
          containsAll(['--vm-service-port=8181', '--disable-service-auth-codes']));
    });

    test('preserves existing user configurations', () {
      final existing = jsonEncode({
        'version': '0.2.0',
        'configurations': [
          {'name': 'My App', 'request': 'launch', 'type': 'dart'},
        ],
      });
      final out = mergeLaunchConfig(existing);
      final names =
          (out['configurations'] as List).map((c) => (c as Map)['name']).toList();
      expect(names, containsAll(['My App', 'Flutter + AI DevTools']));
    });

    test('is idempotent — does not duplicate on re-run', () {
      final first = jsonEncode(mergeLaunchConfig(null));
      final second = mergeLaunchConfig(first);
      final aiConfigs = (second['configurations'] as List)
          .where((c) => (c as Map)['name'] == 'Flutter + AI DevTools');
      expect(aiConfigs, hasLength(1));
    });
  });

  group('mcpJsonContent', () {
    test('produces a stdio server entry', () {
      final json = jsonDecode(mcpJsonContent()) as Map<String, dynamic>;
      final server = (json['mcpServers'] as Map)['flutter_ai_devtools'] as Map;
      expect(server['type'], 'stdio');
      expect(server['args'], contains('flutter_ai_devtools:devtools_mcp'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/launch_config_test.dart`
Expected: FAIL — `launch_config.dart` undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/src/setup/launch_config.dart`:

```dart
import 'dart:convert';

const _kConfigName = 'Flutter + AI DevTools';

/// Returns a launch.json map that contains the AI DevTools debug configuration,
/// merged into [existingJson] (the current file contents, or null if absent).
/// Existing configurations are preserved; the AI config is added once
/// (idempotent — re-running does not duplicate it).
Map<String, dynamic> mergeLaunchConfig(String? existingJson) {
  Map<String, dynamic> doc;
  if (existingJson == null || existingJson.trim().isEmpty) {
    doc = {'version': '0.2.0', 'configurations': <dynamic>[]};
  } else {
    doc = jsonDecode(existingJson) as Map<String, dynamic>;
    doc['version'] ??= '0.2.0';
    doc['configurations'] ??= <dynamic>[];
  }
  final configs = (doc['configurations'] as List).cast<dynamic>();
  final already =
      configs.any((c) => c is Map && c['name'] == _kConfigName);
  if (!already) {
    configs.add({
      'name': _kConfigName,
      'request': 'launch',
      'type': 'dart',
      'args': [
        '--vm-service-port=8181',
        '--host-vmservice-port=8181',
        '--disable-service-auth-codes',
      ],
    });
  }
  doc['configurations'] = configs;
  return doc;
}

/// The `.mcp.json` contents wiring Claude Code to the stdio bridge.
String mcpJsonContent() => '${const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'flutter_ai_devtools': {
          'type': 'stdio',
          'command': 'dart',
          'args': ['run', 'flutter_ai_devtools:devtools_mcp'],
        },
      },
    })}\n';

/// Pretty-prints a launch.json document for writing to disk.
String renderLaunchJson(Map<String, dynamic> doc) =>
    '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/launch_config_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Rewrite `bin/setup.dart` to use the merge functions**

Replace the entire contents of `bin/setup.dart`:

```dart
// bin/setup.dart
import 'dart:io';

import 'package:flutter_ai_devtools/src/setup/launch_config.dart';

Future<void> main(List<String> args) async {
  await _writeMcpJson();
  await _writeVsCodeLaunch();
  _printInstructions();
}

Future<void> _writeMcpJson() async {
  final file = File('.mcp.json');
  await file.writeAsString(mcpJsonContent());
  stdout.writeln('✓ Wrote .mcp.json (stdio transport — no second terminal needed)');
}

Future<void> _writeVsCodeLaunch() async {
  await Directory('.vscode').create(recursive: true);
  final file = File('.vscode/launch.json');
  final existing = await file.exists() ? await file.readAsString() : null;
  final merged = mergeLaunchConfig(existing);
  await file.writeAsString(renderLaunchJson(merged));
  stdout.writeln('✓ Merged "Flutter + AI DevTools" into .vscode/launch.json');
}

void _printInstructions() {
  stdout.writeln('''

Setup complete!

1. Add to your main():
     await FlutterAiDevtools.start();

2. In VSCode's Run panel, pick "Flutter + AI DevTools" and press Run.
   (This pins the VM-service port so the bridge connects deterministically.)

3. In Claude Code, run /mcp — flutter_ai_devtools shows connected.
   Claude Code starts the bridge automatically; no second terminal needed.
''');
}
```

- [ ] **Step 6: Verify analyze + run setup once**

Run: `flutter analyze bin/setup.dart lib/src/setup/launch_config.dart`
Expected: "No issues found!"

Run: `dart run flutter_ai_devtools:setup`
Expected: prints the two ✓ lines; `.vscode/launch.json` now contains a `Flutter + AI DevTools` configuration; re-running does not duplicate it.

- [ ] **Step 7: Commit**

```bash
git add lib/src/setup/launch_config.dart test/launch_config_test.dart bin/setup.dart .mcp.json .vscode/launch.json
git commit -m "feat: idempotent setup that merges the AI DevTools debug config"
```

---

## Task 10: Share the `LiveBuffer` in the SSE `serve` entry point

**Files:**
- Modify: `bin/serve.dart`
- Test: existing `test/sse_server_test.dart` must still pass.

`serve` should use the same resilient daemon so SSE clients get identical behavior.

- [ ] **Step 1: Rewrite `bin/serve.dart`**

Replace the entire contents of `bin/serve.dart`:

```dart
// bin/serve.dart
import 'dart:io';

import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/sse_server.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';

const _defaultMcpPort = 8765;

Future<void> main(List<String> args) async {
  final mcpPort = int.tryParse(_argValue(args, '--port') ?? '') ?? _defaultMcpPort;

  final bridge = VmBridge();
  bridge.start(); // resilient; connects whenever the app appears.

  final dispatcher = ToolDispatcher();
  registerBridgeTools(dispatcher, bridge);

  final server = SseServer(dispatcher: dispatcher);
  final port = await server.bind(mcpPort);
  stderr.writeln('✓ MCP SSE server listening at http://localhost:$port/sse');
  stderr.writeln('  (The bridge connects to your app automatically when it starts.)');

  ProcessSignal.sigint.watch().listen((_) async {
    await bridge.dispose();
    await server.stop();
    exit(0);
  });

  await stdin.drain<void>();
  await bridge.dispose();
  await server.stop();
}

String? _argValue(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  final prefix = '$flag=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}
```

- [ ] **Step 2: Verify analyze + SSE tests still pass**

Run: `flutter analyze bin/serve.dart`
Expected: "No issues found!"

Run: `flutter test test/sse_server_test.dart`
Expected: PASS (all existing SSE tests).

- [ ] **Step 3: Commit**

```bash
git add bin/serve.dart
git commit -m "refactor: serve uses the resilient VmBridge daemon"
```

---

## Task 11: Full suite green + manual end-to-end check

**Files:** none (verification task)

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: PASS — all new tests (`live_buffer`, `log_normalizer`, `connection_manager`, `bridge_tools`, `launch_config`) plus existing (`flutter_ai_devtools_test`, `service_extensions_test`, `sse_server_test`).

- [ ] **Step 2: Analyze the whole package**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Manual end-to-end (real app)**

1. In `example/`, ensure `main()` calls `await FlutterAiDevtools.start();` (already present).
2. Launch the example via the **"Flutter + AI DevTools"** config (run `dart run flutter_ai_devtools:setup` inside `example/` first if needed).
3. From the repo root, drive the bridge manually and confirm live logs flow:
```bash
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_connection_status","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_logs","arguments":{"sinceSeq":0}}}' \
  | dart run flutter_ai_devtools:devtools_mcp
```
Expected: `get_connection_status` → `connected: true`; `get_logs` → an array containing the app's startup console output. Press a button in the example app, re-run `get_logs` with the returned `nextSeq`, and confirm only new lines appear.

- [ ] **Step 4: Commit any final fixups**

```bash
git add -A
git commit -m "test: full suite green for connection + live console" --allow-empty
```

---

## Self-Review Checklist (completed by plan author)

- **Spec coverage:** Section 1 (connection/launch) → Tasks 4–6, 8, 9; live console (Section 2/3.2) → Tasks 1–3, 6, 7; new tools (Section 5: `get_logs`, `get_connection_status`, `hot_reload`, `get_memory_info`) → Task 7; `setup` (Section 1.3) → Task 9; SSE parity (Section 6) → Task 10. (Structured issues, `reportError`, routing, `get_issues`, README/`cli` cleanup, the enhanced `get_runtime_summary` → **Plans 2 & 3**, intentionally out of this plan.)
- **Type consistency:** `LiveBuffer.addLog`/`logsSince`/`nextSeq`, `LogEntry.withSeq`/`toJson`, `VmSession` members, `ConnectionManager.session`/`status`/`start`/`dispose`, `VmBridge.start`/`status`/`callTool`/`hotReload`/`memoryInfo`/`liveBuffer`, `registerBridgeTools(d, bridge)` — all consistent across tasks.
- **Placeholder scan:** none.

---

## Out of scope (deferred to later plans)

- Structured `Issue` model, app-side reporter, `reportError`/`reportIssue`, enhanced render + lifecycle collectors, observer-free routing, bridge-side text detectors, `get_issues`, enhanced `get_runtime_summary` → **Plan 2**.
- Deleting `cli/`, README reconciliation, example refresh → **Plan 3**.
