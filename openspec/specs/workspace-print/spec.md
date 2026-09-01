## Requirements

### Requirement: workspace-<name>-print derivation is produced by wsCfg.print
`wsCfg.print pkgs` SHALL return a `writeShellApplication` derivation named `workspace-<name>-print`. The derivation SHALL be built at Nix evaluation time — the evaluated configuration is serialised as a Nix expression and baked into the store during `nix build`, so the runtime script requires no Nix evaluation.

#### Scenario: print derivation name
- **WHEN** `wsCfg.print pkgs` is called for workspace `"my-ws"`
- **THEN** the derivation `name` attribute SHALL be `"workspace-my-ws-print"`

### Requirement: workspace-<name>-print script writes config as a Nix expression
The `workspace-<name>-print` script SHALL accept exactly one argument (an output file path) and write the evaluated workspace configuration as a Nix expression to that path.

#### Scenario: successful print
- **WHEN** `workspace-my-ws-print /tmp/config.nix` is run
- **THEN** `/tmp/config.nix` SHALL be created containing a Nix expression with the evaluated config

#### Scenario: config includes file, bob, and packages fields
- **WHEN** the workspace declares `workspace.file`, `workspace.bob.rules`, `workspace.bob.skills`, `workspace.bob.mcpServers`, and `workspace.packages`
- **THEN** the written Nix expression SHALL contain representations of all five fields

#### Scenario: store paths in packages are serialised as strings
- **WHEN** `workspace.packages` contains derivations
- **THEN** the Nix expression SHALL represent each package as its store path string via `builtins.toString (lib.getBin pkg)`

#### Scenario: source paths are serialised as strings or null
- **WHEN** a file entry has `source = /nix/store/…`
- **THEN** the Nix expression SHALL represent the source as a string path; when `source = null` it SHALL be represented as `null`

### Requirement: workspace-<name>-print requires exactly one argument
The script SHALL exit non-zero and print a usage message when called with zero arguments or more than one argument.

#### Scenario: zero arguments
- **WHEN** `workspace-my-ws-print` is run with no arguments
- **THEN** it SHALL exit with a non-zero status and print a usage message to stderr

### Requirement: workspace-<name>-print is accessible via legacy mkWorkspace .print
The `writeShellApplication` returned by `engine.mkWorkspace` SHALL have a `.print` attribute that is the `workspace-<name>-print` derivation bound to the same `pkgs`.

#### Scenario: .print on mkWorkspace result
- **WHEN** `drv = engine.mkWorkspace "my-ws" ./ws.nix` and `drv.print` is evaluated
- **THEN** `drv.print` SHALL be the `workspace-my-ws-print` derivation

### Requirement: workspace-<name>-print packages are exposed as a per-system flake output
Each built-in example workspace SHALL expose both `workspace-<name>` (provision) and `workspace-<name>-print` (print) under `packages.<system>`.

#### Scenario: workspace-sample-workspace-print in packages
- **WHEN** the flake is evaluated for a given system
- **THEN** `packages.<system>.workspace-sample-workspace-print` SHALL be a buildable derivation
