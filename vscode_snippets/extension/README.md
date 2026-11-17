# Modular Bridge Snippets

VS Code snippets for [`modular_bridge`](https://pub.dev/packages/modular_bridge) —
a zero-dependency DI container, module system, type-safe config and event bus
for modular Dart/Flutter apps.

## Install

Search **"Modular Bridge Snippets"** in the Extensions view (prefix `mb.`).

## Usage

In any Dart file, type `mb.` to see all snippets:

| Prefix | Expands to |
| --- | --- |
| `mb.module` | Full `FeatureModule` skeleton |
| `mb.module.subscribe` | Auto-disposed event subscription inside a module |
| `mb.event` | `BridgeEvent` subclass |
| `mb.config` | `BridgeConfig` with dev/staging/prod environments |
| `mb.register.*` | `registerLazySingleton`, `registerAsyncSingleton` + retry policy, `registerFactoryParam`, `registerSingletonWithDependencies`, ... |
| `mb.get` / `mb.getasync` / `mb.tryget` / `mb.getall` | Dependency resolution |
| `mb.scope` / `mb.scope.push` | `BridgeScope` / `pushNewScope` request scoping |
| `mb.override` | 1-line mock override for tests |
| `mb.allready` / `mb.warmup` / `mb.modulesready` | Startup orchestration |
| `mb.new.*` | Instantiate public classes (events, exceptions, config, ...) |
| `mb.<apiName>` | Auto-generated call snippets for every public API member |

Placeholders use `${1:default}` tabstops and `${1|a,b,c|}` choice lists.

## Regenerating

Snippets are generated from the package source by
[`generate_snippets.dart`](../generate_snippets.dart):

```bash
cd vscode_snippets
dart run generate_snippets.dart
cp modular-bridge.code-snippets extension/snippets/
```

Bump `version` in `package.json` before publishing.
