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
      # Usage:
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
      #   packages.my-workspace =
      #     inputs.alice-module.lib.mkWorkspaceIn pkgs myFlake.self
      #       "my-workspace" ./workspaces/my-workspace/default.nix;
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
          # Example workspace: blank
          #
          # A minimal workspace that writes a single hello.txt file.
          # Run with:  nix run .#workspace-blank -- /path/to/target-dir
          # ------------------------------------------------------------------
          workspace-blank = mkWs "blank" ./workspaces/blank/default.nix;

          # Default package: the blank workspace (demonstrates the machinery)
          default = mkWs "blank" ./workspaces/blank/default.nix;
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
          # blank-workspace-output
          #
          # Runs workspace-blank against a temporary directory and asserts that
          # hello.txt is created with the expected content.
          # ------------------------------------------------------------------
          blank-workspace-output = pkgs.runCommand "blank-workspace-output" {
            nativeBuildInputs = [ self.packages.${system}.workspace-blank ];
          } ''
            target=$(mktemp -d)
            workspace-blank "$target"

            expected="Hello, world!"
            actual=$(cat "$target/hello.txt")

            if [ "$actual" != "$expected" ]; then
              echo "FAIL: hello.txt content mismatch"
              echo "  expected: $expected"
              echo "  actual:   $actual"
              exit 1
            fi

            echo "PASS: hello.txt contains expected content"
            touch $out
          '';
        }
      );

      apps = forEachSystem (system: {
        workspace-blank = {
          type    = "app";
          program = "${self.packages.${system}.workspace-blank}/bin/workspace-blank";
        };

        default = {
          type    = "app";
          program = "${self.packages.${system}.workspace-blank}/bin/workspace-blank";
        };
      });
    };
}
