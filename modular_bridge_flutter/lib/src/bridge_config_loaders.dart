import 'package:flutter/services.dart' show rootBundle;
import 'package:modular_bridge/modular_bridge.dart';

/// Loads a [BridgeConfig] from a JSON asset bundled with the application.
///
/// Convenience wrapper around [BridgeConfig.fromAsset] that uses
/// `rootBundle.loadString` as the loader. See [BridgeConfig.fromJson] for
/// the expected document shape and for how the active environment is
/// resolved.
Future<BridgeConfig> loadBridgeConfigFromAsset(
  String assetPath, {
  BridgeEnvironment? environment,
}) {
  return BridgeConfig.fromAsset(
    assetPath,
    loader: rootBundle.loadString,
    environment: environment,
  );
}

/// Loads a [BridgeConfig] from a dotenv (`.env`) asset bundled with the
/// application.
///
/// Convenience wrapper around [BridgeConfig.fromEnvFile] that uses
/// `rootBundle.loadString` as the loader. See [BridgeConfig.fromEnvString]
/// for parsing rules and environment resolution.
Future<BridgeConfig> loadBridgeConfigFromEnvAsset(
  String assetPath, {
  BridgeEnvironment? environment,
  List<String> environmentKeys = BridgeConfig.envEnvironmentKeys,
}) {
  return BridgeConfig.fromEnvFile(
    assetPath,
    loader: rootBundle.loadString,
    environment: environment,
    environmentKeys: environmentKeys,
  );
}
