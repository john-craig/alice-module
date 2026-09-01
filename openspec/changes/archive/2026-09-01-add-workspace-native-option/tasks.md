## 1. Module — workspace.native option

- [ ] 1.1 In `modules/workspaces.nix`, add `workspace.native` as a `lib.types.bool` option with `default = true` and a descriptive `description` string inside the `workspaceOptions` block.
- [ ] 1.2 In `modules/workspaces.nix`, add `workspace.assertHostBinaries` as a `lib.types.listOf lib.types.str` option with `default = []` and a description explaining each entry is a short executable name.

## 2. Module — non-native enforcement assertions

- [ ] 2.1 In `modules/workspaces.nix`, add a `config.assertions` entry that fails when `cfg.native = false` and `cfg.packages != []`, with a message identifying `workspace.packages` as incompatible with non-native mode.
- [ ] 2.2 Add assertions for each of `cfg.file`, `cfg.bob.rules`, and `cfg.bob.skills`: for every entry whose `source` is non-null, assert that `cfg.native = true`, naming the offending attribute key and option path in the message.
- [ ] 2.3 Add an assertion for each MCP server in `cfg.bob.mcpServers`: when `cfg.native = false` and the server's `command` is non-null and starts with `/nix/store/`, fail with a message naming the server.
- [ ] 2.4 Add an assertion for each MCP server: when `cfg.native = false` and the server's `command` is non-null and does not start with `/nix/store/`, assert that `builtins.baseNameOf srv.command` is a member of `cfg.assertHostBinaries`, with a message naming the server and the undeclared binary.

## 3. CLI — alice-build-workspace.nix embedded expression

- [ ] 3.1 In `packages/alice/default.nix`, extend the `buildWorkspaceExpr` Nix string to accept a new `wsNative` string argument (passed via `--argstr`) and convert it to a Nix bool (`wsNative == "1"`).
- [ ] 3.2 Pass the resolved `native` bool to the engine call using `lib.mkForce` in the module config overlay so it overrides the workspace declaration's `workspace.native` value.

## 4. CLI — alice switch argument parsing

- [ ] 4.1 In the `cmd_switch` shell function in `packages/alice/default.nix`, add `ws_native` (default `""`) and `host_binaries_file` (default `""`) local variables.
- [ ] 4.2 Add `--no-native`, `--native`, and `--host-binaries` cases to the `case` statement in `cmd_switch`'s option-parsing loop.
- [ ] 4.3 Before calling `nix build`, if `ws_native` is still `""`, auto-detect it from the workspace file via a `nix eval` call (analogous to `ws_name` detection); default to `"1"` if `workspace.native` is absent.
- [ ] 4.4 Pass `--argstr wsNative "$ws_native_resolved"` to the `nix build` invocation.
- [ ] 4.5 After resolving `native`, when `ws_native_resolved = "0"` (non-native mode), perform the host binaries manifest check:
  a. Resolve the manifest path: use `$host_binaries_file` if set, else `"$target_dir/.alice/host-binaries"`.
  b. Read `assertHostBinaries` from the workspace file via `nix eval` (returns a JSON array of strings).
  c. If the list is non-empty and the manifest file does not exist, print an error and exit non-zero.
  d. For each name in `assertHostBinaries`, check it appears as a line in the manifest; collect all missing names and print them together, then exit non-zero if any are missing.
- [ ] 4.6 When `ws_native_resolved = "1"` (native mode), if `assertHostBinaries` is non-empty, print a warning to stderr that host binary assertions will not be checked.
- [ ] 4.7 Update the `usage` heredoc to document `--no-native`, `--native`, and `--host-binaries` under "Options for switch".
- [ ] 4.8 Add `--no-native` / `--native` / `--host-binaries` examples to the `Examples:` section of the usage text.

## 5. CLI — alice init template

- [ ] 5.1 In the `alice init` heredoc template, add a commented-out `# workspace.native = true;` block with a brief description alongside the other top-level `workspace.*` options.
- [ ] 5.2 In the same template, add a commented-out `# workspace.assertHostBinaries = [ "node" "npx" ];` block with a description explaining its purpose and the `.alice/host-binaries` manifest convention.

## 6. Validation

- [x] 6.1 Build the `alice` package (`nix build .#alice`) and confirm it compiles without errors.
- [x] 6.2 Build `workspace-sample-workspace` (`nix build .#workspace-sample-workspace`) to confirm the module change is backward-compatible.
- [x] 6.3 Run the existing Nix checks (`nix flake check`) to confirm all existing assertions still pass.
- [x] 6.4 Manually verify: create a workspace with `native = false` and `packages = [ pkgs.ripgrep ]`; confirm `nix build` fails with a clear assertion message.
- [x] 6.5 Manually verify: create a workspace with `native = false`, a `file` entry using `source`, and confirm `nix build` fails with a clear assertion message naming the key.
- [x] 6.6 Manually verify: create a workspace with `native = false`, an MCP server with `command = "/nix/store/..."`, and confirm `nix build` fails with a clear assertion message naming the server.
- [x] 6.7 Manually verify: create a workspace with `native = false`, an MCP server with `command = "npx"`, `assertHostBinaries = [ "npx" ]`, and a manifest containing `"npx"`; confirm provisioning succeeds.
- [x] 6.8 Manually verify: `alice switch --no-native` with a native workspace correctly overrides to non-native mode.
