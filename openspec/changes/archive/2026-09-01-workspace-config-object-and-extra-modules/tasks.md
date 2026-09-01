## 1. Engine refactor — modules/workspaces.nix

- [ ] 1.1 Extract the MCP server JSON rendering logic from the inline `lib.mapAttrs` into a standalone `mkMcpServerJson` helper function.
- [ ] 1.2 Extract `buildProvisionDrv name cfg provisionPkgs` — the derivation-building code that produces `workspace-<name>` — into a dedicated let binding, accepting `provisionPkgs` instead of the module-level `pkgs`.
- [ ] 1.3 Implement `buildPrintDrv name cfg printPkgs` that produces the `workspace-<name>-print` derivation using `lib.generators.toPretty` to serialise the evaluated config, with store paths stringified via `builtins.toString`.
- [ ] 1.4 Implement `buildWorkspaceConfig name configBlock extraModules` returning `{ configBlock; config; override; provision; print; }`.
- [ ] 1.5 Implement `bindWorkspaceConfig name configBlock extraModules boundPkgs` that eagerly calls `.provision` and attaches `.override` and `.print` for the legacy return type.
- [ ] 1.6 Change the module return value from a curried function to an attrset `{ mkWorkspaceConfig; mkWorkspace; }`.
- [ ] 1.7 Implement `mkWorkspaceConfig name moduleFile { extraModules ? [] }` using `buildWorkspaceConfig`.
- [ ] 1.8 Implement `mkWorkspace name moduleFile` using `bindWorkspaceConfig` (passes `[]` for extraModules, uses module-level `pkgs`).
- [ ] 1.9 Inject `{ _module.args = { inherit pkgs; }; }` as the last module in the `lib.evalModules` call inside `buildWorkspaceConfig` so extra modules can receive `pkgs`.

## 2. flake.nix — new outputs and updated wiring

- [ ] 2.1 Add `lib.mkWorkspaceConfig = name: moduleFile: opts: engine.mkWorkspaceConfig name moduleFile opts;` flake output (using `builtins.currentSystem` for option evaluation).
- [ ] 2.2 Add `lib.mkWorkspaceConfigIn = pkgs: flakeRoot: name: moduleFile: (import ./modules/workspaces.nix { … }).mkWorkspaceConfig name moduleFile;`.
- [ ] 2.3 Update `lib.mkWorkspace pkgs` to return `engine.mkWorkspace` (not `engine` directly).
- [ ] 2.4 Update `lib.mkWorkspaceIn pkgs flakeRoot` to return `(import ./modules/workspaces.nix { … }).mkWorkspace`.
- [ ] 2.5 Add `workspaceModules` attrset output with at minimum `workspaces = ./modules/workspaces.nix` and `git-tools = ./examples/modules/git-tools.nix`.
- [ ] 2.6 Add `workspaceConfigurations` attrset output with `sample-workspace` and `extended-workspace` entries built via `mkWorkspaceConfig`.
- [ ] 2.7 In the per-system `packages` output, derive workspace derivations from `wsCfg.provision pkgs` and add `workspace-<name>-print` entries from `wsCfg.print pkgs`.
- [ ] 2.8 In the per-system `apps` output, add `workspace-<name>-print` app entries.
- [ ] 2.9 Update `flake check` derivations to expect `workspace-sample-workspace-print` and any new outputs.

## 3. packages/alice/default.nix

- [ ] 3.1 Update `buildWorkspaceExpr` to call `engine.mkWorkspace wsName workspaceFile` instead of `engine wsName workspaceFile`.

## 4. examples

- [ ] 4.1 Create `examples/modules/git-tools.nix` — a NixOS-style module declaring `workspace.gitTools.{enable,rules,skill,packages}` options and contributing rules, skill, and packages via `lib.mkIf`.
- [ ] 4.2 Update `examples/sample-workspace/default.nix` to set `workspace.gitTools.enable = true` (enabled by the injected git-tools module).
- [ ] 4.3 Update `examples/workspace.nix` to use `engine.mkWorkspaceConfig` + `.override` instead of manual config-block merging; re-export `extended.configBlock` under `workspaces."extended-workspace"`.

## 5. Validation

- [x] 5.1 Run `nix build .#alice` — confirm no errors.
- [x] 5.2 Run `nix build .#workspace-sample-workspace` — confirm it builds via `wsCfg.provision pkgs`.
- [x] 5.3 Run `nix build .#workspace-extended-workspace` — confirm it still builds with the `.override` pattern.
- [x] 5.4 Run `nix flake check` — confirm all existing checks pass.
- [ ] 5.5 Manually verify: run `workspace-sample-workspace-print /tmp/sample.nix` and confirm the output file is well-formed Nix. (Deferred — workspace-print scope not yet implemented.)
