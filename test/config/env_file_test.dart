import 'package:modular_bridge/modular_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('parseEnvFile', () {
    test('parses KEY=VALUE pairs', () {
      final values = parseEnvFile('A=1\nB=two\n');
      expect(values, {'A': '1', 'B': 'two'});
    });

    test('skips blank lines and comments', () {
      final values = parseEnvFile('# comment\n\nA=1 # inline\n  # indented\nB=2\n');
      expect(values, {'A': '1', 'B': '2'});
    });

    test('supports export prefix', () {
      final values = parseEnvFile('export FOO=bar\n');
      expect(values['FOO'], 'bar');
    });

    test('strips matching single and double quotes', () {
      final values = parseEnvFile("A='hello world'\nB=\"x y\"\nC=''\n");
      expect(values['A'], 'hello world');
      expect(values['B'], 'x y');
      expect(values['C'], '');
    });

    test('keeps # inside quoted values', () {
      final values = parseEnvFile('A="has # hash"\nB=plain#hash\n');
      expect(values['A'], 'has # hash');
      // Unquoted values only strip comments preceded by whitespace.
      expect(values['B'], 'plain#hash');
    });

    test('throws FormatException on malformed lines', () {
      expect(() => parseEnvFile('NOEQUALS\n'), throwsFormatException);
      expect(() => parseEnvFile('=value\n'), throwsFormatException);
    });
  });

  group('BridgeConfig.fromEnvString', () {
    test('exposes parsed pairs as config values', () {
      final config = BridgeConfig.fromEnvString(
        'API_URL=https://api.example.com\nTIMEOUT_MS=5000\n',
        environment: BridgeEnvironment.dev,
      );
      addTearDown(config.dispose);

      expect(config.getString('API_URL'), 'https://api.example.com');
      expect(config.getInt('TIMEOUT_MS'), 5000);
      expect(config.environment, BridgeEnvironment.dev);
    });

    test('resolves environment from BRIDGE_ENV key', () {
      final config = BridgeConfig.fromEnvString(
        'BRIDGE_ENV=staging\nKEY=value\n',
      );
      addTearDown(config.dispose);
      expect(config.environment, BridgeEnvironment.staging);
    });

    test('environment parameter wins over file keys', () {
      final config = BridgeConfig.fromEnvString(
        'BRIDGE_ENV=prod\nKEY=value\n',
        environment: BridgeEnvironment.dev,
      );
      addTearDown(config.dispose);
      expect(config.environment, BridgeEnvironment.dev);
    });

    test('custom environmentKeys are honored', () {
      final config = BridgeConfig.fromEnvString(
        'MY_FLAVOR=production\nKEY=value\n',
        environmentKeys: const ['MY_FLAVOR'],
      );
      addTearDown(config.dispose);
      expect(config.environment, BridgeEnvironment.prod);
    });

    test('throws ArgumentError when no environment can be resolved', () {
      expect(
        () => BridgeConfig.fromEnvString('KEY=value\n'),
        throwsArgumentError,
      );
    });
  });

  group('BridgeConfig.fromEnvFile', () {
    test('loads through the provided loader', () async {
      final config = await BridgeConfig.fromEnvFile(
        'config/.env',
        loader: (path) async {
          expect(path, 'config/.env');
          return 'BRIDGE_ENV=dev\nANSWER=42\n';
        },
      );
      addTearDown(config.dispose);
      expect(config.environment, BridgeEnvironment.dev);
      expect(config.getInt('ANSWER'), 42);
    });
  });
}
