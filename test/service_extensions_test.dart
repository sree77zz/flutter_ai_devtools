import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_devtools/src/service_extensions.dart';
import 'package:flutter_ai_devtools/src/store/runtime_store.dart';

void main() {
  test('registerServiceExtensions registers all 8 tools without throwing', () {
    final store = RuntimeStore();
    expect(() => registerServiceExtensions(store), returnsNormally);
  });
}
