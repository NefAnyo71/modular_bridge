## 0.1.0

* Initial release of the Flutter companion package for `modular_bridge`.
* `ModularBridgeScope` / `ModularBridgeProvider`: widget-tree DI scoping with automatic rebuilds on environment hot-switch.
* `BuildContext` extensions: `context.bridge`, `context.get<T>()`, `context.tryGet<T>()`, `context.config`, `context.publish(event)`.
* `ModularBridgeInspector`: read-only DevTools-style widget showing registrations, modules, scopes, resolution metrics, a module health-check action, and a live dependency-event feed.
* Config loaders backed by `rootBundle`: `loadBridgeConfigFromAsset` (JSON) and `loadBridgeConfigFromEnvAsset` (dotenv).
* Re-exports the entire `package:modular_bridge` core API.
