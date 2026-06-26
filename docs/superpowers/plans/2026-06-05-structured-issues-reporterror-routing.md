# Structured Issues + reportError + Observer-Free Routing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude a single, deduplicated `get_issues` view of everything wrong in a running app — thrown exceptions, layout/render problems, lifecycle violations, and developer-reported errors — plus a `reportError()`/`reportIssue()` API for handled errors, and route tracking that needs no observer.

**Architecture:** All issue detection and aggregation lives **app-side** in `RuntimeStore` (it already holds the structured context). Collectors and the public `reportError`/`reportIssue` API funnel `Issue` objects into `store.addIssue`, which deduplicates by signature, counts recurrences, and escalates severity. A new `get_issues` **service extension** exposes the aggregated list; the bridge proxies it like the other app-state tools, so every call is always-fresh on pull with **no new bridge state**. Route detection reads the live element tree (observer-free); the `NavigatorObserver` becomes optional enrichment.

**Tech Stack:** Dart 3.3+, Flutter 3.41 (`flutter test`), MCP JSON-RPC 2.0. Builds on Plan 1's bridge (already merged).

**Out of scope (deferred):** bridge-side log *text-scraping* fallback for issues never routed through `FlutterError` (the service-extension path already surfaces every detected/reported issue); the `hot_reload` ReloadReport enhancement; the event-driven ingestion-sync refactor.

---

## File Structure

**Create:**
- `lib/src/models/issue.dart` — `Issue`, `IssueCategory`, `IssueSeverity`, plus `issueSignature()` helper.
- `lib/src/collectors/lifecycle_collector.dart` — `LifecycleCollector`.
- `lib/src/routing/route_resolver.dart` — `resolveCurrentRouteName()` (observer-free).
- Tests: `test/issue_test.dart`, `test/issue_store_test.dart`, `test/report_error_test.dart`, `test/render_collector_test.dart`, `test/lifecycle_collector_test.dart`, `test/route_resolver_test.dart`, `test/get_issues_extension_test.dart`.

**Modify:**
- `lib/src/store/runtime_store.dart` — add `addIssue`, `issues`, `maxIssues`, recurrence escalation; `clear()` resets issues.
- `lib/src/config.dart` — add `maxIssues`, `lifecycle`, `recurrenceThreshold`.
- `lib/src/collectors/render_collector.dart` — emit `Issue` (richer classification) into the store.
- `lib/src/collectors/error_collector.dart` — also emit `Issue` (category exception).
- `lib/src/devtools.dart` — wire `LifecycleCollector`; add `reportError`/`reportIssue`.
- `lib/src/service_extensions.dart` — add `get_issues`; route `get_current_route` through the resolver; enrich `get_runtime_summary`.
- `lib/src/mcp/tool_definitions.dart` — register the `get_issues` proxy tool.
- `lib/flutter_ai_devtools.dart` — export `issue.dart`.

---

## Task 1: `Issue` model

**Files:**
- Create: `lib/src/models/issue.dart`
- Test: `test/issue_test.dart`

- [ ] **Step 1: Write the failing test** — create `test/issue_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue', () {
    test('toJson emits the documented shape', () {
      final i = Issue(
        signature: 'sig-1',
        category: IssueCategory.layoutRender,
        severity: IssueSeverity.error,
        source: IssueSource.detected,
        title: 'Overflow',
        detail: 'A RenderFlex overflowed by 42 px',
        firstSeen: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 1, 1),
        count: 1,
        evidence: const {'widget': 'Row'},
      );
      final j = i.toJson();
      expect(j['signature'], 'sig-1');
      expect(j['category'], 'layoutRender');
      expect(j['severity'], 'error');
      expect(j['source'], 'detected');
      expect(j['count'], 1);
      expect(j['evidence'], {'widget': 'Row'});
      expect(j['domainCategory'], isNull);
    });

    test('copyWith overrides only the given fields', () {
      final i = Issue(
        signature: 's',
        category: IssueCategory.exception,
        severity: IssueSeverity.warning,
        source: IssueSource.detected,
        title: 't',
        detail: 'd',
        firstSeen: DateTime(2026),
        lastSeen: DateTime(2026),
        count: 1,
        evidence: const {},
      );
      final u = i.copyWith(count: 5, severity: IssueSeverity.critical);
      expect(u.count, 5);
      expect(u.severity, IssueSeverity.critical);
      expect(u.signature, 's'); // unchanged
      expect(u.firstSeen, DateTime(2026)); // unchanged
    });

    test('issueSignature is stable and normalizes whitespace', () {
      final a = issueSignature(IssueCategory.exception, 'Null   check  failed');
      final b = issueSignature(IssueCategory.exception, 'Null check failed');
      expect(a, b);
      final c = issueSignature(IssueCategory.lifecycle, 'Null check failed');
      expect(a, isNot(c)); // category participates in the signature
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/issue_test.dart`
Expected: FAIL — `issue.dart` / `Issue` undefined.

