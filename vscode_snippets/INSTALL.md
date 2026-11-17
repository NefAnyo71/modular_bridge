# Installing Modular Bridge Snippets

Two ways to install — pick whichever fits your workflow.

---

## Option A — Snippet file (recommended, zero setup)

### 1. Download

Get `modular-bridge.code-snippets` from this repo:

```
vscode_snippets/modular-bridge.code-snippets
```

Or directly via raw URL:

```
https://raw.githubusercontent.com/NefAnyo71/modular_bridge/main/vscode_snippets/modular-bridge.code-snippets
```

### 2. Place the file

**Global install** (available in every Dart project) — copy the file into
your VS Code user snippets folder:

| OS | Path |
| --- | --- |
| Windows | `%APPDATA%\Code\User\snippets\` |
| macOS | `~/Library/Application Support/Code/User/snippets/` |
| Linux | `~/.config/Code/User/snippets/` |

**Project install** (only for one project) — copy it into:

```
<your-project>/.vscode/modular-bridge.code-snippets
```

### 3. Done

Open any `.dart` file and type `mb.` — the snippet list appears.
No restart required in most cases; if nothing shows up, reload the window
(`Ctrl+Shift+P` → `Developer: Reload Window`).

> The same steps apply to **Cursor**, **Windsurf**, and **VSCodium** —
> just use that editor's snippets folder instead of VS Code's.

---

## Option B — VSIX extension package

If you prefer a packaged extension (includes the icon and README):

### 1. Download

Grab `modular-bridge-snippets-<version>.vsix` from the
[`extension/`](extension/) folder or a GitHub Release.

### 2. Install

- **VS Code / Cursor / Windsurf**: `Ctrl+Shift+P` →
  `Extensions: Install from VSIX...` → select the `.vsix` file.
- Or drag & drop the `.vsix` onto the Extensions panel.

### 3. Done

Type `mb.` in a Dart file.

---

## Verifying it works

Type `mb.module` in a Dart file and press `Tab`. You should get a complete
`FeatureModule` skeleton with tabstops you can fill in.

## Updating

Re-download the file and overwrite the old one — snippet changes apply
immediately. To regenerate the snippets from the latest package source:

```bash
cd vscode_snippets
dart run generate_snippets.dart
```

## Snippet Manager (optional)

If you use the
[Snippet Manager](https://marketplace.visualstudio.com/items?itemName=vs-publisher-944125.snippet-manager)
extension, import directly from the raw URL above — no manual file copying.
