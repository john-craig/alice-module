## 1. Engine — modules/workspaces.nix

- [x] 1.1 Implement `buildPrintDrv name cfg printPkgs`: use `printPkgs.writeText` to bake the config serialisation (via `lib.generators.toPretty`) into the store, then produce a `printPkgs.writeShellApplication` named `workspace-<name>-print` whose script installs that store path to the caller-supplied output file.
- [x] 1.2 Add `.print pkgs` to the attrset returned by `buildWorkspaceConfig`, calling `buildPrintDrv name cfg pkgs`.
- [x] 1.3 Add `.print` to the derivation attrset returned by `bindWorkspaceConfig`, set to `wsCfg.print boundPkgs`.

## 2. flake.nix

- [x] 2.1 In the per-system `packages` output, add `workspace-sample-workspace-print` via `sampleWsCfg.print pkgs` and `workspace-extended-workspace-print` via `(mkWsCfg "extended-workspace" ./examples/workspace.nix {}).print pkgs`.
- [x] 2.2 In the per-system `apps` output, add `workspace-sample-workspace-print` and `workspace-extended-workspace-print` app entries.

## 3. Flake checks

- [x] 3.1 Add a `workspace-sample-workspace-print` check: build and run the print script against a temp file, then assert the output file exists and contains the string `"sample-workspace"`.

## 4. Validation

- [x] 4.1 Run `nix build .#workspace-sample-workspace-print` and confirm it builds.
- [x] 4.2 Run `nix flake check` and confirm all checks pass.
- [x] 4.3 Manually run `workspace-sample-workspace-print /tmp/sample.nix` and confirm the output is well-formed.