- [ ] **Step 3: Write the implementation** — create `lib/src/models/issue.dart`:

```dart
import 'package:meta/meta.dart';

/// What kind of problem this is.
enum IssueCategory { exception, layoutRender, lifecycle, reported }

/// Ordered: info < warning < error < critical.
enum IssueSeverity { info, warning, error, critical }

/// Where the issue came from.
enum IssueSource { detected, reported }

/// A single deduplicated, aggregated problem in the running app.
@immutable
class Issue {
  const Issue({
    required this.signature,
    required this.category,
    required this.severity,
    required this.source,
    required this.title,
    required this.detail,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.evidence,
    this.domainCategory,
  });

  /// Stable dedup key (see [issueSignature]).
  final String signature;
  final IssueCategory category;
  final IssueSeverity severity;
  final IssueSource source;
  final String title;
  final String detail;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int count;
  final Map<String, dynamic> evidence;

  /// Free-form domain tag from reportError/reportIssue (e.g. 'api'); null for
  /// detected issues.
  final String? domainCategory;

  Issue copyWith({
    IssueSeverity? severity,
    DateTime? lastSeen,
    int? count,
  }) =>
      Issue(
        signature: signature,
        category: category,
        severity: severity ?? this.severity,
        source: source,
        title: title,
        detail: detail,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        count: count ?? this.count,
        evidence: evidence,
        domainCategory: domainCategory,
      );

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'category': category.name,
        'severity': severity.name,
        'source': source.name,
        'title': title,
        'detail': detail,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'count': count,
        'evidence': evidence,
        if (domainCategory != null) 'domainCategory': domainCategory,
      };
}

/// Computes a stable signature from a [category] and a free-text [key]
/// (whitespace-normalized, length-bounded), so repeated occurrences of the same
/// problem collapse onto one [Issue].
String issueSignature(IssueCategory category, String key) {
  final norm = key.trim().replaceAll(RegExp(r'\s+'), ' ');
  final bounded = norm.length > 120 ? norm.substring(0, 120) : norm;
  final hash = '${category.name}|$bounded'.hashCode.toUnsigned(32).toRadixString(16);
  return '${category.name}_$hash';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/issue_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/issue.dart test/issue_test.dart
git commit -m "feat: add Issue model with signature + copyWith"
```

---

## Task 2: `RuntimeStore` issue aggregation + config

**Files:**
- Modify: `lib/src/store/runtime_store.dart`
- Modify: `lib/src/config.dart`
- Modify: `lib/src/devtools.dart` (forward new limits to the store)
- Test: `test/issue_store_test.dart`

- [ ] **Step 1: Write the failing test** — create `test/issue_store_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/config.dart';
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

Issue mk(String sig, {IssueSeverity sev = IssueSeverity.warning, int n = 1}) =>
    Issue(
      signature: sig,
      category: IssueCategory.exception,
      severity: sev,
      source: IssueSource.detected,
      title: 't',
      detail: 'd',
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026, 1, 1, 0, 0, n),
      count: 1,
      evidence: const {},
    );

void main() {
  group('RuntimeStore.addIssue', () {
    test('stores a new issue', () {
      final s = RuntimeStore();
      s.addIssue(mk('a'));
      expect(s.issues, hasLength(1));
      expect(s.issues.first.count, 1);
    });

    test('deduplicates by signature and increments count + lastSeen', () {
      final s = RuntimeStore();
      s.addIssue(mk('a', n: 1));
      s.addIssue(mk('a', n: 2));
      s.addIssue(mk('a', n: 3));
      expect(s.issues, hasLength(1));
      expect(s.issues.first.count, 3);
      expect(s.issues.first.lastSeen, DateTime(2026, 1, 1, 0, 0, 3));
    });

    test('keeps the highest severity seen', () {
      final s = RuntimeStore();
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      s.addIssue(mk('a', sev: IssueSeverity.error));
      s.addIssue(mk('a', sev: IssueSeverity.info));
      expect(s.issues.first.severity, IssueSeverity.error);
    });

    test('escalates to critical once count reaches recurrenceThreshold', () {
      final s = RuntimeStore(recurrenceThreshold: 3);
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      s.addIssue(mk('a', sev: IssueSeverity.warning));
      expect(s.issues.first.severity, IssueSeverity.warning);
      s.addIssue(mk('a', sev: IssueSeverity.warning)); // count == 3
      expect(s.issues.first.severity, IssueSeverity.critical);
    });

    test('bounds issue count, evicting the oldest', () {
      final s = RuntimeStore(maxIssues: 2);
      s.addIssue(mk('a'));
      s.addIssue(mk('b'));
      s.addIssue(mk('c'));
      expect(s.issues.map((i) => i.signature), ['b', 'c']);
    });

    test('clear() removes issues', () {
      final s = RuntimeStore();
      s.addIssue(mk('a'));
      s.clear();
      expect(s.issues, isEmpty);
    });
  });

  test('CollectorConfig exposes maxIssues / lifecycle / recurrenceThreshold', () {
    const c = CollectorConfig();
    expect(c.maxIssues, greaterThan(0));
    expect(c.lifecycle, isTrue);
    expect(c.recurrenceThreshold, greaterThan(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/issue_store_test.dart`
