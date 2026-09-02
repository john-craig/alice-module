## Context

`buildWorkspaceConfig` in `modules/workspaces.nix` already returns `{ configBlock; config; override; provision; }`. The `.provision pkgs` method calls `buildProvisionDrv`, which mirrors the old single-pass derivation builder but accepts `provisionPkgs` separately from the module-level `pkgs`. The same pattern applies here: `buildPrintDrv name cfg printPkgs` builds a `writeShellApplication` that is system-specific (its `runtimeInputs` come from `printPkgs`) but whose payload — the serialised Nix expression — is computed at Nix eval time from `cfg`, the already-evaluated workspace options.

## Goals / Non-Goals

**Goals:**
- Implement `buildPrintDrv name cfg printPkgs` in `modules/workspaces.nix`.
- Add `.print pkgs` to the `buildWorkspaceConfig` return attrset.
- Add `.print` (bound to module-level `pkgs`) to the `bindWorkspaceConfig` derivation attrset.
- Expose `workspace-<name>-print` under `packages.<system>` and `apps.<system>` in `flake.nix`.
- Add a `workspace-sample-workspace-print` flake check.

**Non-Goals:**
- Changing the serialisation format (it uses `lib.generators.toPretty`; JSON is not supported).
- Exposing `workspace-print` for the `alice switch` CLI flow.
- Validating that the output file is syntactically valid Nix at runtime.

## Decisions

### Decision: serialisation with `lib.generators.toPretty`

**Chosen:** `lib.generators.toPretty {} { … }` produces a human-readable Nix expression. The config attrset is constructed by hand — file entries normalise `source` to `builtins.toString` (a string), packages to their `lib.getBin` store-path string.

**Alternatives considered:** `builtins.toJSON`. Rejected — JSON cannot represent Nix paths and the round-trip is lossy. `lib.generators.toPretty` produces something a user can read and paste back into a workspace file.

### Decision: the serialised expression is baked into the store at build time

The `printPkgs.writeText "workspace-<name>-config.nix" (lib.generators.toPretty {} …)` call happens inside `buildPrintDrv`, which executes during `nix build`. The resulting shell script simply copies that store path to the caller-supplied output file using `install`. No Nix evaluation occurs at runtime.

### Decision: `.print` on `bindWorkspaceConfig` result is a derivation, not a function

`mkWorkspace` already eagerly calls `.provision` and attaches `.override` to the resulting derivation. `.print` follows the same pattern — it is `wsCfg.print boundPkgs` attached directly, so `drv.print` is the `workspace-<name>-print` derivation, not a function.

## Risks / Trade-offs

- **Risk: toPretty output is not round-trippable** — the printed config is for human inspection, not for `import`. Store paths appear as strings, so you cannot re-import the file as a workspace module. → Acceptable; the use case is inspection and debugging, not re-import.
- **Risk: large workspaces produce large store texts** — `toPretty` can generate verbose output for workspaces with many files or large inline text. → Acceptable for now; the store deduplicates identical content.

## Open Questions

None.
