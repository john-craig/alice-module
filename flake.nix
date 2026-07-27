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

      # Import the workspace engine for a given pkgs + flakeRoot combination.
      # The engine attrset exposes { mkWorkspace, mkWorkspaceFromFile }.
      mkEngine = pkgs: flakeRoot:
        import ./modules/workspaces.nix { inherit pkgs flakeRoot; };

    in
    {
      # -----------------------------------------------------------------------
      # lib.mkWorkspace pkgs
      #
      # Returns a curried function  name → moduleFile → derivation.
      #
      # `utils.root` inside the module resolves relative to *this* flake's root.
      # Use lib.mkWorkspaceIn when you want it to resolve relative to a
      # different repository.
      #
      # Usage (downstream flake):
      #
      #   mkWs = inputs.alice-module.lib.mkWorkspace pkgs;
      #   packages.my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
      # -----------------------------------------------------------------------
      lib.mkWorkspace = pkgs:
        (mkEngine pkgs self).mkWorkspace;

      # -----------------------------------------------------------------------
      # lib.mkWorkspaceIn pkgs flakeRoot
      #
      # Like lib.mkWorkspace but with an explicit flake root so that
      # utils.root resolves relative to the caller's repository.
      #
      # Usage (downstream flake):
      #
      #   mkWs = inputs.alice-module.lib.mkWorkspaceIn pkgs self;
      #   packages.my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
      # -----------------------------------------------------------------------
      lib.mkWorkspaceIn = pkgs: flakeRoot:
        (mkEngine pkgs flakeRoot).mkWorkspace;

      # -----------------------------------------------------------------------
      # lib.mkWorkspaceFromFile pkgs
      #
      # Returns a function  workspaceNixPath → derivation.
      #
      # Designed for runtime use inside the Docker container: accepts an
      # absolute path string to the consuming repository's .alice/workspace.nix
      # (available after bind-mounting) and builds a workspace derivation from
      # it without requiring the path to be a Nix path literal.
      #
      # Supports both the full { pkgs, workspaces, utils } convention and the
      # simplified { pkgs, utils, ... } consumer convention.
      #
      # Usage (generated runtime flake in entrypoint.sh):
      #
      #   mkWs = alice-module.lib.mkWorkspaceFromFile pkgs;
      #   packages.${system}.workspace = mkWs "/workspace/source/.alice/workspace.nix";
      # -----------------------------------------------------------------------
      lib.mkWorkspaceFromFile = pkgs:
        (mkEngine pkgs self).mkWorkspaceFromFile;

      # -----------------------------------------------------------------------
      # Per-system outputs
      # -----------------------------------------------------------------------
      packages = forEachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          engine = mkEngine pkgs self;
          mkWs   = engine.mkWorkspace;
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