Expected: FAIL — `addIssue`/`issues`/`recurrenceThreshold`/`maxIssues`/`lifecycle` undefined.

- [ ] **Step 3a: Extend `CollectorConfig`** — in `lib/src/config.dart`, add three fields to the constructor and class. Replace the constructor parameter list and field declarations so the class reads:

```dart
class CollectorConfig {
  const CollectorConfig({
    this.widgets = true,
    this.frames = true,
    this.errors = true,
    this.routes = true,
    this.renders = true,
    this.lifecycle = true,
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
    this.maxIssues = 200,
    this.recurrenceThreshold = 5,
    this.widgetSnapshotMaxDepth = 20,
    this.widgetSnapshotMaxNodes = 500,
  });

  final bool widgets;
  final bool frames;
  final bool errors;
  final bool routes;
  final bool renders;
  final bool lifecycle;
  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;
  final int maxIssues;
  final int recurrenceThreshold;
  final int widgetSnapshotMaxDepth;
  final int widgetSnapshotMaxNodes;
}
```

(Leave `FlutterAiDevtoolsException` in the file unchanged.)

- [ ] **Step 3b: Add issue aggregation to `RuntimeStore`** — in `lib/src/store/runtime_store.dart`:

Add the import at the top (with the other model imports):
```dart
import '../models/issue.dart';
```

Add to the constructor (new named params) and fields. Change the constructor to:
```dart
  RuntimeStore({
    this.maxErrors = 100,
    this.maxFrames = 300,
    this.maxRenderIssues = 200,
    this.maxIssues = 200,
    this.recurrenceThreshold = 5,
  });

  final int maxErrors;
  final int maxFrames;
  final int maxRenderIssues;
  final int maxIssues;
  final int recurrenceThreshold;
```

Add fields alongside the other private collections:
```dart
  final _issues = <String, Issue>{};
```

Add the write method (near the other `add*` methods):
```dart
  /// Adds or merges [incoming] by signature: repeats increment the count, push
  /// lastSeen forward, keep the highest severity seen, and escalate to critical
  /// once the count reaches [recurrenceThreshold].
  void addIssue(Issue incoming) {
    final existing = _issues[incoming.signature];
    if (existing != null) {
      final count = existing.count + 1;
      var severity =
          existing.severity.index >= incoming.severity.index
              ? existing.severity
              : incoming.severity;
      if (count >= recurrenceThreshold) severity = IssueSeverity.critical;
      _issues[incoming.signature] = existing.copyWith(
        count: count,
        lastSeen: incoming.lastSeen,
        severity: severity,
      );
      return;
    }
    while (_issues.length >= maxIssues && _issues.isNotEmpty) {
      _issues.remove(_issues.keys.first);
    }
    _issues[incoming.signature] = incoming;
  }
```

Add the read getter (near the other getters):
```dart
  List<Issue> get issues => List.unmodifiable(_issues.values);
```

Add to `clear()`:
```dart
    _issues.clear();
```

- [ ] **Step 3c: Pass the new config into the store** — in `lib/src/devtools.dart`'s `start()`, the `RuntimeStore(...)` construction must forward the new limits. Change it to:
```dart
    _store = RuntimeStore(
      maxErrors: collectors.maxErrors,
      maxFrames: collectors.maxFrames,
      maxRenderIssues: collectors.maxRenderIssues,
      maxIssues: collectors.maxIssues,
      recurrenceThreshold: collectors.recurrenceThreshold,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/issue_store_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/store/runtime_store.dart lib/src/config.dart test/issue_store_test.dart
git commit -m "feat: aggregate issues in RuntimeStore with dedup + escalation"
```

---

## Task 3: `reportError` / `reportIssue` public API

**Files:**
- Modify: `lib/src/devtools.dart`
- Modify: `lib/flutter_ai_devtools.dart` (export the Issue model)
- Test: `test/report_error_test.dart`

- [ ] **Step 1: Write the failing test** — create `test/report_error_test.dart`:

