# modular_bridge_example

A Flutter showcase for [`modular_bridge`](https://pub.dev/packages/modular_bridge)
built with **zero external state-management dependencies** — every reactive
surface is a `ChangeNotifier` resolved from the DI container or plain
`StatefulWidget` state.

## What's demonstrated

- **Type-safe config** loaded from `assets/config.json`, environment
  hot-switching, `registerConfigBinding` auto-rebuild of `ApiClient`.
- **Feature modules** (`Core`, `Analytics`, `Auth`, `Home`, `Cart`) with
  `dependencies`, `healthCheck`, and `warmup` hooks; `registerModules(parallel: true)`.
- **`Lazy<T>`** breaking the `AuthService` ↔ `UserProfileService` circular
  dependency.
- **Async lifecycles**: eager `SessionStore` with `BridgeRetryPolicy`,
  resolved via `callAsync`.
- **Event bus**: module-owned `subscribe` (auto-disposed), live console,
  event interceptor veto, `totalPublished`.
- **Scopes**: `pushNewScopeAsync` request scope with scoped config overrides.
- **Inspector**: resolution metrics, module load/unload, health check with
  durations, `diagnosticsReport()`, `dependencyEventHistory()`.
- **1-line overrides**: mock `AuthService` swap via `bridge.override`.

## Run

```sh
flutter pub get
flutter run
```
