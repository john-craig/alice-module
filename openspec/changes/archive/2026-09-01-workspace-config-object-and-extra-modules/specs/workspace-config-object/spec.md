## ADDED Requirements

### Requirement: mkWorkspaceConfig returns a system-independent configuration object
The engine SHALL expose a `mkWorkspaceConfig name moduleFile { extraModules? }` function that evaluates the workspace module file with `lib.evalModules` and returns a workspace configuration object (`wsCfg`) without requiring a system-specific `pkgs` at call time. The `pkgs` used for option type evaluation SHALL be the one supplied to the engine import (`{ pkgs, flakeRoot }:`).

#### Scenario: basic call returns a wsCfg with .config
- **WHEN** `engine.mkWorkspaceConfig "my-ws" ./workspace.nix {}` is called
- **THEN** the return value SHALL have a `config` attribute containing the evaluated `workspace.*` options attrset

#### Scenario: extraModules defaults to empty list
- **WHEN** `mkWorkspaceConfig` is called with `{}` (no `extraModules` key)
- **THEN** evaluation SHALL succeed and behave identically to calling with `{ extraModules = []; }`

### Requirement: wsCfg.provision pkgs returns a provisioning derivation
`wsCfg.provision pkgs` SHALL return a `writeShellApplication` derivation named `workspace-<name>` that, when run against a target directory, provisions it identically to the output of the legacy `mkWorkspace` function.

#### Scenario: provision produces workspace-<name> derivation
- **WHEN** `wsCfg.provision pkgs` is called with a valid package set
- **THEN** the return value SHALL be a derivation whose `name` attribute equals `"workspace-<name>"`

#### Scenario: provision output is idempotent with mkWorkspace
- **WHEN** the same workspace module is built via `mkWorkspaceConfig … .provision pkgs` and via `mkWorkspace pkgs`
- **THEN** the resulting provisioning scripts SHALL produce identical file trees when run

### Requirement: wsCfg.print pkgs returns a Nix-expression print derivation
`wsCfg.print pkgs` SHALL return a `writeShellApplication` derivation named `workspace-<name>-print`. When run with a single output-file argument, it SHALL write the evaluated workspace configuration as a Nix expression to that file.

#### Scenario: print derivation is named correctly
- **WHEN** `wsCfg.print pkgs` is called
- **THEN** the return value SHALL be a derivation whose `name` attribute equals `"workspace-<name>-print"`

#### Scenario: print script writes a file
- **WHEN** the `workspace-<name>-print` script is run with a path argument
- **THEN** a file at that path SHALL be created containing a Nix expression representation of the workspace configuration

#### Scenario: print script requires exactly one argument
- **WHEN** `workspace-<name>-print` is run with zero or more than one argument
- **THEN** the script SHALL exit with a non-zero status and print a usage message

### Requirement: wsCfg.override returns a new wsCfg with transformed config block
`wsCfg.override overrideFn` SHALL accept a function that receives the raw config block attrset and returns a new raw config block attrset. It SHALL return a new `wsCfg` produced by re-evaluating the returned config block with the same `extraModules`.

#### Scenario: override produces an independent wsCfg
- **WHEN** `wsCfg.override (cfg: cfg // { workspace.file."extra.txt" = "hello"; })` is called
- **THEN** the resulting `wsCfg.config.file` SHALL contain `"extra.txt"` and the original `wsCfg.config.file` SHALL NOT be modified

#### Scenario: override preserves extraModules
- **WHEN** a `wsCfg` was created with `extraModules = [ someModule ]` and `.override` is called on it
- **THEN** the returned `wsCfg` SHALL also evaluate with `someModule` in scope

### Requirement: wsCfg.configBlock exposes the raw config block
`wsCfg.configBlock` SHALL expose the raw config block attrset (as passed to `buildWorkspaceConfig`), enabling workspace module files that use `.override` to re-export the result under a new name.

#### Scenario: configBlock is re-importable
- **WHEN** a workspace module file sets `workspaces."new-name" = extended.configBlock`
- **THEN** `mkWorkspace`/`mkWorkspaceConfig` importing that file SHALL evaluate the overridden config under `"new-name"` successfully

### Requirement: mkWorkspace remains a compatibility wrapper
`engine.mkWorkspace name moduleFile` SHALL return a `writeShellApplication` derivation (identical type to the pre-refactor return value) with `.override overrideFn` and `.print` attributes attached, both bound to the same `pkgs` as the engine.

#### Scenario: mkWorkspace return value is a derivation
- **WHEN** `engine.mkWorkspace "my-ws" ./workspace.nix` is called
- **THEN** the return value SHALL be a derivation (not a `wsCfg` attrset)

#### Scenario: .override on mkWorkspace result returns a derivation
- **WHEN** `.override (cfg: cfg // { … })` is called on the `mkWorkspace` return value
- **THEN** the result SHALL also be a derivation with `.override` and `.print` attached

#### Scenario: .print on mkWorkspace result is a derivation
- **WHEN** `.print` is accessed on the `mkWorkspace` return value
- **THEN** it SHALL be a `workspace-<name>-print` derivation

### Requirement: lib.mkWorkspace and lib.mkWorkspaceIn flake outputs remain compatible
The flake's `lib.mkWorkspace pkgs` and `lib.mkWorkspaceIn pkgs flakeRoot` SHALL continue to return a function `name: moduleFile: <derivation>` with the same behaviour as before the refactor.

#### Scenario: lib.mkWorkspace downstream usage is unchanged
- **WHEN** a downstream flake calls `alice.lib.mkWorkspace pkgs "my-ws" ./workspace.nix`
- **THEN** the result SHALL be a provisionable derivation, unchanged from the pre-refactor behaviour

### Requirement: workspaceConfigurations flake output
The flake SHALL expose a system-independent `workspaceConfigurations` attribute set. Each value SHALL be a `wsCfg` object produced by `mkWorkspaceConfig`.

#### Scenario: workspaceConfigurations.sample-workspace exists
- **WHEN** the flake is evaluated
- **THEN** `workspaceConfigurations.sample-workspace` SHALL be a `wsCfg` with `.config`, `.override`, `.provision`, and `.print` attributes

### Requirement: workspaceModules flake output
The flake SHALL expose a `workspaceModules` attribute set of module file paths. At minimum it SHALL contain a `workspaces` key pointing to `modules/workspaces.nix`.

#### Scenario: workspaceModules.workspaces exists and is importable
- **WHEN** `workspaceModules.workspaces` is imported with `{ pkgs, flakeRoot }`
- **THEN** it SHALL return an attrset with `mkWorkspaceConfig` and `mkWorkspace` keys
