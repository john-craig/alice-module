{
  description = "Declarative workspace provisioning for Bob — Alice Nix Module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Systems this flake exposes per-system outputs for.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Iterate over all supported systems and merge the per-system attrsets.
      forEachSystem = f:
        nixpkgs.lib.foldl'
          (acc: system: nixpkgs.lib.recursiveUpdate acc { ${system} = f system; })
          {}
          systems;

    in
    {
      # -----------------------------------------------------------------------
      # lib.mkWorkspace
      #
      # Build a workspace derivation from a module file.
      #
      # Usage (in a downstream flake):
      #
      #   let
      #     alice = inputs.alice-module;
      #     pkgs  = import inputs.nixpkgs { inherit system; };
      #     mkWs  = alice.lib.mkWorkspace pkgs;
      #   in {
      #     packages.my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
      #   }
      #
      # The module file must follow the convention described in
      # modules/workspaces.nix — a function of { pkgs, workspaces, utils } that
      # returns { workspaces."<name>" = { workspace = ...; }; }.
      #
      # `utils.root relPath` resolves a path relative to the *calling* flake's
      # root.  Pass `flakeRoot` (the second arg to mkWorkspaceIn) to customise
      # this; if omitted it defaults to the root of *this* flake (useful for
      # the built-in example workspaces).
      # -----------------------------------------------------------------------
      lib.mkWorkspace = pkgs:
        let
          # When consumers call this from their own flake they will import
          # modules/workspaces.nix with their own flakeRoot.  The default
          # here points at this flake's own root so the built-in example
          # workspaces resolve correctly.
          engine = import ./modules/workspaces.nix {
            inherit pkgs;
            flakeRoot = self;
          };
        in
        engine;

      # -----------------------------------------------------------------------
      # lib.mkWorkspaceIn
      #
      # Like lib.mkWorkspace but lets the caller supply a custom flakeRoot
      # so that utils.root resolves relative to their own repository.
      #
      # Usage (in a downstream flake):
      #
      #   let
      #     mkWs = inputs.alice-module.lib.mkWorkspaceIn pkgs self;
      #   in {
      #     packages.my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
      #   }
      # -----------------------------------------------------------------------
      lib.mkWorkspaceIn = pkgs: flakeRoot:
        import ./modules/workspaces.nix { inherit pkgs flakeRoot; };

      # -----------------------------------------------------------------------
      # Per-system outputs
      # -----------------------------------------------------------------------
      packages = forEachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          mkWs = self.lib.mkWorkspace pkgs;
        in
        {
          # ------------------------------------------------------------------
          # alice — the imperative workspace provisioning CLI.
          #
          # Inspired by home-manager / nixos-rebuild.  Accepts a workspace.nix
          # path and a target directory at runtime and provisions on the spot.
          #
          # Run with:  nix run .#alice -- switch --workspace ./workspace.nix --target .
          # ------------------------------------------------------------------
          alice = pkgs.callPackage ./packages/alice {
            inherit pkgs;
            # Capture the store path of the engine module at build time so the
            # runtime script can reference it without needing the source tree.
            workspacesModule = ./modules/workspaces.nix;
          };

          # ------------------------------------------------------------------
          # Example workspace: sample-workspace
          #
          # Demonstrates every supported workspace option (workspace.file,
          # workspace.bob.rules, workspace.bob.skills, workspace.bob.mcpServers,
          # workspace.packages).
          #
          # The first argument to mkWs is the workspace *name* — it must match
          # the key used in workspaces."<name>" inside the module file.
          # The second argument is the path to the module file itself.
          #
          # Run with:  nix run .#workspace-sample-workspace -- /path/to/target-dir
          # ------------------------------------------------------------------
          workspace-sample-workspace =
            mkWs "sample-workspace" ./examples/sample-workspace/default.nix;

          # ------------------------------------------------------------------
          # Example workspace: extended-workspace
          #
          # Demonstrates how to override and extend an upstream workspace
          # definition.  The module at examples/workspace.nix imports
          # examples/sample-workspace/default.nix, merges its config block
          # using Nix attribute operators (// for attrsets, ++ for lists),
          # and re-exports the result under a different workspace name.
          #
          # Both workspaces can coexist and are built independently — the
          # extended one shares no mutable state with the upstream one.
          #
          # Run with:  nix run .#workspace-extended-workspace -- /path/to/target-dir
          # ------------------------------------------------------------------
          workspace-extended-workspace =
            mkWs "extended-workspace" ./examples/workspace.nix;

          # Default package: the sample workspace
          default =
            mkWs "sample-workspace" ./examples/sample-workspace/default.nix;
        }
      );

      checks = forEachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Convenience: build a workspace engine with an optional nativeOverride.
          mkEngine = args: import ./modules/workspaces.nix ({ inherit pkgs; flakeRoot = self; } // args);

          # Inline workspace files used by the non-native checks.
          # Each is a store path produced by pkgs.writeText — safe to pass as a
          # moduleFile argument to the engine because the engine only needs to
          # `import` the file, which is allowed from the Nix store.
          wsNativeFalsePackages = pkgs.writeText "ws-native-false-packages.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native   = false;
                workspace.packages = [ pkgs.ripgrep ];
              };
            }
          '';

          wsNativeFalseSourceFile = pkgs.writeText "ws-native-false-source-file.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native = false;
                workspace.file."data.txt" = { source = builtins.toFile "data" "hello"; };
              };
            }
          '';

          wsNativeFalseStoreMcp = pkgs.writeText "ws-native-false-store-mcp.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native = false;
                workspace.bob.mcpServers."my-server" = {
                  command = "${pkgs.nodejs}/bin/node";
                  args    = [ "server.js" ];
                };
              };
            }
          '';

          wsNativeFalseUndeclaredBinary = pkgs.writeText "ws-native-false-undeclared-binary.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native = false;
                workspace.bob.mcpServers."my-server" = {
                  command = "npx";
                  args    = [ "-y" "some-pkg" ];
                };
              };
            }
          '';

          wsNativeFalseTextOnly = pkgs.writeText "ws-native-false-text-only.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native = false;
                workspace.file."hello.txt" = "Hello from non-native mode.\n";
                workspace.bob.rules."rules.md" = "# Rules\n\n- Be good.\n";
              };
            }
          '';

          wsNativeFalseHttpMcp = pkgs.writeText "ws-native-false-http-mcp.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native = false;
                workspace.bob.mcpServers."remote" = {
                  type = "streamable-http";
                  url  = "https://mcp.example.com/";
                };
              };
            }
          '';

          wsNativeFalseDeclaredBinary = pkgs.writeText "ws-native-false-declared-binary.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native          = false;
                workspace.assertHostBinaries = [ "npx" ];
                workspace.bob.mcpServers."my-server" = {
                  command = "npx";
                  args    = [ "-y" "some-pkg" ];
                };
              };
            }
          '';

          wsNativeOverrideFalse = pkgs.writeText "ws-native-override-false.nix" ''
            { pkgs, utils, workspaces }:
            { workspaces."test-ws" = {
                workspace.native   = true;   # module says native; CLI will override
                workspace.packages = [ pkgs.ripgrep ];
              };
            }
          '';

        in
        {
          # ------------------------------------------------------------------
          # sample-workspace-output
          #
          # Runs workspace-sample-workspace against a temporary directory and
          # asserts that key output files are created with expected content.
          # ------------------------------------------------------------------
          sample-workspace-output = pkgs.runCommand "sample-workspace-output" {
            nativeBuildInputs = [ self.packages.${system}.workspace-sample-workspace ];
          } ''
            target=$(mktemp -d)
            workspace-sample-workspace "$target"

            # README.md should exist (written with dontIgnore = true)
            if [ ! -f "$target/README.md" ]; then
              echo "FAIL: README.md was not created"
              exit 1
            fi

            # config/settings.json should exist
            if [ ! -f "$target/config/settings.json" ]; then
              echo "FAIL: config/settings.json was not created"
              exit 1
            fi

            # .bob/mcp.json should exist (mcpServers were declared)
            if [ ! -f "$target/.bob/mcp.json" ]; then
              echo "FAIL: .bob/mcp.json was not created"
              exit 1
            fi

            echo "PASS: sample-workspace output verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # extended-workspace-output
          #
          # Runs workspace-extended-workspace and verifies that both inherited
          # and override/extended files are present.
          # ------------------------------------------------------------------
          extended-workspace-output = pkgs.runCommand "extended-workspace-output" {
            nativeBuildInputs = [ self.packages.${system}.workspace-extended-workspace ];
          } ''
            target=$(mktemp -d)
            workspace-extended-workspace "$target"

            # README.md — overridden by the extended workspace
            if ! grep -q "extended-workspace" "$target/README.md"; then
              echo "FAIL: README.md does not contain extended-workspace header"
              exit 1
            fi

            # extended-notes.md — added only by the extended workspace
            if [ ! -f "$target/extended-notes.md" ]; then
              echo "FAIL: extended-notes.md was not created"
              exit 1
            fi

            # .bob/rules/sample-rules.md — inherited from upstream
            if [ ! -f "$target/.bob/rules/sample-rules.md" ]; then
              echo "FAIL: upstream sample-rules.md was not inherited"
              exit 1
            fi

            # .bob/rules/extended-rules.md — added by the extended workspace
            if [ ! -f "$target/.bob/rules/extended-rules.md" ]; then
              echo "FAIL: extended-rules.md was not created"
              exit 1
            fi

            echo "PASS: extended-workspace output verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # native-false-blocks-packages
          #
          # workspace.native = false with a non-empty workspace.packages list
          # must throw at Nix evaluation time.
          # ------------------------------------------------------------------
          native-false-blocks-packages =
            let
              result = builtins.tryEval (mkEngine {} "test-ws" wsNativeFalsePackages);
            in
            assert !result.success;
            pkgs.runCommand "native-false-blocks-packages" {} "touch $out";

          # ------------------------------------------------------------------
          # native-false-blocks-source-file
          #
          # workspace.native = false with a source-based file entry must throw.
          # ------------------------------------------------------------------
          native-false-blocks-source-file =
            let
              result = builtins.tryEval (mkEngine {} "test-ws" wsNativeFalseSourceFile);
            in
            assert !result.success;
            pkgs.runCommand "native-false-blocks-source-file" {} "touch $out";

          # ------------------------------------------------------------------
          # native-false-blocks-store-path-mcp
          #
          # workspace.native = false with an MCP server command that starts
          # with /nix/store/ must throw at Nix evaluation time.
          # ------------------------------------------------------------------
          native-false-blocks-store-path-mcp =
            let
              result = builtins.tryEval (mkEngine {} "test-ws" wsNativeFalseStoreMcp);
            in
            assert !result.success;
            pkgs.runCommand "native-false-blocks-store-path-mcp" {} "touch $out";

          # ------------------------------------------------------------------
          # native-false-blocks-undeclared-host-binary
          #
          # workspace.native = false with an MCP server using a plain command
          # name that is NOT in assertHostBinaries must throw.
          # ------------------------------------------------------------------
          native-false-blocks-undeclared-host-binary =
            let
              result = builtins.tryEval (mkEngine {} "test-ws" wsNativeFalseUndeclaredBinary);
            in
            assert !result.success;
            pkgs.runCommand "native-false-blocks-undeclared-host-binary" {} "touch $out";

          # ------------------------------------------------------------------
          # native-false-allows-text-only
          #
          # A workspace with native = false, text-only files, no packages and
          # no MCP servers must evaluate and provision successfully.
          # ------------------------------------------------------------------
          native-false-allows-text-only =
            let ws = mkEngine {} "test-ws" wsNativeFalseTextOnly; in
            pkgs.runCommand "native-false-allows-text-only" {
              nativeBuildInputs = [ ws ];
            } ''
              target=$(mktemp -d)
              workspace-test-ws "$target"

              if [ ! -f "$target/hello.txt" ]; then
                echo "FAIL: hello.txt was not created"
                exit 1
              fi
              if ! grep -q "Hello from non-native mode" "$target/hello.txt"; then
                echo "FAIL: hello.txt content is wrong"
                exit 1
              fi
              if [ ! -f "$target/.bob/rules/rules.md" ]; then
                echo "FAIL: .bob/rules/rules.md was not created"
                exit 1
              fi

              echo "PASS: native-false-allows-text-only verified"
              touch $out
            '';

          # ------------------------------------------------------------------
          # native-false-allows-http-mcp
          #
          # HTTP-based MCP servers carry no Nix store path dependency and must
          # be permitted (and written to .bob/mcp.json) when native = false.
          # ------------------------------------------------------------------
          native-false-allows-http-mcp =
            let ws = mkEngine {} "test-ws" wsNativeFalseHttpMcp; in
            pkgs.runCommand "native-false-allows-http-mcp" {
              nativeBuildInputs = [ ws ];
            } ''
              target=$(mktemp -d)
              workspace-test-ws "$target"

              if [ ! -f "$target/.bob/mcp.json" ]; then
                echo "FAIL: .bob/mcp.json was not created"
                exit 1
              fi
              if ! grep -q "streamable-http" "$target/.bob/mcp.json"; then
                echo "FAIL: mcp.json does not contain expected HTTP server type"
                exit 1
              fi

              echo "PASS: native-false-allows-http-mcp verified"
              touch $out
            '';

          # ------------------------------------------------------------------
          # native-false-allows-declared-host-binary
          #
          # An MCP server whose plain command name IS listed in
          # assertHostBinaries must evaluate successfully when native = false.
          # (Runtime manifest check is a CLI concern; this tests Nix-eval pass.)
          # ------------------------------------------------------------------
          native-false-allows-declared-host-binary =
            let
              result = builtins.tryEval (mkEngine {} "test-ws" wsNativeFalseDeclaredBinary);
            in
            assert result.success;
            pkgs.runCommand "native-false-allows-declared-host-binary" {} "touch $out";

          # ------------------------------------------------------------------
          # native-override-forces-native-false
          #
          # When nativeOverride = false is passed to the engine, a workspace
          # that declares native = true (and uses packages) must still throw.
          # ------------------------------------------------------------------
          native-override-forces-native-false =
            let
              result = builtins.tryEval (mkEngine { nativeOverride = false; } "test-ws" wsNativeOverrideFalse);
            in
            assert !result.success;
            pkgs.runCommand "native-override-forces-native-false" {} "touch $out";

          # ------------------------------------------------------------------
          # alice-init-creates-file
          #
          # `alice init` must create .alice/workspace.nix in the target
          # directory and the file must contain the new workspace.native and
          # workspace.assertHostBinaries commented-out option blocks.
          # ------------------------------------------------------------------
          alice-init-creates-file = pkgs.runCommand "alice-init-creates-file" {
            nativeBuildInputs = [ self.packages.${system}.alice ];
          } ''
            target=$(mktemp -d)
            alice init --target "$target"

            dest="$target/.alice/workspace.nix"
            if [ ! -f "$dest" ]; then
              echo "FAIL: .alice/workspace.nix was not created"
              exit 1
            fi
            if ! grep -q "workspace.native" "$dest"; then
              echo "FAIL: workspace.nix does not mention workspace.native"
              exit 1
            fi
            if ! grep -q "workspace.assertHostBinaries" "$dest"; then
              echo "FAIL: workspace.nix does not mention workspace.assertHostBinaries"
              exit 1
            fi
            if ! grep -q "host-binaries" "$dest"; then
              echo "FAIL: workspace.nix does not mention the host-binaries manifest"
              exit 1
            fi

            echo "PASS: alice-init-creates-file verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # alice-help-exits-zero
          #
          # `alice --help` must print usage and exit 0.
          # ------------------------------------------------------------------
          alice-help-exits-zero = pkgs.runCommand "alice-help-exits-zero" {
            nativeBuildInputs = [ self.packages.${system}.alice ];
          } ''
            if ! alice --help; then
              echo "FAIL: alice --help exited non-zero"
              exit 1
            fi

            echo "PASS: alice-help-exits-zero verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # alice-switch-rejects-missing-workspace-file
          #
          # `alice switch --file /nonexistent.nix` must exit non-zero and
          # print an error identifying the missing file.
          # ------------------------------------------------------------------
          alice-switch-rejects-missing-workspace-file = pkgs.runCommand "alice-switch-rejects-missing-workspace-file" {
            nativeBuildInputs = [ self.packages.${system}.alice ];
          } ''
            target=$(mktemp -d)
            if alice switch --file /nonexistent-workspace.nix --target "$target" 2>err.txt; then
              echo "FAIL: alice switch should have exited non-zero"
              exit 1
            fi
            if ! grep -q "not found" err.txt; then
              echo "FAIL: error output did not mention 'not found'"
              cat err.txt
              exit 1
            fi

            echo "PASS: alice-switch-rejects-missing-workspace-file verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # alice-switch-rejects-missing-target-dir
          #
          # `alice switch --target /nonexistent-dir` must exit non-zero and
          # print an error identifying the missing directory.
          # ------------------------------------------------------------------
          alice-switch-rejects-missing-target-dir = pkgs.runCommand "alice-switch-rejects-missing-target-dir" {
            nativeBuildInputs = [ self.packages.${system}.alice ];
          } ''
            ws=$(mktemp)
            echo '{ pkgs, utils, workspaces }: { workspaces."t" = {}; }' > "$ws"
            if alice switch --file "$ws" --target /nonexistent-alice-target-dir 2>err.txt; then
              echo "FAIL: alice switch should have exited non-zero"
              exit 1
            fi
            if ! grep -q "does not exist" err.txt; then
              echo "FAIL: error output did not mention 'does not exist'"
              cat err.txt
              exit 1
            fi

            echo "PASS: alice-switch-rejects-missing-target-dir verified"
            touch $out
          '';

          # ------------------------------------------------------------------
          # alice-switch-rejects-unknown-option
          #
          # Passing an unrecognised flag to `alice switch` must exit non-zero.
          # ------------------------------------------------------------------
          alice-switch-rejects-unknown-option = pkgs.runCommand "alice-switch-rejects-unknown-option" {
            nativeBuildInputs = [ self.packages.${system}.alice ];
          } ''
            if alice switch --this-flag-does-not-exist 2>/dev/null; then
              echo "FAIL: alice switch should have rejected unknown option"
              exit 1
            fi

            echo "PASS: alice-switch-rejects-unknown-option verified"
            touch $out
          '';
        }
      );

      apps = forEachSystem (system: {
        # The alice CLI — imperative workspace provisioning.
        alice = {
          type    = "app";
          program = "${self.packages.${system}.alice}/bin/alice";
        };

        # The sample workspace app — the canonical starting point for new consumers.
        workspace-sample-workspace = {
          type    = "app";
          program = "${self.packages.${system}.workspace-sample-workspace}/bin/workspace-sample-workspace";
        };

        # The extended workspace app — shows override/extension in action.
        workspace-extended-workspace = {
          type    = "app";
          program = "${self.packages.${system}.workspace-extended-workspace}/bin/workspace-extended-workspace";
        };

        default = {
          type    = "app";
          program = "${self.packages.${system}.workspace-sample-workspace}/bin/workspace-sample-workspace";
        };
      });
    };
}
