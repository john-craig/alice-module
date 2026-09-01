## Requirements

### Requirement: workspace.native module option
The workspace module SHALL expose a `workspace.native` boolean option with a default value of `true`. Its description SHALL state that `true` means the workspace assumes host-native tooling and the Nix store are available; `false` declares that the Nix store must not be assumed to be present on the target host.

#### Scenario: default value is true
- **WHEN** a workspace module does not set `workspace.native`
- **THEN** the evaluated `cfg.workspace.native` SHALL be `true`

#### Scenario: explicit false is accepted
- **WHEN** a workspace module sets `workspace.native = false`
- **THEN** the evaluated `cfg.workspace.native` SHALL be `false`

### Requirement: non-native mode blocks workspace.packages
When `workspace.native = false`, the engine SHALL reject any non-empty `workspace.packages` list at Nix evaluation time with a descriptive assertion message.

#### Scenario: packages declared with native = false
- **WHEN** `workspace.native = false` and `workspace.packages` contains one or more packages
- **THEN** Nix evaluation SHALL fail with an assertion error identifying `workspace.packages` as incompatible with non-native mode

#### Scenario: packages empty with native = false
- **WHEN** `workspace.native = false` and `workspace.packages = []`
- **THEN** evaluation SHALL succeed without error

### Requirement: non-native mode blocks source file entries
When `workspace.native = false`, the engine SHALL reject any `workspace.file`, `workspace.bob.rules`, or `workspace.bob.skills` entry whose `source` attribute is non-null, at Nix evaluation time.

#### Scenario: file entry with source set and native = false
- **WHEN** `workspace.native = false` and any file/rules/skills entry has `source` set to a non-null path
- **THEN** Nix evaluation SHALL fail with an assertion error identifying the offending key and option path

#### Scenario: file entry with text only and native = false
- **WHEN** `workspace.native = false` and all file/rules/skills entries use `text` only
- **THEN** evaluation SHALL succeed without error

### Requirement: non-native mode blocks Nix-store MCP commands
When `workspace.native = false`, the engine SHALL reject any MCP server whose `command` string begins with `/nix/store/`, at Nix evaluation time.

#### Scenario: stdio MCP server with store-path command and native = false
- **WHEN** `workspace.native = false` and an MCP server has `command` starting with `/nix/store/`
- **THEN** Nix evaluation SHALL fail with an assertion error identifying the offending server name

#### Scenario: HTTP MCP server with native = false
- **WHEN** `workspace.native = false` and an MCP server has `type` set (HTTP-based, no `command`)
- **THEN** evaluation SHALL succeed without error

#### Scenario: stdio MCP server with non-store command and native = false
- **WHEN** `workspace.native = false` and an MCP server has `command` that does not start with `/nix/store/`
- **THEN** Nix evaluation SHALL succeed (the command is treated as a potential host binary and verified at provision time)

### Requirement: workspace.assertHostBinaries option
The workspace module SHALL expose a `workspace.assertHostBinaries` option of type `listOf str` with a default value of `[]`. Each entry is an executable name (short name, not a full path) that the workspace depends on.

#### Scenario: default value is empty
- **WHEN** a workspace module does not set `workspace.assertHostBinaries`
- **THEN** the evaluated list SHALL be `[]`

#### Scenario: list of names is accepted
- **WHEN** `workspace.assertHostBinaries = [ "node" "npx" ]`
- **THEN** evaluation SHALL succeed and the list SHALL be available as `cfg.workspace.assertHostBinaries`

### Requirement: host binaries manifest check at provision time
At `alice switch` time, when `workspace.native = false` and `workspace.assertHostBinaries` is non-empty, alice SHALL read a host binaries manifest file and verify that every name in `assertHostBinaries` appears in the manifest. Any missing name SHALL cause alice to abort with a hard error before any provisioning begins.

#### Scenario: all asserted binaries present in manifest
- **WHEN** `native = false`, `assertHostBinaries = [ "node" ]`, and the manifest contains `"node"`
- **THEN** provisioning SHALL proceed normally

#### Scenario: asserted binary absent from manifest
- **WHEN** `native = false`, `assertHostBinaries = [ "node" "deno" ]`, and the manifest contains `"node"` but not `"deno"`
- **THEN** alice SHALL print an error naming `"deno"` as missing and exit with a non-zero status before any file is written

