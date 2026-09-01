# Extra Modules Specification

## Purpose
Defines how alice-module workspaces can be extended with additional NixOS-style modules via the `extraModules` argument to `mkWorkspaceConfig`, enabling third-party and project-specific option namespaces.


## Requirements

### Requirement: mkWorkspaceConfig accepts an extraModules list
`mkWorkspaceConfig name moduleFile { extraModules }` SHALL accept an `extraModules` list of NixOS-style module paths or inline module functions. Each entry SHALL be passed to `lib.evalModules` alongside `workspaceOptions` and the workspace config block. The `pkgs` attrset SHALL be made available to extra modules via `_module.args`.

#### Scenario: extraModules entries can declare options under a custom namespace
- **WHEN** an extra module declares `options.workspace.myTool.enable` as a `lib.types.bool`
- **THEN** the workspace config block MAY set `workspace.myTool.enable = true` without an evaluation error

#### Scenario: extraModules entries receive pkgs via _module.args
- **WHEN** an extra module signature is `{ pkgs, lib, config, ... }:`
- **THEN** `pkgs` SHALL be the same attrset supplied to the engine import, available for referencing packages

#### Scenario: extra module config is contributed via lib.mkIf
- **WHEN** an extra module sets `workspace.bob.rules."extra.md" = lib.mkIf config.workspace.myTool.enable "…"`
- **THEN** the rule SHALL appear in `wsCfg.config.bob.rules` only when `workspace.myTool.enable = true`

#### Scenario: extraModules = [] produces no change
- **WHEN** `mkWorkspaceConfig` is called with `{ extraModules = []; }`
- **THEN** evaluation SHALL produce the same result as calling without the `extraModules` key

### Requirement: extraModules are preserved across .override
When `wsCfg.override overrideFn` is called on a `wsCfg` built with `extraModules`, the resulting `wsCfg` SHALL be evaluated with the same `extraModules` list.

#### Scenario: overridden wsCfg retains injected module options
- **WHEN** `wsCfg` has `extraModules = [ someModule ]` and `.override` is called
- **THEN** `someModule`'s option declarations SHALL still be available in the overridden config evaluation

### Requirement: lib.mkWorkspaceConfig flake output accepts extraModules
The flake's `lib.mkWorkspaceConfig name moduleFile` SHALL return a function `{ extraModules? }: wsCfg` so that downstream flakes can inject their own modules.

#### Scenario: downstream flake injects an extraModule
- **WHEN** a downstream flake calls `alice.lib.mkWorkspaceConfig "ws" ./ws.nix { extraModules = [ ./my-module.nix ]; }`
- **THEN** `./my-module.nix`'s option declarations SHALL be available during workspace evaluation
