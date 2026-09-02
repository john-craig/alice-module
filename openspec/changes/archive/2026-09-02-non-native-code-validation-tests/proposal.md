## Why

The `modules/workspaces.nix` engine contains `mkNonNativeChecks`, which enforces several rules when `workspace.native = false` (blocking packages, source-based file entries, Nix-store MCP commands, and undeclared host binaries). These enforcement paths are exercised by checks in `flake.nix`, but those checks currently exist as inline `builtins.tryEval` assertions and ad-hoc `runCommand` scripts rather than a structured, spec-aligned test suite. Adding explicit tests for each scenario in the `workspace-native-option` spec makes coverage visible, traceable, and easier to extend.

## What Changes

- Add Nix `checks` entries in `flake.nix` for every scenario defined in the `workspace-native-option` spec that is not yet covered (or is only partially covered) by an existing check.
- Each new check is a named `pkgs.runCommand` (or `builtins.tryEval` + assert pattern) that maps 1-to-1 to a scenario in the spec.
- No changes to `modules/workspaces.nix` or `packages/alice/default.nix`; this change is test-only.

## Capabilities

### New Capabilities

- `non-native-code-validation-tests`: A set of Nix checks in `flake.nix` that provide complete scenario coverage for the `workspace-native-option` spec's non-native engine validation rules (Nix-evaluation-time checks only — CLI/runtime checks are out of scope for this change).

### Modified Capabilities

- `workspace-native-option`: The existing spec already covers the requirements; the scenarios drive the new tests but no spec text changes are needed.

## Impact

- `flake.nix`: new entries added to the `checks` attrset under the existing `forEachSystem` block.
- No production code changes.
- `nix flake check` run time will increase slightly due to the additional derivations.