#### Scenario: manifest file absent with non-empty assertHostBinaries and native = false
- **WHEN** `native = false`, `assertHostBinaries` is non-empty, and the manifest file does not exist at the expected path
- **THEN** alice SHALL print an error explaining that the manifest is missing and exit with a non-zero status

### Requirement: host binaries manifest file location
The default host binaries manifest path SHALL be `.alice/host-binaries` inside the target directory. The manifest SHALL be a plain text file with one executable name per line.

#### Scenario: manifest at default location
- **WHEN** no `--host-binaries` flag is supplied and `.alice/host-binaries` exists in the target directory
- **THEN** alice SHALL read that file as the manifest

#### Scenario: manifest overridden via --host-binaries flag
- **WHEN** `--host-binaries /path/to/my-manifest` is passed to `alice switch`
- **THEN** alice SHALL read `/path/to/my-manifest` as the manifest instead of the default

### Requirement: non-native stdio MCP server permitted via assertHostBinaries
A stdio MCP server whose `command` does not start with `/nix/store/` SHALL be permitted in non-native mode if and only if the executable name of its `command` appears in `workspace.assertHostBinaries` and passes the host binaries manifest check.

#### Scenario: host-binary MCP server permitted after successful manifest check
- **WHEN** `native = false`, an MCP server has `command = "npx"`, `assertHostBinaries` contains `"npx"`, and `"npx"` is present in the manifest
- **THEN** the MCP server SHALL be included in the provisioned `.bob/mcp.json`

#### Scenario: host-binary MCP server not declared in assertHostBinaries
- **WHEN** `native = false`, an MCP server has `command = "npx"`, and `assertHostBinaries` does not contain `"npx"`
- **THEN** alice SHALL abort with an error identifying `"npx"` as an undeclared host binary dependency

### Requirement: assertHostBinaries warning when native = true
When `workspace.native = true` (or defaulted to true) and `workspace.assertHostBinaries` is non-empty, alice SHALL emit a single warning to stderr and continue without reading any manifest file.

#### Scenario: assertHostBinaries set but native = true
- **WHEN** `native = true` (or not set) and `assertHostBinaries` is non-empty
- **THEN** alice SHALL print a warning to stderr stating that host binary assertions will not be checked in native mode
- **AND** provisioning SHALL proceed normally without reading a manifest

#### Scenario: assertHostBinaries empty with native = true
- **WHEN** `native = true` and `assertHostBinaries = []`
- **THEN** no warning SHALL be emitted

### Requirement: alice switch --no-native / --native flags
`alice switch` SHALL accept two mutually exclusive flags, `--no-native` and `--native`, that override `workspace.native` at invocation time. When neither flag is supplied, the value declared in the workspace module is used.

#### Scenario: --no-native overrides workspace.native = true
- **WHEN** `alice switch --no-native` is invoked
- **THEN** the workspace SHALL be built with `wsNative = false`, overriding any `workspace.native` value in the module

#### Scenario: --native explicitly sets native = true
- **WHEN** `alice switch --native` is invoked
- **THEN** the workspace SHALL be built with `wsNative = true`

#### Scenario: neither flag defers to the module declaration
- **WHEN** neither `--no-native` nor `--native` is passed to `alice switch`
- **THEN** the `wsNative` argument passed to the build expression SHALL reflect the value declared in the workspace module

#### Scenario: unknown flag is rejected
- **WHEN** an unrecognised option is passed to `alice switch`
- **THEN** alice SHALL print an error and exit with a non-zero status (existing behaviour; must remain intact after this change)

### Requirement: alice switch --host-binaries flag
`alice switch` SHALL accept a `--host-binaries <file>` flag that sets the path to the host binaries manifest, overriding the default of `.alice/host-binaries` in the target directory.

#### Scenario: --host-binaries flag overrides default path
- **WHEN** `alice switch --host-binaries /etc/alice/binaries` is passed
- **THEN** alice SHALL use `/etc/alice/binaries` as the manifest path for the host binaries check

### Requirement: alice init template documents workspace.native and workspace.assertHostBinaries
The starter `workspace.nix` generated by `alice init` SHALL include both `workspace.native` and `workspace.assertHostBinaries` as commented-out example options with brief descriptions.

#### Scenario: generated file contains both new options
- **WHEN** `alice init` is run
- **THEN** the generated `.alice/workspace.nix` SHALL contain commented-out example lines for both `workspace.native` and `workspace.assertHostBinaries`
