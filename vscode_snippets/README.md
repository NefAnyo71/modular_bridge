# Modular Bridge — VS Code Snippets

> **End users:** see [INSTALL.md](INSTALL.md) for manual installation
> instructions (snippet file or `.vsix` package).

Generates `modular-bridge.code-snippets` for VS Code from the public API of
`package:modular_bridge`.

## Usage

```bash
cd vscode_snippets
dart run generate_snippets.dart            # writes modular-bridge.code-snippets here
dart run generate_snippets.dart --out <path>
```

Then copy `modular-bridge.code-snippets` into your project's `.vscode/`
folder (or `%APPDATA%\Code\User\snippets\` for global use).

## How it works

- **Curated templates** (`mb.module`, `mb.config`, `mb.register.*`,
  `mb.event.*`, `mb.scope`, ...) — hand-written, idiomatic snippets for the
  most common workflows. These live in the `curated` map at the top of
  `generate_snippets.dart`.
- **Auto-generated call sites** — the script scans `lib/**/*.dart`, extracts
  public method/getter signatures (including named parameters and defaults),
  and emits `mb.<name>` snippets with sensible receivers
  (`bridge.`, `scope.`, `config.`, `bridge.eventBus.`, `ModularBridge.`,
  `BridgeConfig.`, ...).
- **Class snippets** — `mb.new.<ClassName>` for every concrete public class
  (events, exceptions, config, metrics, ...).

Re-run the generator after API changes; curated snippets are never
overwritten by auto-generation.

## Snippet conventions

| Prefix family | Meaning |
| --- | --- |
| `mb.module*` | `FeatureModule` skeletons and lifecycle hooks |
| `mb.event*` | `BridgeEvent` subclasses and bus publish/subscribe |
| `mb.config*` | `BridgeConfig` setup, typed reads, hot-switch |
| `mb.register.*` | DI registration helpers (pick the lifecycle you need) |
| `mb.get*` / `mb.tryget` / `mb.getall` | Dependency resolution |
| `mb.scope*` | `BridgeScope` / `pushNewScope` request scoping |
| `mb.new.*` | Instantiate a public class |
| `mb.<apiName>` | Auto-generated call snippet for any public API member |
