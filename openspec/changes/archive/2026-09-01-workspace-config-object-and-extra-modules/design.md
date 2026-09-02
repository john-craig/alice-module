## Context

`modules/workspaces.nix` currently exports a single curried function:

```
{ pkgs, flakeRoot }: name: moduleFile: <writeShellApplication>
```

The entire pipeline — option evaluation, file path resolution, and derivation construction — happens in one pass bound to a specific `pkgs`. This design has two consequences:

1. **No system-independent evaluation.** To get anything from a workspace (even just its `config` attrset), a caller must supply a `pkgs`, which means committing to a Nix system. The `workspaceConfigurations` flake output pattern (system-agnostic objects) is impossible.
2. **No module extension point.** `lib.evalModules` only receives `workspaceOptions` and the user's config block. There is no way to inject additional option declarations (e.g. `workspace.gitTools.*`) without forking the engine.

The refactor separates concerns:

- **Config evaluation** (`buildWorkspaceConfig`) — system-independent; evaluates `lib.evalModules`, returns a `wsCfg` object.
- **Derivation building** (`buildProvisionDrv`, `buildPrintDrv`) — system-dependent; called lazily via `wsCfg.provision pkgs` / `wsCfg.print pkgs`.
- **Legacy binding** (`bindWorkspaceConfig`) — wraps `buildWorkspaceConfig` and eagerly calls `.provision` to reproduce the old return type.

## Goals / Non-Goals

**Goals:**
- Expose `mkWorkspaceConfig name moduleFile { extraModules? }` returning a system-independent `wsCfg` object with `.config`, `.override`, `.provision pkgs`, and `.print pkgs`.
- Support `extraModules`: an optional list of NixOS-style module paths/functions injected into `lib.evalModules` alongside `workspaceOptions` and the config block, with `pkgs` available via `_module.args`.
- Expose `mkWorkspace name moduleFile` as a compatibility wrapper returning the same `writeShellApplication` type as before, with `.override` and `.print` attached.
- Add a `workspace-<name>-print` shell application that writes the evaluated config as a Nix expression to a caller-supplied output path.
- Add `workspaceConfigurations` and `workspaceModules` system-independent flake outputs.
- Fix `packages/alice/default.nix` to call `engine.mkWorkspace` (not `engine` as a function).

**Non-Goals:**
- Changing the workspace module file format (`{ pkgs, workspaces, utils }:` → `{ workspaces."name" = ...; }`).
- Changing the provisioning script's runtime behaviour (the generated shell code is identical).
- Changing the `{ pkgs, flakeRoot }:` outer argument signature of `modules/workspaces.nix`.
- Changing `alice switch` CLI behaviour.

## Decisions

### Decision: `buildWorkspaceConfig` takes `pkgs` from the module-level closure, not from the caller

The engine file is `import`-ed with `{ pkgs, flakeRoot }` at the top. `buildWorkspaceConfig` captures those bindings. The `pkgs` argument on `.provision pkgs` / `.print pkgs` is used *only* inside `buildProvisionDrv` / `buildPrintDrv` for `writeShellApplication`, `writeText`, and `coreutils`. Option type-checking inside `lib.evalModules` still uses the closure-level `pkgs`.

**Rationale:** Separating evaluation `pkgs` (for types) from build `pkgs` (for derivations) would require threading two `pkgs` through every layer. The closure `pkgs` is already there; the per-call `pkgs` is only needed for build-time artefacts, not for option evaluation.

**Known limitation:** If a consumer imports the engine with `pkgs` for system A but calls `.provision` with `pkgs` for system B, the option type-checking used system A's `pkgs` while the derivation was built for system B. In practice this is not an issue because option types do not depend on the host system, but it is worth documenting.

### Decision: `extraModules` entries receive `pkgs` via `_module.args`

NixOS modules that need `pkgs` (e.g. to reference `pkgs.git`) can declare `{ pkgs, lib, config, ... }:` in their module signature. The engine injects `{ _module.args = { inherit pkgs; }; }` as the last module in the list so that the closure `pkgs` flows through.

**Alternatives considered:** Requiring extraModules to be pure functions of `{ lib, config, ... }` with no `pkgs`. Rejected — modules that add packages to `workspace.packages` inherently need `pkgs`.

### Decision: `.override` takes a raw config-block transformation function

`wsCfg.override (cfg: cfg // { workspace.packages = cfg.workspace.packages ++ [ … ]; })` receives the *raw* (pre-evaluation) config block attrset and returns a new one. The new block is re-evaluated with the same `extraModules`.

**Alternatives considered:** Passing the *evaluated* `cfg` to the function. Rejected — evaluated attrsets contain type-wrapper metadata that is not round-trippable as a raw config block. Using the raw block keeps the override pattern identical to what downstream workspace files already do manually.

### Decision: `wsCfg.configBlock` is exposed

The raw config block is attached as `wsCfg.configBlock` so that workspace module files that use `.override` can re-export the result:

```nix
workspaces."extended" = extended.configBlock;
```

This lets `mkWorkspace`/`mkWorkspaceConfig` import `examples/workspace.nix` and extract the config block in the same way as any other module file.

### Decision: `workspace-<name>-print` uses `lib.generators.toPretty`

The print derivation writes a Nix-expression representation using `lib.generators.toPretty {}`. Store paths in `packages` and `source` entries are serialised as strings via `builtins.toString`.

**Alternatives considered:** JSON output. Rejected — `builtins.toJSON` cannot represent Nix paths; round-tripping through `toString` loses type information. A Nix-expression format is more useful for inspection and copy-paste into configs.

## Risks / Trade-offs

- **Risk: `_module.args` injection order** — if an `extraModules` entry also injects `_module.args`, the last writer wins. The engine appends `{ _module.args = { inherit pkgs; }; }` last, so the engine's `pkgs` always wins. If a consumer's module needs a *different* pkgs for some reason, it cannot override it. → Acceptable; `pkgs` in modules should come from the engine.
- **Risk: `.override` re-evaluates with raw block** — if the raw config block contains expression-level Nix that cannot be trivially round-tripped (e.g. `builtins.readFile` calls), the override closure operates on already-evaluated string results. → Not a problem in practice; the config block is an attrset of option assignments, not arbitrary Nix programs.
- **Risk: backwards compatibility surface** — `lib.mkWorkspace` / `lib.mkWorkspaceIn` must continue returning a derivation (not a `wsCfg` object). The `bindWorkspaceConfig` helper enforces this. → Tested by existing `flake check` derivations.

## Open Questions

None — the branch implementation is complete and the design is derived from it.
