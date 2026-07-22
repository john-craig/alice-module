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
          # Sample package
          # ------------------------------------------------------------------
          hello = pkgs.callPackage ./packages/hello { inherit pkgs; };

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
        }
      );

      apps = forEachSystem (system: {
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
