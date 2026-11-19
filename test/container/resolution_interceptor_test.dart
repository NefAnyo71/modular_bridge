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

  group('Resolution interceptors', () {
    test('interceptor observes sync resolution and can wrap the result', () {
      bridge.registerSingleton<AuthService>(RealAuthService());
      final seen = <Type>[];

      bridge.addResolutionInterceptor((request, next) {
        seen.add(request.type);
        final value = next() as AuthService;
        return _PrefixingAuthService(value);
      });

      final service = bridge.get<AuthService>();

      expect(service, isA<_PrefixingAuthService>());
      expect(seen, [AuthService]);
      expect(service.login('a@b.c'), 'intercepted_real_token_for_a@b.c');
    });

    test('sync resolution of a Future-typed dependency does not throw',
        () async {
      // T = Future<int>: the Future is the resolved value, not an
      // interceptor accidentally going async.
      bridge.registerFactory<Future<int>>(() async => 42);
      bridge.addResolutionInterceptor((request, next) => next());

      final future = bridge.get<Future<int>>();
      expect(await future, 42);
    });

    test('interceptor can short-circuit without calling next', () {
      bridge.registerSingleton<AuthService>(RealAuthService());

      bridge.addResolutionInterceptor((request, next) {
        if (request.type == AuthService) return MockAuthService();
        return next();
      });

      expect(bridge.get<AuthService>().login('x'), 'mock_token_for_x');
    });

    test('interceptors run onion-style in registration order', () {
      bridge.registerSingleton<UserRepository>(UserRepository());
      final order = <String>[];

      bridge
        ..addResolutionInterceptor((request, next) {
          order.add('outer-in');
          final result = next();
          order.add('outer-out');
          return result;
        })
        ..addResolutionInterceptor((request, next) {
          order.add('inner-in');
          final result = next();
          order.add('inner-out');
          return result;
        });

      bridge.get<UserRepository>();

      expect(order, ['outer-in', 'inner-in', 'inner-out', 'outer-out']);
    });

    test('request exposes type, instanceName, isAsync, and bridge', () {
      bridge.registerSingleton<UserRepository>(UserRepository(),
          instanceName: 'primary');
      BridgeResolutionRequest? captured;

      bridge.addResolutionInterceptor((request, next) {
        captured = request;
        return next();
      });

      bridge.get<UserRepository>(instanceName: 'primary');

      expect(captured, isNotNull);
      expect(captured!.type, UserRepository);
      expect(captured!.instanceName, 'primary');
      expect(captured!.isAsync, isFalse);
      expect(captured!.bridge, same(bridge));
      expect(captured!.arguments, isEmpty);
    });

    test('param resolution exposes arguments', () {
      bridge.registerFactoryParam<String, int, String>(
        (count, suffix) => '$count$suffix',
      );
      BridgeResolutionRequest? captured;

      bridge.addResolutionInterceptor((request, next) {
        captured = request;
        return next();
      });

      final result = bridge.getParam<String, int, String>(
        param1: 7,
        param2: '!',
      );

      expect(result, '7!');
      expect(captured!.arguments, [7, '!']);
    });

    test('async interceptor wraps getAsync resolutions', () async {
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async => AsyncConfig('loaded'),
      );
      final seen = <Type>[];

      bridge.addResolutionInterceptor((request, next) async {
        seen.add(request.type);
        final value = await next() as AsyncConfig;
        return AsyncConfig('${value.value}-wrapped');
      });

      final config = await bridge.getAsync<AsyncConfig>();

      expect(config.value, 'loaded-wrapped');
      expect(seen, [AsyncConfig]);
    });

    test('sync interceptor may return a plain value on async path', () async {
      bridge.registerSingleton<UserRepository>(UserRepository());

      bridge.addResolutionInterceptor((request, next) => UserRepository());

      final repo = await bridge.getAsync<UserRepository>();
      expect(repo, isA<UserRepository>());
    });

    test('interceptor throwing propagates the error', () {
      bridge.registerSingleton<UserRepository>(UserRepository());

      bridge.addResolutionInterceptor((request, next) {
        throw StateError('blocked');
      });

      expect(() => bridge.get<UserRepository>(), throwsStateError);
    });

    test('resolution errors propagate through the chain', () {
      bridge.addResolutionInterceptor((request, next) => next());

      expect(
        () => bridge.get<AuthService>(),
        throwsA(isA<BridgeDependencyNotFoundException>()),
      );
    });

    test('Future returned on sync path throws BridgeAsyncInterceptorException',
        () {
      bridge.registerSingleton<UserRepository>(UserRepository());

      bridge.addResolutionInterceptor((request, next) async => next());

      expect(
        () => bridge.get<UserRepository>(),
        throwsA(isA<BridgeAsyncInterceptorException>()),
      );
    });

    test('removeResolutionInterceptor and clearResolutionInterceptors', () {
      bridge.registerSingleton<UserRepository>(UserRepository());
      var calls = 0;

      Object? interceptor(
        BridgeResolutionRequest request,
        BridgeResolutionNext next,
      ) {
        calls++;
        return next();
      }

      bridge.addResolutionInterceptor(interceptor);
      bridge.get<UserRepository>();
      expect(calls, 1);

      expect(bridge.removeResolutionInterceptor(interceptor), isTrue);
      expect(bridge.removeResolutionInterceptor(interceptor), isFalse);
      bridge.get<UserRepository>();
      expect(calls, 1);

      bridge
        ..addResolutionInterceptor(interceptor)
        ..addResolutionInterceptor(interceptor);
      expect(bridge.resolutionInterceptors, hasLength(2));
      bridge.clearResolutionInterceptors();
      expect(bridge.resolutionInterceptors, isEmpty);
      bridge.get<UserRepository>();
      expect(calls, 1);
    });

    test('interceptor wraps scope resolution when a scope is active', () {
      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.registerSingleton<UserRepository>(UserRepository());
      final seen = <Type>[];

      bridge.addResolutionInterceptor((request, next) {
        seen.add(request.type);
        return next();
      });

      bridge.get<UserRepository>();

      expect(seen, [UserRepository]);
    });

    test('nested resolutions are intercepted per call', () {
      bridge
        ..registerSingleton<UserRepository>(UserRepository())
        ..registerLazySingleton<AuthService>(() => RealAuthService());
      final count = <Type, int>{};

      bridge.addResolutionInterceptor((request, next) {
        count.update(request.type, (v) => v + 1, ifAbsent: () => 1);
        return next();
      });

      // A factory that resolves another dependency internally produces a
      // nested intercepted resolution.
      bridge.registerFactory<OuterService>(() => OuterService(bridge));
      bridge.get<OuterService>();

      expect(count[OuterService], 1);
      expect(count[UserRepository], 1);
    });

    test('interceptors are cleared on dispose', () async {
      bridge.registerSingleton<UserRepository>(UserRepository());
      bridge.addResolutionInterceptor((request, next) => next());
      await bridge.dispose();

      expect(bridge.resolutionInterceptors, isEmpty);
    });

    test('BridgeInterceptors.logging reports sync resolutions', () {
      bridge.registerSingleton<UserRepository>(UserRepository(),
          instanceName: 'repo');
      final messages = <String>[];

      bridge.addResolutionInterceptor(
          BridgeInterceptors.logging(log: messages.add));

      bridge.get<UserRepository>(instanceName: 'repo');

      expect(messages, hasLength(1));
      expect(messages.single, contains('UserRepository'));
      expect(messages.single, contains('repo'));
      expect(messages.single, contains('resolved'));
    });

    test('BridgeInterceptors.logging reports failures', () {
      final messages = <String>[];
      bridge.addResolutionInterceptor(
          BridgeInterceptors.logging(log: messages.add));

      expect(() => bridge.get<AuthService>(),
          throwsA(isA<BridgeDependencyNotFoundException>()));
      expect(messages.single, contains('FAILED'));
    });

    test('BridgeInterceptors.logging wraps async resolutions', () async {
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('v'));
      final messages = <String>[];

      bridge.addResolutionInterceptor(
          BridgeInterceptors.logging(log: messages.add));

      await bridge.getAsync<AsyncConfig>();
      expect(messages.single, contains('AsyncConfig'));
      expect(messages.single, contains('resolved'));
    });

    test('BridgeInterceptors.timing reports structured timings', () async {
      bridge.registerSingleton<UserRepository>(UserRepository());
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('v'));
      final timings = <BridgeResolutionTiming>[];

      bridge.addResolutionInterceptor(BridgeInterceptors.timing(timings.add));

      bridge.get<UserRepository>();
      await bridge.getAsync<AsyncConfig>();

      expect(timings, hasLength(2));
      expect(timings[0].request.type, UserRepository);
      expect(timings[0].succeeded, isTrue);
      expect(timings[0].elapsed, isNotNull);
      expect(timings[1].request.isAsync, isTrue);
    });

    test('timing callback errors do not break resolution', () {
      bridge.registerSingleton<UserRepository>(UserRepository());
      bridge.addResolutionInterceptor(BridgeInterceptors.timing((_) {
        throw StateError('metrics backend down');
      }));

      expect(bridge.get<UserRepository>(), isA<UserRepository>());
    });

    test('works with no interceptors registered (fast path)', () {
      bridge.registerSingleton<UserRepository>(UserRepository());
      expect(bridge.get<UserRepository>(), isA<UserRepository>());
      expect(bridge.tryGet<UserRepository>(), isA<UserRepository>());
      expect(bridge.tryGet<AuthService>(), isNull);
    });
  });
}

class _PrefixingAuthService implements AuthService {
  _PrefixingAuthService(this._inner);
  final AuthService _inner;

  @override
  String login(String email) => 'intercepted_${_inner.login(email)}';
}

class OuterService {
  OuterService(this.bridge) {
    repo = bridge.get<UserRepository>();
  }

  final ModularBridge bridge;
  late final UserRepository repo;
}
