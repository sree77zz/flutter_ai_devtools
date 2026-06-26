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
