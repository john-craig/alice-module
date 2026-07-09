{
  description = "Declarative development-environment provisioning for Bob";

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
      # lib.mkEnvironment
      #
      # Build an environment derivation from a module file.
      #
      # Usage:
      #
      #   let
      #     envs = inputs.dev-envs;
      #     pkgs = import inputs.nixpkgs { inherit system; };
      #     mkEnv = envs.lib.mkEnvironment pkgs;
      #   in {
      #     packages.my-env = mkEnv "my-env" ./environments/my-env/default.nix;
      #   }
      #
      # The module file must follow the convention described in
      # modules/environments.nix — a function of { pkgs, envs, utils } that
      # returns { envs."<name>" = { environment = ...; }; }.
      #
      # `utils.root relPath` resolves a path relative to the *calling* flake's
      # root.  Pass `flakeRoot` (the second arg to mkEnvironment) to customise
      # this; if omitted it defaults to the root of *this* flake (useful for
      # the built-in example environments).
      # -----------------------------------------------------------------------
      lib.mkEnvironment = pkgs:
        let
          # When consumers call this from their own flake they will import
          # modules/environments.nix with their own flakeRoot.  The default
          # here points at this flake's own root so the built-in example
          # environments resolve correctly.
          engine = import ./modules/environments.nix {
            inherit pkgs;
            flakeRoot = self;
          };
        in
        engine;

      # -----------------------------------------------------------------------
      # lib.mkEnvironmentIn
      #
      # Like lib.mkEnvironment but lets the caller supply a custom flakeRoot
      # so that utils.root resolves relative to their own repository.
      #
      # Usage (in a downstream flake):
      #
      #   packages.my-env =
      #     inputs.dev-envs.lib.mkEnvironmentIn pkgs myFlake.self
      #       "my-env" ./environments/my-env/default.nix;
      # -----------------------------------------------------------------------
      lib.mkEnvironmentIn = pkgs: flakeRoot:
        import ./modules/environments.nix { inherit pkgs flakeRoot; };

      # -----------------------------------------------------------------------
      # Per-system outputs
      # -----------------------------------------------------------------------
      packages = forEachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          mkEnv = self.lib.mkEnvironment pkgs;
        in
        {
          # ------------------------------------------------------------------
          # Sample package
          # ------------------------------------------------------------------
          hello = pkgs.callPackage ./packages/hello { inherit pkgs; };

          # ------------------------------------------------------------------
          # Example environment: blank
          #
          # A minimal environment that writes a single hello.txt file.
          # Run with:  nix run .#env-blank -- /path/to/target-dir
          # ------------------------------------------------------------------
          env-blank = mkEnv "blank" ./environments/blank/default.nix;

          # Default package: the blank environment (demonstrates the machinery)
          default = mkEnv "blank" ./environments/blank/default.nix;
        }
      );

      apps = forEachSystem (system: {
        env-blank = {
          type    = "app";
          program = "${self.packages.${system}.env-blank}/bin/env-blank";
        };

        default = {
          type    = "app";
          program = "${self.packages.${system}.env-blank}/bin/env-blank";
        };
      });
    };
}
