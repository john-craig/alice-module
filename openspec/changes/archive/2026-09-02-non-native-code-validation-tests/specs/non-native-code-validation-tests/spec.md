## ADDED Requirements

### Requirement: non-native blocks-packages check
`flake.nix` SHALL contain a check named `native-false-blocks-packages` that asserts Nix evaluation fails when `workspace.native = false` and `workspace.packages` is non-empty.

#### Scenario: packages check present and fails on violation
- **WHEN** the `native-false-blocks-packages` check is run via `nix flake check`
- **THEN** the check SHALL pass (meaning the engine threw as expected)

### Requirement: non-native blocks-source-file check
`flake.nix` SHALL contain a check named `native-false-blocks-source-file` that asserts Nix evaluation fails when `workspace.native = false` and any file/rules/skills entry has `source` set.

#### Scenario: source-file check present and fails on violation
- **WHEN** the `native-false-blocks-source-file` check is run
- **THEN** the check SHALL pass

### Requirement: non-native blocks-store-path-mcp check
`flake.nix` SHALL contain a check named `native-false-blocks-store-path-mcp` that asserts Nix evaluation fails when `workspace.native = false` and an MCP server command starts with `/nix/store/`.

#### Scenario: store-mcp check present and fails on violation
- **WHEN** the `native-false-blocks-store-path-mcp` check is run
- **THEN** the check SHALL pass

### Requirement: non-native blocks-undeclared-host-binary check
`flake.nix` SHALL contain a check named `native-false-blocks-undeclared-host-binary` that asserts Nix evaluation fails when `workspace.native = false` and an MCP server has a plain command name not listed in `workspace.assertHostBinaries`.

#### Scenario: undeclared-binary check present and fails on violation
- **WHEN** the `native-false-blocks-undeclared-host-binary` check is run
- **THEN** the check SHALL pass

### Requirement: non-native allows-text-only check
`flake.nix` SHALL contain a check named `native-false-allows-text-only` that provisions a workspace with `native = false`, text-only files, no packages, and no MCP servers, then asserts the expected files exist with correct content.

#### Scenario: text-only workspace provisions successfully
- **WHEN** the `native-false-allows-text-only` check is run
- **THEN** the check SHALL create `hello.txt` with the expected content and `.bob/rules/rules.md`

### Requirement: non-native allows-http-mcp check
`flake.nix` SHALL contain a check named `native-false-allows-http-mcp` that provisions a workspace with `native = false` and an HTTP MCP server, then asserts `.bob/mcp.json` exists and contains the expected server type.

#### Scenario: HTTP MCP server written to mcp.json
- **WHEN** the `native-false-allows-http-mcp` check is run
- **THEN** the check SHALL confirm `.bob/mcp.json` contains `"streamable-http"`

### Requirement: non-native allows-declared-host-binary check (with provisioning verification)
`flake.nix` SHALL contain a check named `native-false-allows-declared-host-binary` that not only asserts Nix evaluation succeeds but also runs the provisioning script and verifies that `.bob/mcp.json` is written and contains the expected MCP server entry.

#### Scenario: declared host-binary MCP server written to mcp.json
- **WHEN** the `native-false-allows-declared-host-binary` check is run
- **THEN** the check SHALL provision the workspace and assert `.bob/mcp.json` contains the server entry for the `npx`-based MCP server

### Requirement: native-override-forces-native-false check
`flake.nix` SHALL contain a check named `native-override-forces-native-false` that asserts Nix evaluation fails when `nativeOverride = false` is passed to the engine and the workspace declares `native = true` with non-empty packages.

#### Scenario: nativeOverride = false overrides module native = true
- **WHEN** the `native-override-forces-native-false` check is run
- **THEN** the check SHALL pass (engine threw despite module declaring native = true)
