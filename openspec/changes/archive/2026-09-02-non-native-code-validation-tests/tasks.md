## 1. Add inline workspace fixture for declared-host-binary provisioning

- [x] 1.1 In `flake.nix`, add a new `wsNativeFalseDeclaredBinaryMcp` inline workspace fixture (via `pkgs.writeText`) that sets `native = false`, `assertHostBinaries = [ "npx" ]`, and declares an MCP server with `command = "npx"` — identical in intent to the existing `wsNativeFalseDeclaredBinary` fixture but used by the upgraded provisioning check

## 2. Upgrade native-false-allows-declared-host-binary to a provisioning check

- [x] 2.1 Replace the existing `native-false-allows-declared-host-binary` check (currently a bare `builtins.tryEval` + `assert result.success`) with a `pkgs.runCommand` check that builds the workspace derivation, runs the provisioning script against a temp directory, and asserts `.bob/mcp.json` exists and contains the `npx`-based MCP server entry

## 3. Verify all existing non-native checks are present and correctly named

- [x] 3.1 Confirm `native-false-blocks-packages` check exists and uses `assert !result.success` pattern
- [x] 3.2 Confirm `native-false-blocks-source-file` check exists and uses `assert !result.success` pattern
- [x] 3.3 Confirm `native-false-blocks-store-path-mcp` check exists and uses `assert !result.success` pattern
- [x] 3.4 Confirm `native-false-blocks-undeclared-host-binary` check exists and uses `assert !result.success` pattern
- [x] 3.5 Confirm `native-false-allows-text-only` check exists and provisions + verifies `hello.txt` and `.bob/rules/rules.md`
- [x] 3.6 Confirm `native-false-allows-http-mcp` check exists and provisions + verifies `.bob/mcp.json` contains `"streamable-http"`
- [x] 3.7 Confirm `native-override-forces-native-false` check exists and uses `assert !result.success` pattern

## 4. Validate

- [x] 4.1 Run `nix flake check` and confirm all checks pass (including the upgraded `native-false-allows-declared-host-binary` check)
