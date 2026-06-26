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
      expect(
          (configs.first as Map)['args'],
          containsAll(
              ['--host-vmservice-port=8181', '--disable-service-auth-codes']));
    });

    test('does not include the conflicting --vm-service-port flag', () {
      // Flutter rejects --vm-service-port alongside --host-vmservice-port.
      final out = mergeLaunchConfig(null);
      final ai = (out['configurations'] as List)
              .firstWhere((c) => (c as Map)['name'] == 'Flutter + AI DevTools')
          as Map;
      expect(
          (ai['args'] as List)
              .any((a) => (a as String).startsWith('--vm-service-port')),
          isFalse);
    });

    test('preserves existing user configurations', () {
      final existing = jsonEncode({
        'version': '0.2.0',
        'configurations': [
          {'name': 'My App', 'request': 'launch', 'type': 'dart'},
        ],
      });
      final out = mergeLaunchConfig(existing);
      final names = (out['configurations'] as List)
          .map((c) => (c as Map)['name'])
          .toList();
      expect(names, containsAll(['My App', 'Flutter + AI DevTools']));
    });

    test('places the AI DevTools config first so it is the default', () {
      final existing = jsonEncode({
        'version': '0.2.0',
        'configurations': [
          {'name': 'My App', 'request': 'launch', 'type': 'dart'},
        ],
      });
      final out = mergeLaunchConfig(existing);
      final configs = out['configurations'] as List;
      expect((configs.first as Map)['name'], 'Flutter + AI DevTools',
          reason: "VS Code pre-selects the first configuration");
      final names = configs.map((c) => (c as Map)['name']).toList();
      expect(names, ['Flutter + AI DevTools', 'My App'],
          reason: 'ours first, existing configs preserved after');
    });

    test('is idempotent — does not duplicate on re-run', () {
      final first = jsonEncode(mergeLaunchConfig(null));
      final second = mergeLaunchConfig(first);
      final aiConfigs = (second['configurations'] as List)
          .where((c) => (c as Map)['name'] == 'Flutter + AI DevTools');
      expect(aiConfigs, hasLength(1));
    });

    test('canonical config includes the host-vmservice-port arg', () {
      final out = mergeLaunchConfig(null);
      final ai = (out['configurations'] as List)
              .firstWhere((c) => (c as Map)['name'] == 'Flutter + AI DevTools')
          as Map;
      expect(ai['args'], contains('--host-vmservice-port=8181'));
    });

    test('refreshes a stale managed entry to canonical args', () {
      final stale = jsonEncode({
        'version': '0.2.0',
        'configurations': [
          {'name': 'My App', 'request': 'launch', 'type': 'dart'},
          {
            'name': 'Flutter + AI DevTools',
            'request': 'launch',
            'type': 'dart',
            'args': ['--vm-service-port=8181', '--disable-service-auth-codes'],
          },
        ],
      });
      final out = mergeLaunchConfig(stale);
      final aiEntries = (out['configurations'] as List)
          .where((c) => (c as Map)['name'] == 'Flutter + AI DevTools')
          .toList();
      expect(aiEntries, hasLength(1),
          reason: 'still exactly one managed entry');
      expect((aiEntries.first as Map)['args'],
          contains('--host-vmservice-port=8181'));
      // other user configs preserved
      final names = (out['configurations'] as List)
          .map((c) => (c as Map)['name'])
          .toList();
      expect(names, contains('My App'));
    });

    test('tolerates a non-list configurations value', () {
      final out = mergeLaunchConfig(
          jsonEncode({'configurations': <String, dynamic>{}}));
      final ai = (out['configurations'] as List)
          .where((c) => (c as Map)['name'] == 'Flutter + AI DevTools');
      expect(ai, hasLength(1));
    });

    test('throws FormatException on non-object JSON', () {
      expect(() => mergeLaunchConfig('[1,2,3]'), throwsFormatException);
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

  group('mergeMcpJson', () {
    test('creates the flutter_ai_devtools stdio server from null', () {
      final json = jsonDecode(mergeMcpJson(null)) as Map<String, dynamic>;
      final server = (json['mcpServers'] as Map)['flutter_ai_devtools'] as Map;
      expect(server['type'], 'stdio');
      expect(server['args'], contains('flutter_ai_devtools:devtools_mcp'));
    });

    test('preserves other MCP servers', () {
      final existing = jsonEncode({
        'mcpServers': {
          'github': {'type': 'stdio', 'command': 'gh-mcp'},
        },
      });
      final json = jsonDecode(mergeMcpJson(existing)) as Map<String, dynamic>;
      final servers = json['mcpServers'] as Map;
      expect(servers.keys, containsAll(['github', 'flutter_ai_devtools']));
    });

    test('throws FormatException on non-object JSON', () {
      expect(() => mergeMcpJson('"a string"'), throwsFormatException);
    });
  });
}
