## Why

The current engine exposes a single `mkWorkspace pkgs name moduleFile` function that immediately binds to a Nix package set and returns a `writeShellApplication` derivation. This makes the workspace configuration object inseparable from a specific build system — consumers cannot evaluate, inspect, or extend a workspace without committing to a particular `pkgs`. It also provides no way to inject additional NixOS-style option declarations alongside the workspace config, limiting reuse and composability. Finally, there is no built-in way to inspect what a workspace configuration evaluates to, making debugging difficult.

## What Changes

- The engine in `modules/workspaces.nix` is refactored to expose two public entry points:
  - `mkWorkspaceConfig name moduleFile { extraModules? }` — system-independent; returns a **workspace configuration object** (`wsCfg`) with `.config`, `.override`, `.provision pkgs`, and `.print pkgs` attributes.
  - `mkWorkspace name moduleFile` — legacy convenience wrapper; still returns a `writeShellApplication` with `.override` and `.print` attached, bound to the same `pkgs`.
- A new `extraModules` parameter on `mkWorkspaceConfig` allows callers to inject NixOS-style modules into `lib.evalModules` alongside the workspace config block, enabling workspaces to declare and use options under custom namespaces (e.g. `workspace.gitTools.*`).
- A new `workspace-<name>-print` derivation is produced by `wsCfg.print pkgs` (and attached as `.print` on the legacy `mkWorkspace` return value). Running it writes the evaluated workspace configuration as a Nix expression to a caller-supplied output file.
- `flake.nix` gains two new system-independent outputs:
  - `workspaceConfigurations` — attrset of `wsCfg` objects, one per built-in example workspace.
  - `workspaceModules` — attrset of module file paths consumers can import.
- An example NixOS-style workspace module (`examples/modules/git-tools.nix`) demonstrates the `extraModules` pattern. It declares `workspace.gitTools.*` options and conditionally contributes rules, a skill, and packages via `lib.mkIf`.
- The `examples/workspace.nix` extended-workspace example is updated to use `.override` instead of manual attribute merging.
- `packages/alice/default.nix` is updated to call `engine.mkWorkspace` (the new attrset surface) instead of calling the engine as a function directly.

## Capabilities

### New Capabilities

- `workspace-config-object`: The `mkWorkspaceConfig` / `wsCfg` API — system-independent workspace configuration objects with `.config`, `.override`, `.provision`, and `.print`.
- `extra-modules`: The `extraModules` parameter enabling NixOS-style module injection into workspace evaluation.
- `workspace-print`: The `workspace-<name>-print` derivation that writes the evaluated configuration as a Nix expression.

### Modified Capabilities

<!-- No existing specs require delta changes; all three capabilities are new. -->

## Impact

- **`modules/workspaces.nix`**: Internal refactor into `buildWorkspaceConfig`, `buildProvisionDrv`, `buildPrintDrv`, `bindWorkspaceConfig`; public surface changes from a single function to an attrset `{ mkWorkspaceConfig, mkWorkspace }`. The `{ pkgs, flakeRoot }:` argument signature is unchanged.
- **`flake.nix`**: Adds `workspaceConfigurations`, `workspaceModules`, `lib.mkWorkspaceConfig`, `lib.mkWorkspaceConfigIn` outputs; `lib.mkWorkspace` and `lib.mkWorkspaceIn` are maintained as compatibility wrappers.
- **`packages/alice/default.nix`**: One-line fix: `engine wsName workspaceFile` → `engine.mkWorkspace wsName workspaceFile`.
- **`examples/modules/git-tools.nix`**: New file (demonstration module).
- **`examples/sample-workspace/default.nix`**: Updated to enable `workspace.gitTools`.
- **`examples/workspace.nix`**: Updated to use `.override` method.
- **Backwards compatibility**: `lib.mkWorkspace` and `lib.mkWorkspaceIn` remain available and return the same type as before (a `writeShellApplication` with `.override` and `.print` attached).