```dart
import 'package:flutter_ai_devtools/flutter_ai_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reportError/reportIssue no-op before start()', () {
    // Not started: must not throw, and there is no store to inspect.
    expect(() => FlutterAiDevtools.reportError(Exception('x'), StackTrace.current),
        returnsNormally);
    expect(() => FlutterAiDevtools.reportIssue('x'), returnsNormally);
  });

  // Disable collectors so start() installs no timers/FlutterError hooks — we
  // only need _store set so reportError is live.
  const noCollectors = CollectorConfig(
      widgets: false, frames: false, errors: false,
      routes: false, renders: false, lifecycle: false);

  test('reportError records a reported issue with category + context', () async {
    await FlutterAiDevtools.start(collectors: noCollectors);
    addTearDown(FlutterAiDevtools.stop);

    FlutterAiDevtools.reportError(
      Exception('charge failed'),
      StackTrace.current,
      category: 'api',
      context: {'orderId': 42},
    );

    final issues = FlutterAiDevtools.store!.issues;
    expect(issues, hasLength(1));
    final i = issues.first;
    expect(i.source, IssueSource.reported);
    expect(i.category, IssueCategory.reported);
    expect(i.domainCategory, 'api');
    expect(i.evidence['orderId'], 42);
    expect(i.detail, contains('charge failed'));
  });

  test('reportIssue records a reported issue with given severity', () async {
    await FlutterAiDevtools.start(collectors: noCollectors);
    addTearDown(FlutterAiDevtools.stop);

    FlutterAiDevtools.reportIssue('Cart total mismatch',
        severity: IssueSeverity.error, context: {'expected': 1200});

    final i = FlutterAiDevtools.store!.issues.single;
    expect(i.title, 'Cart total mismatch');
    expect(i.severity, IssueSeverity.error);
    expect(i.evidence['expected'], 1200);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/report_error_test.dart`
Expected: FAIL — `reportError`/`reportIssue` undefined; `IssueSource`/`IssueCategory` not exported.

- [ ] **Step 3a: Export the Issue model** — in `lib/flutter_ai_devtools.dart`, add to the model exports:
```dart
export 'src/models/issue.dart';
```

- [ ] **Step 3b: Add the API** — in `lib/src/devtools.dart`:

Add the import (with the other src imports):
```dart
import 'models/issue.dart';
```

Add these two static methods to the `FlutterAiDevtools` class (after `stop()`):

```dart
  /// Reports a handled error so it surfaces in `get_issues`. No-op when devtools
  /// is not started, so calls are safe to leave in production code paths.
  static void reportError(
    Object error,
    StackTrace stackTrace, {
    String? category,
    Map<String, dynamic>? context,
  }) {
    final store = _store;
    if (store == null) return;
    final message = error.toString();
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.reported, '${category ?? ''}|$message'),
      category: IssueCategory.reported,
      severity: IssueSeverity.error,
      source: IssueSource.reported,
      title: message.length > 80 ? '${message.substring(0, 80)}…' : message,
      detail: '$message\n$stackTrace',
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {...?context},
      domainCategory: category,
    ));
  }

  /// Reports a non-exception problem (validation failure, invariant break) so it
  /// surfaces in `get_issues`. No-op when devtools is not started.
  static void reportIssue(
    String title, {
    IssueSeverity severity = IssueSeverity.warning,
    String? category,
    Map<String, dynamic>? context,
  }) {
    final store = _store;
    if (store == null) return;
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.reported, '${category ?? ''}|$title'),
      category: IssueCategory.reported,
      severity: severity,
      source: IssueSource.reported,
      title: title,
      detail: title,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {...?context},
      domainCategory: category,
    ));
  }
```

- [ ] **Step 3c: Make extension registration register-once** — VM service extensions cannot be registered twice in one isolate (the second `dev.registerExtension` throws), which breaks repeated `start()` calls (e.g. across tests). Guard it in `lib/src/devtools.dart`'s `_registerExtensions`.

Add a static field to the `FlutterAiDevtools` class (near the other statics):
```dart
  static bool _extensionsRegistered = false;
```

Change `_registerExtensions` so registration happens at most once:
```dart
  static Future<void> _registerExtensions(RuntimeStore store) async {
    if (kIsWeb) return;
    if (!_extensionsRegistered) {
      registerServiceExtensions(store);
      _extensionsRegistered = true;
    }
    // Write VM URI to lockfile so the bridge can discover it on desktop.
    try {
      final info = await dev.Service.getInfo();
      await writeLockfile(vmServiceUri: info.serverUri?.toString());
    } catch (_) {
      // VM service not available (release mode or unsupported platform).
    }
  }
```

