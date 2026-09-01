## Why

Workspace configurations are evaluated at Nix time but today there is no way to inspect what a configuration resolves to without provisioning a directory. A `workspace-<name>-print` derivation addresses this by serialising the evaluated configuration as a Nix expression into the store at build time, so it can be written to any path at runtime with no further Nix evaluation.

## What Changes

- `modules/workspaces.nix` gains a `buildPrintDrv name cfg printPkgs` helper that produces a `writeShellApplication` named `workspace-<name>-print`. The script accepts a single output-file argument and installs the pre-baked config Nix expression to that path.
- `buildWorkspaceConfig` gains a `.print pkgs` attribute, alongside the existing `.provision pkgs`.
- `bindWorkspaceConfig` (the legacy `mkWorkspace` compatibility wrapper) gains a `.print` attribute bound to the same `pkgs`, alongside the existing `.override`.
- `flake.nix` exposes `workspace-<name>-print` entries under `packages.<system>` and `apps.<system>` for each built-in example workspace.
- A `workspace-sample-workspace-print` flake check verifies that the print derivation builds and that its output script runs successfully.

## Capabilities

### New Capabilities

<!-- workspace-print is already in main specs from the prior change's sync; this change implements it. -->

### Modified Capabilities

- `workspace-print`: Implementing the capability already specced in `openspec/specs/workspace-print/spec.md`.

## Impact

- **`modules/workspaces.nix`**: adds `buildPrintDrv`; threads `.print pkgs` through `buildWorkspaceConfig` and `.print` through `bindWorkspaceConfig`.
- **`flake.nix`**: adds `workspace-sample-workspace-print` and `workspace-extended-workspace-print` packages and apps; adds a `workspace-sample-workspace-print` check.
- No breaking changes; all existing outputs are unchanged.
