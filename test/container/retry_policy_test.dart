import 'package:modular_bridge/modular_bridge.dart';
import 'package:test/test.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  late ModularBridge bridge;

  setUp(() {
    bridge = ModularBridge.createIsolated();
  });

  tearDown(() async {
    await bridge.dispose();
  });

  group('BridgeRetryPolicy', () {
    test('retries a failing async factory until it succeeds', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          if (attempts < 3) throw StateError('transient $attempts');
          return AsyncConfig('recovered');
        },
        retryPolicy: const BridgeRetryPolicy(maxAttempts: 5),
      );

      final config = await bridge.getAsync<AsyncConfig>();

      expect(config.value, 'recovered');
      expect(attempts, 3);
    });

    test('propagates the last error after maxAttempts', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          throw StateError('always fails');
        },
        retryPolicy: const BridgeRetryPolicy(maxAttempts: 3),
      );

      await expectLater(
        bridge.getAsync<AsyncConfig>(),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 3);
    });

    test('retryIf=false fails immediately without retrying', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          throw StateError('fatal');
        },
        retryPolicy: BridgeRetryPolicy(
          maxAttempts: 5,
          retryIf: (e) => false,
        ),
      );

      await expectLater(
        bridge.getAsync<AsyncConfig>(),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });

    test('retryIf predicate receives the thrown error', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          if (attempts == 1) throw ArgumentError('retryable');
          throw StateError('fatal');
        },
        retryPolicy: BridgeRetryPolicy(
          maxAttempts: 5,
          retryIf: (e) => e is ArgumentError,
        ),
      );

      await expectLater(
        bridge.getAsync<AsyncConfig>(),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 2);
    });

    test('no policy means a single attempt', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          throw StateError('boom');
        },
      );

      await expectLater(
        bridge.getAsync<AsyncConfig>(),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });

    test('retry applies to registerFactoryAsync per resolution', () async {
      var attempts = 0;
      bridge.registerFactoryAsync<UserRepository>(
        () async {
          attempts++;
          if (attempts == 1) throw StateError('flaky');
          return UserRepository();
        },
        retryPolicy: const BridgeRetryPolicy(maxAttempts: 3),
      );

      final repo = await bridge.getAsync<UserRepository>();
      expect(repo, isA<UserRepository>());
      expect(attempts, 2);

      // Transient factories retry per call.
      await bridge.getAsync<UserRepository>();
      expect(attempts, 3);
    });

    test('retry works for scope-registered async singletons', () async {
      var attempts = 0;
      bridge.pushNewScope(scopeName: 's');
      // Register through the bridge while the scope is active so the
      // registration (and retryPolicy) lands on the scope.
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          if (attempts < 3) throw StateError('flaky');
          return AsyncConfig('scope-ok');
        },
        instanceName: 'retried',
        retryPolicy: const BridgeRetryPolicy(maxAttempts: 3),
      );

      final config =
          await bridge.getAsync<AsyncConfig>(instanceName: 'retried');
      expect(config.value, 'scope-ok');
      expect(attempts, 3);
    });

    test('successful first attempt does not invoke retry machinery', () async {
      var attempts = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          attempts++;
          return AsyncConfig('first-try');
        },
        retryPolicy: const BridgeRetryPolicy(maxAttempts: 5),
      );

      final config = await bridge.getAsync<AsyncConfig>();
      expect(config.value, 'first-try');
      expect(attempts, 1);
    });
  });
}
