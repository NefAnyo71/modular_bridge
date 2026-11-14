import 'package:test/test.dart';
import 'package:modular_bridge/modular_bridge.dart';

/// Manual performance benchmark — not part of the default `flutter test` run.
///
/// Run with:
/// ```sh
/// flutter test benchmark/
/// ```
void main() {
  test('DI resolution throughput benchmark', () async {
    final bridge = ModularBridge.createIsolated();
    addTearDown(() async => bridge.reset());

    bridge.registerSingleton<String>('singleton');
    bridge.registerLazySingleton<int>(() => 42);
    bridge.registerFactory<double>(() => 3.14);
    bridge.registerAsyncSingleton<List<int>>(() async => [1, 2, 3]);

    const iterations = 20000;

    // Sync get
    var sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      bridge.get<String>();
      bridge.get<int>();
      bridge.get<double>();
    }
    sw.stop();
    // ignore: avoid_print
    print('sync get x3  : ${sw.elapsedMilliseconds}ms '
        '(${iterations * 3 / sw.elapsedMilliseconds * 1000 ~/ 1} ops/s)');

    // Scope fallback get
    bridge.pushNewScope(scopeName: 'bench');
    sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      bridge.get<String>(); // scope miss -> root fallback
    }
    sw.stop();
    // ignore: avoid_print
    print('scope->root  : ${sw.elapsedMilliseconds}ms '
        '(${iterations / sw.elapsedMilliseconds * 1000 ~/ 1} ops/s)');
    await bridge.popScope();

    // Async get
    sw = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      await bridge.getAsync<List<int>>();
    }
    sw.stop();
    // ignore: avoid_print
    print('async get    : ${sw.elapsedMilliseconds}ms '
        '(${2000 / sw.elapsedMilliseconds * 1000 ~/ 1} ops/s)');
  });
}
