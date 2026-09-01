## Why

Workspace modules need a way to opt out of native (host-OS) toolchain usage — for example when provisioning a workspace that must run inside a container or a restricted environment where the Nix store is not present. Today there is no workspace-level flag to express this, alice has no way to override it from the command line, and the engine places no restrictions on which options are valid in such environments.

## What Changes

- A new boolean option `workspace.native` (default `true`) is added to the workspace module schema in `modules/workspaces.nix`.
- When `workspace.native = false`, the engine enforces at Nix evaluation time that no Nix store paths are referenced:
  - `workspace.packages` must be empty.
  - All `workspace.file`, `workspace.bob.rules`, and `workspace.bob.skills` entries must use `text` (not `source`).
  - All MCP server `command` values must not be Nix store paths (i.e. must not start with `/nix/store/`). An MCP server using a host binary is permitted only if that binary name is declared in `workspace.assertHostBinaries` and confirmed present at provision time.
- A new option `workspace.assertHostBinaries` (list of strings, default `[]`) declares host binaries the workspace depends on. At `alice switch` time, every listed name is checked against a host binaries manifest file; any name not present in the manifest is a hard error before provisioning begins.
- When `native = true` (the default), a non-empty `assertHostBinaries` list produces a warning but is otherwise ignored — native mode assumes the host has everything it needs.
- `alice switch` gains a `--no-native` / `--native` pair of flags that override `workspace.native` at invocation time.
- `alice switch` gains a `--host-binaries <file>` flag pointing to the host binaries manifest (default: `.alice/host-binaries` in the target directory).
- The `init` template in `alice switch` is updated to show `workspace.native` and `workspace.assertHostBinaries` as commented-out options.

## Capabilities

### New Capabilities

- `workspace-native-option`: Declarative `workspace.native` boolean, non-native enforcement (Nix assertions for packages/files, runtime check for host-binary MCP servers), `workspace.assertHostBinaries` declaration, host binaries manifest validation, and corresponding `alice switch` CLI flags.

### Modified Capabilities

<!-- No existing spec files to delta. -->

## Impact

- **`modules/workspaces.nix`**: adds `workspace.native` and `workspace.assertHostBinaries` option definitions; adds `config.assertions` that fire when `native = false` and a store-path-dependent option is set.
- **`packages/alice/default.nix`**: adds `--no-native` / `--native` / `--host-binaries` argument parsing in `cmd_switch`; updates the embedded `alice-build-workspace.nix` expression to accept and forward `wsNative`; adds the new options to the `alice init` template; adds the runtime host-binaries manifest check.
- No breaking changes; existing workspace modules that omit `workspace.native` continue to behave as before (native = true, no restrictions).