(Note: the registered closures capture the first store; re-`start()` in the *same* isolate keeps querying that store. This is fine for tests — which read `FlutterAiDevtools.store` directly — and for real use, where `start()` runs once per app launch and hot restart spawns a fresh isolate.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/report_error_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/devtools.dart lib/flutter_ai_devtools.dart test/report_error_test.dart
git commit -m "feat: add reportError/reportIssue public API"
```

---

## Task 4: Enhanced `RenderCollector` → `Issue`

**Files:**
- Modify: `lib/src/collectors/render_collector.dart`
- Test: `test/render_collector_test.dart`

Context: `RenderCollector` already intercepts `FlutterError.onError` and classifies overflow/unbounded/intrinsic into the legacy `RenderIssue`. This task ADDS emitting a unified `Issue` (category `layoutRender`) into the store, with broader classification, while keeping the existing `RenderIssue` behavior intact.

- [ ] **Step 1: Write the failing test** — create `test/render_collector_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/render_collector_test.dart`
Expected: FAIL — collector does not yet call `store.addIssue`.

- [ ] **Step 3: Update `RenderCollector`** — replace the entire contents of `lib/src/collectors/render_collector.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/issue.dart';
import '../models/render_issue.dart';
import 'base_collector.dart';

/// Detects render-tree problems by intercepting [FlutterError.onError] and
/// pattern-matching against known layout error strings. Emits both the legacy
/// [RenderIssue] (kept for back-compat) and a unified [Issue] (category
/// [IssueCategory.layoutRender]) into the store.
class RenderCollector extends BaseCollector {
  RenderCollector({required super.store, required super.config});

  final _uuid = const Uuid();
  FlutterExceptionHandler? _prevHandler;

  @override
  String get id => 'render_collector';

  @override
  Future<void> onStart() async {
    _prevHandler = FlutterError.onError;
    FlutterError.onError = _intercept;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _prevHandler;
  }

  void _intercept(FlutterErrorDetails details) {
    _prevHandler?.call(details);
    _classify(details.exceptionAsString(), details);
  }

  void _classify(String msg, FlutterErrorDetails details) {
    final ({String title, RenderIssueKind kind, IssueSeverity severity})? hit =
        _match(msg);
    if (hit == null) return;

    final widgetType = details.context?.toString() ?? 'Unknown';
    final detail = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;

    // Legacy RenderIssue (unchanged behavior).
    store.addRenderIssue(RenderIssue(
      id: _uuid.v4(),
      kind: hit.kind,
      description: detail,
      widgetType: widgetType,
      capturedAt: DateTime.now(),
      severity: hit.severity == IssueSeverity.error
          ? RenderIssueSeverity.error
          : RenderIssueSeverity.warning,
    ));

    // Unified Issue.
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.layoutRender, '${hit.kind.name}|$widgetType'),
      category: IssueCategory.layoutRender,
      severity: hit.severity,
      source: IssueSource.detected,
      title: hit.title,
      detail: detail,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {'widget': widgetType},
    ));
  }

  ({String title, RenderIssueKind kind, IssueSeverity severity})? _match(String msg) {
    if (msg.contains('overflowed by') || msg.contains('RenderFlex overflowed')) {
      return (title: 'Render overflow', kind: RenderIssueKind.overflow, severity: IssueSeverity.error);
    }
    if (msg.contains('Unbounded') || msg.contains('forces an infinite')) {
      return (title: 'Unbounded constraints', kind: RenderIssueKind.unboundedConstraints, severity: IssueSeverity.warning);
    }
    if (msg.contains('intrinsic')) {
      return (title: 'Intrinsic measurement', kind: RenderIssueKind.intrinsicMeasurement, severity: IssueSeverity.warning);
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/render_collector_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/collectors/render_collector.dart test/render_collector_test.dart
git commit -m "feat: RenderCollector emits unified layoutRender issues"
```

---

## Task 5: `LifecycleCollector` → `Issue`

**Files:**
- Create: `lib/src/collectors/lifecycle_collector.dart`
- Modify: `lib/src/devtools.dart` (wire it in)
- Test: `test/lifecycle_collector_test.dart`

Context: many lifecycle bugs surface through `FlutterError.onError` with recognizable text ("setState() called after dispose()", "was used after being disposed", "This widget has been unmounted"). The `LifecycleCollector` classifies those into `Issue`s (category `lifecycle`); recurrence escalation is handled by the store (Task 2).

- [ ] **Step 1: Write the failing test** — create `test/lifecycle_collector_test.dart`:

```dart
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
    collector = LifecycleCollector(store: store, config: const CollectorConfig());
    await collector.start();
  });
  tearDown(() => collector.stop());

  void emit(String message) {
    FlutterError.onError!(FlutterErrorDetails(exception: FlutterError(message)));
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lifecycle_collector_test.dart`
Expected: FAIL — `lifecycle_collector.dart` / `LifecycleCollector` undefined.

- [ ] **Step 3a: Create the collector** — `lib/src/collectors/lifecycle_collector.dart`:

```dart
import 'package:flutter/foundation.dart';
import '../models/issue.dart';
import 'base_collector.dart';

/// Detects widget/state lifecycle violations from [FlutterError.onError]
/// (setState-after-dispose, use-after-dispose, unmounted access) and records
/// them as unified [Issue]s (category [IssueCategory.lifecycle]).
class LifecycleCollector extends BaseCollector {
  LifecycleCollector({required super.store, required super.config});

  FlutterExceptionHandler? _prevHandler;

  @override
  String get id => 'lifecycle_collector';

  @override
  Future<void> onStart() async {
    _prevHandler = FlutterError.onError;
    FlutterError.onError = _intercept;
  }

  @override
  Future<void> onStop() async {
    FlutterError.onError = _prevHandler;
  }

  void _intercept(FlutterErrorDetails details) {
    _prevHandler?.call(details);
    _classify(details.exceptionAsString());
  }

  void _classify(String msg) {
    final title = _match(msg);
    if (title == null) return;
    final detail = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.lifecycle, title),
      category: IssueCategory.lifecycle,
      severity: IssueSeverity.error,
      source: IssueSource.detected,
      title: title,
      detail: detail,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: const {},
    ));
  }

  String? _match(String msg) {
    if (msg.contains('called after dispose()')) return 'setState after dispose';
    if (msg.contains('used after being disposed')) return 'Object used after dispose';
    if (msg.contains('has been unmounted') || msg.contains('!_debugLifecycleState')) {
      return 'Access after unmount';
    }
    if (msg.contains('Another exception was thrown')) return 'Cascading exception';
    return null;
  }
}
```

- [ ] **Step 3b: Wire it into `devtools.dart`** — in `lib/src/devtools.dart`:

Add the import:
```dart
import 'collectors/lifecycle_collector.dart';
```

In `start()`, after the `renders` collector block, add:
```dart
    if (collectors.lifecycle) {
      _collectors.add(LifecycleCollector(store: _store!, config: collectors));
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/lifecycle_collector_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/collectors/lifecycle_collector.dart lib/src/devtools.dart test/lifecycle_collector_test.dart
git commit -m "feat: add LifecycleCollector for state/lifecycle issues"
```

---

## Task 6: `ErrorCollector` → also emit `Issue`

**Files:**
- Modify: `lib/src/collectors/error_collector.dart`
- Test: `test/error_collector_issue_test.dart`

Context: `ErrorCollector` already records `ErrorReport`s for Flutter + platform errors. This task ADDS a unified `Issue` (category `exception`) per error, so uncaught exceptions show up in `get_issues` alongside everything else. Existing `ErrorReport` behavior stays.

- [ ] **Step 1: Write the failing test** — create `test/error_collector_issue_test.dart`:

```dart
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

    final issues = store.issues.where((i) => i.category == IssueCategory.exception);
    expect(issues, isNotEmpty);
    expect(issues.first.source, IssueSource.detected);
    expect(issues.first.detail, contains('boom in build'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/error_collector_issue_test.dart`
Expected: FAIL — no exception issue recorded.

- [ ] **Step 3: Update `ErrorCollector`** — in `lib/src/collectors/error_collector.dart`:

Add the import:
```dart
import '../models/issue.dart';
```

In `_onFlutter`, after `store.addError(...)`, add:
```dart
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.exception, msg),
      category: IssueCategory.exception,
      severity: IssueSeverity.error,
      source: IssueSource.detected,
      title: msg.length > 80 ? '${msg.substring(0, 80)}…' : msg,
      detail: msg,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: {'library': d.library ?? 'unknown'},
    ));
