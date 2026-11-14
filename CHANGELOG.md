## 0.3.0

* **Module dependency protection**: `unregisterModule`/`unregisterModuleByName` now throw `BridgeModuleInUseException` when other registered modules depend on the target; pass `force: true` to override. Added `ModularBridge.moduleDependents(type)` for introspection.
* **Reactive config stream**: `BridgeConfig.onChanged` emits on every mutation (`set`, `setAll`, `remove`, `switchEnvironment`).
* **Persistent runtime overrides**: `BridgeConfig.set`/`setAll` values now survive environment switches; added `BridgeConfig.remove(key)` to restore underlying configured values. `switchEnvironment(runtimeOverrides:)` participates in the same override layer.
* Refactored `BridgeConfig` internals: removed duplicated missing-key boilerplate across typed getters via shared lookup/coercion helpers.
* `BridgeConfig` now guards against use-after-dispose: `set`, `setAll`, `remove`, and `switchEnvironment` throw `StateError` after `dispose()`, which is now idempotent and exposed via `isDisposed`.
* Added `BridgeConfig` coercion coverage (string/num/bool → `int`, `double`, `bool`, `Duration`, `Uri`) and unmodifiable `currentValues` snapshot guarantees.
* Added `ModularBridge.tryGetModule<M>()` as a nullable counterpart to `getModule<M>()`.
* Added `ModularBridge.registeredDependencies` for container introspection and debugging.
* Added `ModularBridge.resetInstance()` test helper to restore the global instance after `setMockInstance`.
* Added `BridgeEventBus.hasListeners<T>()` and event-type tracking on `BridgeSubscription`.
* Fixed `ModularBridgeProvider` to properly await cancellation of the previous environment subscription via `unawaited`.
* Expanded test suite to 55 tests, split into per-module files mirroring `lib/` structure with shared fixtures.
* Upgraded `flutter_lints` to ^6.0.0.

## 0.2.2

* Roll back module dependencies and subscriptions when registration or initialization fails.
* Propagate dependency construction errors from `tryGet` instead of silently returning `null`.
* Document optional dependency lookup and module initialization failure handling.

## 0.2.1

* Bug fixes and performance improvements.
* Updated documentation.

## 0.1.0

* Initial release of `modular_bridge`.
* High-performance, zero-dependency modular dependency injection container (`ModularBridge`).
* Isolated feature module definition with automatic subscription disposal (`FeatureModule`).
* Type-safe environment and flavor management with runtime hot-switch support (`BridgeConfig`).
* Decoupled cross-module domain event bus (`BridgeEventBus`).
* Seamless Flutter widget tree integration (`ModularBridgeScope`, `ModularBridgeProvider`, and `BuildContext` extensions).
* Single-line mock override capability for frictionless unit and integration testing.
