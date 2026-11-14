import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

void main() {
  group('BridgeConfig', () {
    late BridgeConfig config;

    setUp(() {
      config = BridgeConfig(
        environment: BridgeEnvironment.dev,
        commonValues: {
          'appName': 'ModularBridgeApp',
          'supportEmail': 'support@example.com',
          'port': 8080,
          'timeout': const Duration(seconds: 30),
          'isDebug': true,
          'apiRatio': 1.5,
          'serverUri': Uri.parse('https://example.com/api'),
        },
        environmentValues: {
          BridgeEnvironment.dev: {
            'apiUrl': 'https://dev.api.com',
            'featureBiometrics': false,
            'maxRetries': 5,
          },
          BridgeEnvironment.staging: {
            'apiUrl': 'https://staging.api.com',
            'featureBiometrics': true,
            'maxRetries': 3,
          },
          BridgeEnvironment.prod: {
            'apiUrl': 'https://api.com',
            'featureBiometrics': true,
            'maxRetries': 1,
          },
        },
      );
    });

    tearDown(() {
      config.dispose();
    });

    test('reads strongly typed values correctly', () {
      expect(config.getString('appName'), 'ModularBridgeApp');
      expect(config.getString('apiUrl'), 'https://dev.api.com');
      expect(config.getInt('port'), 8080);
      expect(config.getInt('maxRetries'), 5);
      expect(config.getBool('featureBiometrics'), isFalse);
      expect(config.getDouble('apiRatio'), 1.5);
      expect(config.getDuration('timeout'), const Duration(seconds: 30));
      expect(config.getUri('serverUri'), Uri.parse('https://example.com/api'));
    });

    test(
        'throws BridgeConfigKeyNotFoundException when key is missing and no default provided',
        () {
      expect(
        () => config.get<String>('nonExistentKey'),
        throwsA(isA<BridgeConfigKeyNotFoundException>()),
      );
      expect(
        () => config.getString('nonExistentKey'),
        throwsA(isA<BridgeConfigKeyNotFoundException>()),
      );
    });

    test('returns defaultValue when key is missing', () {
      expect(config.getString('nonExistentKey', defaultValue: 'fallback'),
          'fallback');
      expect(config.getInt('missingInt', defaultValue: 42), 42);
      expect(config.getBool('missingBool', defaultValue: true), isTrue);
      expect(config.getDouble('missingDouble', defaultValue: 3.14), 3.14);
      expect(
        config.getDuration('missingDuration',
            defaultValue: const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
      expect(
        config.getUri('missingUri',
            defaultValue: Uri.parse('https://fallback.com')),
        Uri.parse('https://fallback.com'),
      );
    });

    test('throws BridgeConfigTypeMismatchException when type does not match',
        () {
      expect(
        () => config.getInt('appName'), // appName is String 'ModularBridgeApp'
        throwsA(isA<BridgeConfigTypeMismatchException>().having(
          (e) => e.message,
          'message',
          contains('expected type \'int\''),
        )),
      );
    });

    test('environment-specific value overrides common value with the same key',
        () {
      final merged = BridgeConfig(
        environment: BridgeEnvironment.dev,
        commonValues: {'shared': 'common-value'},
        environmentValues: {
          BridgeEnvironment.dev: {'shared': 'env-value'},
        },
      );
      addTearDown(merged.dispose);

      expect(merged.getString('shared'), 'env-value');
    });

    test('hot-switches environment at runtime and notifies listeners',
        () async {
      expect(config.environment, BridgeEnvironment.dev);
      expect(config.getString('apiUrl'), 'https://dev.api.com');
      expect(config.getInt('maxRetries'), 5);

      final envChanges = <BridgeEnvironment>[];
      final subscription = config.onEnvironmentChanged.listen(envChanges.add);

      config.switchEnvironment(BridgeEnvironment.prod);

      // Wait a microtask for broadcast
      await Future<void>.delayed(Duration.zero);

      expect(config.environment, BridgeEnvironment.prod);
      expect(config.getString('apiUrl'), 'https://api.com');
      expect(config.getInt('maxRetries'), 1);
      expect(envChanges, [BridgeEnvironment.prod]);

      await subscription.cancel();
    });

    test(
        'switching to an environment without a key falls back to common values',
        () async {
      config.switchEnvironment(BridgeEnvironment.staging);
      await Future<void>.delayed(Duration.zero);

      // 'appName' exists only in commonValues and must remain readable.
      expect(config.getString('appName'), 'ModularBridgeApp');
      expect(config.getString('apiUrl'), 'https://staging.api.com');
    });

    test('coerces primitive values for typed getters', () {
      config.set('stringFromInt', 42);
      config.set('stringFromBool', true);
      config.set('intFromString', '123');
      config.set('doubleFromString', '2.5');
      config.set('boolFromString', 'TRUE');
      config.set('durationFromInt', 1500);
      config.set('uriFromString', 'https://example.com/path');

      expect(config.getString('stringFromInt'), '42');
      expect(config.getString('stringFromBool'), 'true');
      expect(config.getInt('intFromString'), 123);
      expect(config.getDouble('doubleFromString'), 2.5);
      expect(config.getBool('boolFromString'), isTrue);
      expect(config.getBool('featureBiometrics'), isFalse);
      expect(config.getDuration('durationFromInt'),
          const Duration(milliseconds: 1500));
      expect(config.getUri('uriFromString'),
          Uri.parse('https://example.com/path'));
    });

    test('tryGet returns null on type mismatch', () {
      expect(config.tryGet<int>('appName'), isNull); // String value
      expect(config.tryGet<String>('appName'), 'ModularBridgeApp');
    });

    test('currentValues returns an unmodifiable snapshot', () {
      final snapshot = config.currentValues;
      expect(snapshot['appName'], 'ModularBridgeApp');
      expect(() => snapshot['appName'] = 'hacked', throwsUnsupportedError);
    });

    test('mutations throw StateError after dispose while reads still work', () {
      config.dispose();
      config.dispose(); // idempotent

      expect(config.isDisposed, isTrue);
      expect(config.getString('appName'), 'ModularBridgeApp');
      expect(() => config.set('k', 'v'), throwsStateError);
      expect(() => config.setAll({'k': 'v'}), throwsStateError);
      expect(() => config.remove('k'), throwsStateError);
      expect(
        () => config.switchEnvironment(BridgeEnvironment.prod),
        throwsStateError,
      );
    });

    test('set values persist across environment switches as runtime overrides',
        () async {
      config.set('promoCode', 'SUMMER2026');
      config.set('apiUrl', 'https://override.api.com'); // overrides env value

      config.switchEnvironment(BridgeEnvironment.prod);
      await Future<void>.delayed(Duration.zero);

      expect(config.getString('promoCode'), 'SUMMER2026');
      expect(config.getString('apiUrl'), 'https://override.api.com');
    });

    test('remove restores the underlying configured value', () {
      config.set('apiUrl', 'https://override.api.com');
      expect(config.getString('apiUrl'), 'https://override.api.com');

      expect(config.remove('apiUrl'), isTrue);
      expect(config.getString('apiUrl'), 'https://dev.api.com');
      expect(config.remove('apiUrl'), isFalse);
    });

    test('onChanged emits on set, setAll, remove, and environment switch',
        () async {
      final emissions = <void>[];
      final sub = config.onChanged.listen((_) => emissions.add(null));
      addTearDown(sub.cancel);

      config.set('k1', 'v1');
      config.setAll({'k2': 'v2'});
      config.remove('k1');
      config.switchEnvironment(BridgeEnvironment.staging);

      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, 4);
    });

    test('runtimeOverrides passed to switchEnvironment persist', () async {
      config.switchEnvironment(
        BridgeEnvironment.prod,
        runtimeOverrides: {'hotfix': 'enabled'},
      );
      await Future<void>.delayed(Duration.zero);

      config.switchEnvironment(BridgeEnvironment.dev);
      await Future<void>.delayed(Duration.zero);

      expect(config.getString('hotfix'), 'enabled');
    });

    test('parses BridgeEnvironment from string correctly', () {
      expect(BridgeEnvironment.fromString('dev'), BridgeEnvironment.dev);
      expect(
          BridgeEnvironment.fromString('DEVELOPMENT'), BridgeEnvironment.dev);
      expect(
          BridgeEnvironment.fromString('staging'), BridgeEnvironment.staging);
      expect(BridgeEnvironment.fromString('prod'), BridgeEnvironment.prod);
      expect(
        () => BridgeEnvironment.fromString('invalid_env'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
