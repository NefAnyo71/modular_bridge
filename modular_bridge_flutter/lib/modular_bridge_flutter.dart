/// Flutter integration layer for `modular_bridge`.
///
/// This package re-exports the pure-Dart core (`package:modular_bridge`) and
/// adds the Flutter-facing pieces that require the Flutter SDK:
///
/// - [ModularBridgeScope] / [ModularBridgeProvider] — widget-tree DI scoping
///   and environment hot-switch rebuilds.
/// - `BuildContext` extensions (`context.get`, `context.tryGet`,
///   `context.config`, `context.publish`).
/// - [ModularBridgeInspector] — read-only DevTools-style inspector widget.
/// - Asset/dotenv loaders backed by `rootBundle`
///   ([loadBridgeConfigFromAsset], [loadBridgeConfigFromEnvAsset]).
library;

export 'package:modular_bridge/modular_bridge.dart';

export 'src/bridge_config_loaders.dart'
    show loadBridgeConfigFromAsset, loadBridgeConfigFromEnvAsset;
export 'src/modular_bridge_extensions.dart';
export 'src/modular_bridge_inspector.dart' show ModularBridgeInspector;
export 'src/modular_bridge_scope.dart'
    show ModularBridgeProvider, ModularBridgeScope;
