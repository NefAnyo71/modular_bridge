# Migrating from `get_it` to `modular_bridge`

`modular_bridge` covers the full `get_it` API surface and adds modules, a typed event bus, environment-aware configuration, hierarchical scopes, and diagnostics — all with zero external dependencies.

## Cheat sheet

| `get_it` | `modular_bridge` |
|---|---|
| `GetIt.instance` / `GetIt.I` | `ModularBridge.instance` / `ModularBridge.I` |
| `getIt<T>()` | `bridge.get<T>()` or `bridge<T>()` |
| `getIt.get<T>()` | `bridge.get<T>()` |
| `getIt.isRegistered<T>()` | `bridge.isRegistered<T>()` |
| `getIt.tryGet<T>()` | `bridge.tryGet<T>()` |
| `getIt.registerSingleton<T>(instance)` | `bridge.registerSingleton<T>(instance)` |
| `getIt.registerLazySingleton<T>(factory)` | `bridge.registerLazySingleton<T>(factory)` |
| `getIt.registerFactory<T>(factory)` | `bridge.registerFactory<T>(factory)` |
| `getIt.registerSingletonAsync<T>(factory)` | `bridge.registerSingletonAsync<T>(factory)` |
| `getIt.registerLazySingletonAsync<T>(factory)` | `bridge.registerLazySingletonAsync<T>(factory)` |
| `getIt.registerFactoryAsync<T>(factory)` | `bridge.registerFactoryAsync<T>(factory)` |
| `getIt.registerFactoryParam<T,P1,P2>` (+`Cached`) | `bridge.registerFactoryParam` / `registerCachedFactoryParam` |
| `getIt.getAsync<T>()` | `bridge.getAsync<T>()` |
| `getIt.allReady({timeout})` | `bridge.allReady(timeout: ...)` |
| `getIt.allReadySync()` | `bridge.allReadySync()` |
| `getIt.isReady<T>()` / `isReadySync` | `bridge.isReady<T>()` / `isReadySync<T>()` |
| `getIt.signalReady(instance)` | `bridge.signalReady(instance)` |
| `signalsReady: true` | `signalsReady: true` or implement `WillSignalReady` |
| `getIt.registerSingletonWithDependencies` | `bridge.registerSingletonWithDependencies` |
| `dependsOn: [...]` | `dependsOn: [DependencyKey(T), DependencyKey(T, 'name')]` |
| `getIt.pushNewScope(...)` | `bridge.pushNewScope(...)` |
| `getIt.popScope()` | `await bridge.popScope()` |
| `getIt.dropScope(name)` | `await bridge.dropScope(name)` |
| `getIt.popScopesTill(name)` | `await bridge.popScopesTill(name)` |
| `getIt.onScopeChanged` | `bridge.onScopeChanged` |
| `getIt.resetScope()` | `await bridge.resetScope()` |
| `getIt.resetLazySingleton<T>()` | `await bridge.resetLazySingleton<T>()` |
| `getIt.resetLazySingletons()` | `await bridge.resetLazySingletons()` |
| `getIt.allowReassignment` | `bridge.allowReassignment` |
| `instance is Disposable` | `instance is Disposable` (same contract) |
| `getIt.unregister<T>()` | `await bridge.unregister<T>()` |
| `GetIt.asNewInstance()` | `ModularBridge.createIsolated()` |

## Key differences

- **`dependsOn` uses `DependencyKey`** instead of bare `Type`s so named registrations can be expressed: `DependencyKey(AuthRepository, 'primary')`.
- **Async is first-class**: `registerDependencies` on modules may be `async`, `unregister`/`dispose`/`reset` return `Future`s you should `await`.
- **Scopes are objects too**: `bridge.createScope()` gives you an explicit `BridgeScope` you can pass around — useful for per-request Flutter widgets (`ModularBridgeScope`).
- **Modules own their registrations**: dependencies registered inside `FeatureModule.registerDependencies` are tracked per-module and rolled back automatically on failure.
- **Config is reactive**: `registerConfigBinding` re-decodes config keys into DI registrations on every environment switch or `set`.

## Minimal example

```dart
final bridge = ModularBridge.instance;

await bridge.registerModules([
  CoreModule(),
  AuthModule(),
  ShopModule(),
]);

await bridge.allReady(timeout: const Duration(seconds: 10));
```

See the [README](README.md) for the full API reference.
