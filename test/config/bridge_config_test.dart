import 'dart:convert';

import 'package:test/test.dart';
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

    test(
        'switchEnvironment with same env and overrides does not emit env event',
        () async {
      final envEvents = <BridgeEnvironment>[];
      final changeEvents = <void>[];
      final envSub = config.onEnvironmentChanged.listen(envEvents.add);
      final changeSub = config.onChanged.listen((_) => changeEvents.add(null));
      addTearDown(envSub.cancel);
      addTearDown(changeSub.cancel);

      config.switchEnvironment(
        BridgeEnvironment.dev, // same environment
        runtimeOverrides: {'runtime.key': 'value'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(envEvents, isEmpty);
      expect(changeEvents, hasLength(1));
      expect(config.getString('runtime.key'), 'value');
    });

    test('set/setAll with unchanged values do not emit onChanged', () async {
      final emissions = <void>[];
      final sub = config.onChanged.listen((_) => emissions.add(null));
      addTearDown(sub.cancel);

      config.set('appName', 'ModularBridgeApp'); // same effective value
      config.setAll({'appName': 'ModularBridgeApp'});
      config.switchEnvironment(
        BridgeEnvironment.dev, // same env
        runtimeOverrides: const {}, // empty overrides are a no-op
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, isEmpty);
    });

    test('set/setAll with structurally equal collections do not emit onChanged',
        () async {
      final emissions = <void>[];
      final sub = config.onChanged.listen((_) => emissions.add(null));
      addTearDown(sub.cancel);

      config.set('features', {
        'a': true,
        'nested': [1, 2]
      });
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));

      // Equal-but-not-identical collections must not retrigger listeners.
      config.set('features', {
        'a': true,
        'nested': [1, 2]
      });
      config.setAll({
        'features': {
          'a': true,
          'nested': [1, 2]
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));

      config.set('features', {
        'a': false,
        'nested': [1, 2]
      });
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(2));
    });

    test('removeRuntimeOverrides restores configured values', () async {
      final emissions = <void>[];
      final sub = config.onChanged.listen((_) => emissions.add(null));
      addTearDown(sub.cancel);

      config.set('appName', 'Overridden');
      config.set('runtime.only', 'x');
      expect(config.getString('appName'), 'Overridden');

      expect(config.removeRuntimeOverrides(), isTrue);
      expect(config.getString('appName'), 'ModularBridgeApp');
      expect(config.hasKey('runtime.only'), isFalse);
      expect(config.removeRuntimeOverrides(), isFalse);

      await Future<void>.delayed(Duration.zero);
      // Two set() calls + one removeRuntimeOverrides().
      expect(emissions, hasLength(3));
    });

    test('getMap returns unmodifiable nested maps and getSection decodes them',
        () {
      final configWithSection = BridgeConfig(
        environment: BridgeEnvironment.dev,
        commonValues: {
          'api': {
            'baseUrl': 'https://api.example.com',
            'timeoutMs': 5000,
            'retries': 3,
          },
        },
      );
      addTearDown(configWithSection.dispose);

      final map = configWithSection.getMap('api');
      expect(map['baseUrl'], 'https://api.example.com');
      expect(() => map['baseUrl'] = 'x', throwsUnsupportedError);

      final section = configWithSection.getSection<ApiSection>(
        'api',
        (m) => ApiSection(
          baseUrl: m['baseUrl'] as String,
          timeoutMs: m['timeoutMs'] as int,
          retries: m['retries'] as int,
        ),
      );

      expect(section.baseUrl, 'https://api.example.com');
      expect(section.timeoutMs, 5000);
      expect(section.retries, 3);
    });

    test('getMap throws for missing keys and non-map values', () {
      expect(() => config.getMap('missing'),
          throwsA(isA<BridgeConfigKeyNotFoundException>()));
      expect(
        () => config.getMap('appName'), // String value
        throwsA(isA<BridgeConfigTypeMismatchException>()),
      );
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

  group('BridgeConfig JSON loaders', () {
    const jsonDoc = '''
    {
      "environment": "dev",
      "common": { "appName": "Demo", "retries": 3 },
      "environments": {
        "dev": { "apiUrl": "http://localhost:8080" },
        "prod": { "apiUrl": "https://api.example.com", "appName": "DemoProd" }
      }
    }
    ''';

    test('fromString resolves environment, common and env values', () {
      final c = BridgeConfig.fromString(jsonDoc);
      addTearDown(c.dispose);

      expect(c.environment, BridgeEnvironment.dev);
      expect(c.getString('apiUrl'), 'http://localhost:8080');
      expect(c.getString('appName'), 'Demo');
      expect(c.getInt('retries'), 3);
    });

    test('fromJson environment parameter overrides the JSON key', () {
      final decoded = jsonDecode(jsonDoc) as Map<String, dynamic>;
      final c = BridgeConfig.fromJson(
        decoded,
        environment: BridgeEnvironment.prod,
      );
      addTearDown(c.dispose);

      expect(c.environment, BridgeEnvironment.prod);
      expect(c.getString('apiUrl'), 'https://api.example.com');
      // Environment values override common values.
      expect(c.getString('appName'), 'DemoProd');
    });

    test('environment aliases like "production" are accepted', () {
      final c = BridgeConfig.fromString(
        jsonDoc.replaceAll('"dev"', '"production"'),
      );
      addTearDown(c.dispose);

      expect(c.environment, BridgeEnvironment.prod);
      expect(c.getString('apiUrl'), 'https://api.example.com');
    });

    test('throws ArgumentError when no environment is provided', () {
      expect(
        () => BridgeConfig.fromString('{"common": {}}'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for a non-object JSON root', () {
      expect(
        () => BridgeConfig.fromString('[1, 2, 3]'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromAsset uses the provided loader', () async {
      String? loadedPath;
      final c = await BridgeConfig.fromAsset(
        'assets/config.json',
        loader: (path) async {
          loadedPath = path;
          return jsonDoc;
        },
      );
      addTearDown(c.dispose);

      expect(loadedPath, 'assets/config.json');
      expect(c.environment, BridgeEnvironment.dev);
      expect(c.getString('apiUrl'), 'http://localhost:8080');
    });
  });
}

class ApiSection {
  ApiSection(
      {required this.baseUrl, required this.timeoutMs, required this.retries});
  final String baseUrl;
  final int timeoutMs;
  final int retries;
}