```

In `_onPlatform`, after `store.addError(...)`, add:
```dart
    store.addIssue(Issue(
      signature: issueSignature(IssueCategory.exception, msg),
      category: IssueCategory.exception,
      severity: IssueSeverity.critical,
      source: IssueSource.detected,
      title: msg.length > 80 ? '${msg.substring(0, 80)}…' : msg,
      detail: '$msg\n$stack',
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      count: 1,
      evidence: const {'fatal': true},
    ));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/error_collector_issue_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/collectors/error_collector.dart test/error_collector_issue_test.dart
git commit -m "feat: ErrorCollector emits unified exception issues"
```

---

## Task 7: Observer-free `RouteResolver`

**Files:**
- Create: `lib/src/routing/route_resolver.dart`
- Test: `test/route_resolver_test.dart`

Context: resolve the current route name from the live element tree so route tracking needs no `NavigatorObserver`. Mechanism: find a deep element under the active route and read its `ModalRoute`. Works with `MaterialApp.routes`, `MaterialApp.router`, `go_router`, Navigator 2.0.

- [ ] **Step 1: Write the failing test** — create `test/route_resolver_test.dart`:

```dart
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

    key.currentState!.pushNamed('/detail');
    await tester.pumpAndSettle();

    expect(resolveCurrentRouteName(), '/detail');
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/route_resolver_test.dart`
Expected: FAIL — `route_resolver.dart` / `resolveCurrentRouteName` undefined.

- [ ] **Step 3: Write the implementation** — create `lib/src/routing/route_resolver.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Returns the name of the currently-active route by inspecting the live
/// element tree — no [NavigatorObserver] required. Works with MaterialApp.routes,
/// MaterialApp.router, go_router, and Navigator 2.0.
///
/// Reads the [ModalRoute] of the deepest element (which lives inside the topmost
/// route's content). Returns null if no routed content is mounted. Read-only and
/// guarded so it never perturbs the app.
String? resolveCurrentRouteName() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  final leaf = _deepestElement(root);
  if (leaf == null) return null;
  try {
    final route = ModalRoute.of(leaf);
    if (route == null) return null;
    return route.settings.name ?? route.runtimeType.toString();
  } catch (_) {
    return null;
  }
}

