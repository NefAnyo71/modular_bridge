# modular_bridge_flutter

Flutter integration layer for [`modular_bridge`](https://pub.dev/packages/modular_bridge) — the pure-Dart modular dependency injection, configuration, and event-bus framework.

This package re-exports the entire `package:modular_bridge` core API and adds the pieces that require the Flutter SDK:

## Features

- **`ModularBridgeScope` / `ModularBridgeProvider`** — provide a `ModularBridge` container down the widget tree; the provider rebuilds the subtree automatically on environment hot-switches.
- **`BuildContext` extensions** — `context.bridge`, `context.get<T>()`, `context.tryGet<T>()`, `context.config`, and `context.publish(event)` for ergonomic dependency access inside widgets.
- **`ModularBridgeInspector`** — a read-only DevTools-style widget that live-displays registrations, modules, scopes, resolution metrics, a module health-check action, and a rolling feed of dependency registration events.
- **Asset & dotenv config loaders** — `loadBridgeConfigFromAsset` and `loadBridgeConfigFromEnvAsset` wrap `rootBundle` for `BridgeConfig.fromAsset` / `BridgeConfig.fromEnvFile`.

## Install

```yaml
dependencies:
  modular_bridge: ^0.9.0
  modular_bridge_flutter: ^0.1.0
```

```dart
import 'package:modular_bridge_flutter/modular_bridge_flutter.dart';
```

## Example

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await loadBridgeConfigFromAsset('assets/config.json');
  ModularBridge.I.setConfig(config);
  await ModularBridge.I.registerModules([CoreModule(), AuthModule()]);

  runApp(
    const ModularBridgeProvider(child: MyApp()),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = context.get<AuthRepository>();
    return Text('Env: ${context.config.environment.name}');
  }
}
```

See the [modular_bridge](https://pub.dev/packages/modular_bridge) package for the full core API, module system, event bus, and configuration documentation.