Element? _deepestElement(Element root) {
  Element? best;
  var bestDepth = -1;
  void dfs(Element e, int depth) {
    if (depth > bestDepth) {
      bestDepth = depth;
      best = e;
    }
    e.visitChildren((c) => dfs(c, depth + 1));
  }
  dfs(root, 0);
  return best;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/route_resolver_test.dart`
Expected: PASS (2 tests).

If `ModalRoute.of(leaf)` does not resolve the route in the test (e.g. the deepest element is in an overlay above the route), adapt `_deepestElement` to skip `Overlay`/`OverlayEntry` subtrees, or walk for the deepest element whose `ModalRoute.of` is non-null — but keep the public signature `resolveCurrentRouteName()` and the test assertions unchanged. Report any adaptation.

- [ ] **Step 5: Commit**

```bash
git add lib/src/routing/route_resolver.dart test/route_resolver_test.dart
git commit -m "feat: observer-free current-route resolver"
```

---

## Task 8: `get_issues` + enriched `get_runtime_summary` + resolver-backed `get_current_route`

**Files:**
- Modify: `lib/src/service_extensions.dart`
- Test: `test/get_issues_extension_test.dart`

Context: `service_extensions.dart` registers the app-side service extensions the bridge proxies. Add `get_issues`, route `get_current_route` through the resolver (falling back to the observer's data), and add issue counts to `get_runtime_summary`. Tests here verify the pure result-building helpers; full extension registration is smoke-tested.

- [ ] **Step 1: Write the failing test** — create `test/get_issues_extension_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/models/issue.dart';
import 'package:flutter_ai_devtools/src/service_extensions.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

Issue mk(String sig, IssueCategory cat, IssueSeverity sev) => Issue(
      signature: sig,
      category: cat,
      severity: sev,
      source: IssueSource.detected,
      title: sig,
      detail: 'd',
      firstSeen: DateTime(2026),
      lastSeen: DateTime(2026),
      count: 1,
      evidence: const {},
    );

void main() {
  test('buildIssuesResult filters by category and severity', () {
    final store = RuntimeStore();
    store.addIssue(mk('a', IssueCategory.exception, IssueSeverity.error));
    store.addIssue(mk('b', IssueCategory.layoutRender, IssueSeverity.warning));
    store.addIssue(mk('c', IssueCategory.exception, IssueSeverity.info));

    final all = buildIssuesResult(store, {});
    expect(all['count'], 3);

    final exceptions = buildIssuesResult(store, {'category': 'exception'});
    expect(exceptions['count'], 2);

    final errorsUp = buildIssuesResult(store, {'minSeverity': 'error'});
    expect(errorsUp['count'], 1); // only the 'error' one
  });

  test('buildIssuesResult sorts by severity desc then count desc', () {
    final store = RuntimeStore();
    store.addIssue(mk('warn', IssueCategory.exception, IssueSeverity.warning));
    store.addIssue(mk('crit', IssueCategory.exception, IssueSeverity.critical));
    final r = buildIssuesResult(store, {});
    final list = r['issues'] as List;
    expect((list.first as Map)['signature'], 'crit');
  });

  test('registerServiceExtensions registers without throwing', () {
    expect(() => registerServiceExtensions(RuntimeStore()), returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/get_issues_extension_test.dart`
Expected: FAIL — `buildIssuesResult` undefined.

- [ ] **Step 3: Update `service_extensions.dart`**:

Add imports at the top:
```dart
import '../models/issue.dart';
import '../routing/route_resolver.dart';
```

Add the public helper (top-level, after the imports) — kept public so it is unit-testable:
```dart
/// Builds the `get_issues` result from the store, applying optional
/// `category` / `minSeverity` filters and sorting by severity then count (desc).
Map<String, dynamic> buildIssuesResult(
    RuntimeStore store, Map<String, String> params) {
  final category = _enumByName(IssueCategory.values, params['category']);
  final minSeverity = _enumByName(IssueSeverity.values, params['minSeverity']);
  var issues = store.issues;
  if (category != null) {
    issues = issues.where((i) => i.category == category).toList();
  }
  if (minSeverity != null) {
    issues = issues.where((i) => i.severity.index >= minSeverity.index).toList();
  }
  final sorted = issues.toList()
    ..sort((a, b) {
      final s = b.severity.index.compareTo(a.severity.index);
      return s != 0 ? s : b.count.compareTo(a.count);
    });
  return {
    'count': sorted.length,
    'issues': sorted.map((i) => i.toJson()).toList(),
  };
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
```

Register the new extension inside `registerServiceExtensions` (alongside the others):
```dart
  _register('get_issues', (params) => buildIssuesResult(store, params));
```

Replace the existing `get_current_route` registration with a resolver-backed one:
```dart
  _register('get_current_route', (params) {
    final auto = resolveCurrentRouteName();
    final observed = store.currentRoute;
    if (auto == null && observed == null) {
      return {'error': 'No route captured yet'};
    }
    return {
      'name': observed?.name ?? auto,
      'source': observed != null ? 'observer' : 'auto',
      if (auto != null) 'autoDetected': auto,
      if (observed != null) 'observed': observed.toJson(),
    };
  });
```

In the existing `get_runtime_summary` registration, add these keys to the returned map (next to `errorCount`):
```dart
      'issueCount': store.issues.length,
      'criticalIssues':
          store.issues.where((i) => i.severity == IssueSeverity.critical).length,
      'currentRoute': resolveCurrentRouteName(),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/get_issues_extension_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/service_extensions.dart test/get_issues_extension_test.dart
git commit -m "feat: add get_issues extension + resolver-backed route + issue counts in summary"
```

---

## Task 9: Register the `get_issues` MCP tool

**Files:**
- Modify: `lib/src/mcp/tool_definitions.dart`
- Test: `test/get_issues_tool_test.dart`

- [ ] **Step 1: Write the failing test** — create `test/get_issues_tool_test.dart`:

```dart
import 'package:flutter_ai_devtools/src/bridge/vm_bridge.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_definitions.dart';
import 'package:flutter_ai_devtools/src/mcp/tool_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('get_issues is registered and proxies to the app (offline → error map)',
      () async {
    final bridge = VmBridge(connector: (_) async => null);
    addTearDown(bridge.dispose);
    final d = ToolDispatcher();
    registerBridgeTools(d, bridge);

    expect(d.toolNames, contains('get_issues'));
    final res = await d.dispatch('get_issues', {});
    expect(res['error'], contains('not connected'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/get_issues_tool_test.dart`
Expected: FAIL — `get_issues` not registered.

- [ ] **Step 3: Register the tool** — in `lib/src/mcp/tool_definitions.dart`, in the app-state proxies section (next to `get_render_issues`), add:
```dart
  d.register('get_issues', (a) => bridge.callTool('get_issues', a),
      description: 'Deduplicated issues: exceptions, layout/render, lifecycle, reported',
      schema: {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'enum': ['exception', 'layoutRender', 'lifecycle', 'reported'],
          },
          'minSeverity': {
            'type': 'string',
            'enum': ['info', 'warning', 'error', 'critical'],
          },
        },
      });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/get_issues_tool_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/mcp/tool_definitions.dart test/get_issues_tool_test.dart
git commit -m "feat: register get_issues MCP tool"
```

---

## Task 10: Full-suite verification

**Files:** none.

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: PASS — all Plan 1 tests plus the new Plan 2 tests (issue, issue_store, report_error, render_collector, lifecycle_collector, error_collector_issue, route_resolver, get_issues_extension, get_issues_tool).

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib bin test`
Expected: "No issues found!"

- [ ] **Step 3: Smoke-test tools/list includes get_issues**

Run:
```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | dart run flutter_ai_devtools:devtools_mcp
```
Expected: the `tools/list` result includes `get_issues` among the tools.

- [ ] **Step 4: Commit (if any fixups)**

```bash
git add -A && git commit -m "test: full suite green for structured issues + routing" --allow-empty
```

---

## Self-Review Checklist (completed by plan author)

- **Spec coverage:** Issue model + dedup/escalation (spec 3.1) → Tasks 1–2; reportError/reportIssue (3.5) → Task 3; layout/render (3.3) → Task 4; lifecycle (3.4) → Task 5; exception capture → Task 6; observer-free routing (Section 4) → Task 7; `get_issues` + enriched summary + `source` field (Section 5) → Tasks 8–9. Deferred (bridge text-scraping, hot_reload report, ingestion-sync refactor) called out at top.
- **Type consistency:** `Issue`/`IssueCategory`/`IssueSeverity`/`IssueSource`, `issueSignature`, `RuntimeStore.addIssue`/`issues`/`recurrenceThreshold`/`maxIssues`, `CollectorConfig.lifecycle`, `resolveCurrentRouteName`, `buildIssuesResult`, `registerBridgeTools(d, bridge)` — consistent across tasks.
- **Placeholder scan:** none.

---

## Out of scope (future)

- Bridge-side text-pattern detectors over the raw log stream (fallback for issues never routed through `FlutterError`).
- `hot_reload` surfacing `ReloadReport` compile errors.
- Event-driven ingestion re-attach (replacing the 500ms poll) + post-reconnect log-gap.
- These remain for a later plan; Plan 3 still covers `cli/` deletion, README, and the example refresh.
