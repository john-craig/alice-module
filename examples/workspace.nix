# examples/workspace.nix
#
# Extended workspace — demonstrates how to use the .override method to build
# on an upstream workspace definition without forking it.
#
# This file is a standard workspace module (a function of { pkgs, workspaces,
# utils }) so it works with both alice switch and mkWorkspaceConfig/mkWorkspace.
# Internally it builds an upstream workspace configuration object and calls
# .override on it, then returns the overridden config block under the new name.
#
# .override receives the raw config block and must return a (possibly modified)
# config block.  Use the same Nix attribute operators you would use in a normal
# workspace config block:
#
#   //   — shallow-merge attrsets (override individual files/rules/servers)
#   ++   — append lists (add packages without dropping upstream ones)
#
# The result is a fresh workspace configuration object that is completely
# independent of the upstream one — both can be provisioned separately.

{ pkgs, workspaces, utils }:

let
  # ---------------------------------------------------------------------------
  # Build a workspace configuration object for the upstream module.
  #
  # We import the engine so we can call mkWorkspaceConfig and receive a
  # configuration object with .override available.
  # ---------------------------------------------------------------------------
  engine = import ../modules/workspaces.nix {
    inherit pkgs;
    flakeRoot = builtins.dirOf (builtins.toString ./workspace.nix);
  };

  base = engine.mkWorkspaceConfig "sample-workspace"
           ./sample-workspace/default.nix
           { extraModules = [ ./modules/git-tools.nix ]; };

  # ---------------------------------------------------------------------------
  # Apply overrides.
  #
  # The closure receives the raw config block (cfg) and returns a new one.
  # Every upstream key that is not mentioned here is preserved as-is.
  # ---------------------------------------------------------------------------
  extended = base.override (cfg: cfg // {

    # workspace.file — keep all upstream files, override README, add a new one.
    workspace.file = cfg.workspace.file // {
      # Override the upstream README with content specific to this workspace.
      "README.md" = {
        dontIgnore = true;
        text = ''
          # extended-workspace

          This workspace extends sample-workspace with additional configuration.
        '';
      };

      # Add a new file not present in the upstream workspace.
      "extended-notes.md" = ''
        # Extended workspace notes

        This file is only present in the extended workspace.
      '';
    };

    # workspace.bob.rules — keep upstream rules, add an extra one.
    workspace.bob.rules = cfg.workspace.bob.rules // {
      "extended-rules.md" = ''
        # Extended rules

        - Follow all upstream rules.
        - Additionally: document every public function.
      '';
    };

    # workspace.bob.mcpServers — keep upstream servers, override the HTTP one.
    workspace.bob.mcpServers = cfg.workspace.bob.mcpServers // {
      # Replace the upstream HTTP server entry with a different URL.
      "sample-http-server" = {
        type    = "http";
        url     = "https://mcp.extended-example.com/";
        headers = { Authorization = "Bearer \${env:EXTENDED_TOKEN}"; };
      };
    };

    # workspace.packages — append to the upstream list rather than replacing it.
    workspace.packages = cfg.workspace.packages ++ [ pkgs.fd ];

  });

in
# Expose the overridden config block under the new workspace name.
# The engine that imports this file reads workspaces."extended-workspace" as
# the raw config block and evaluates it with lib.evalModules.
{
  workspaces."extended-workspace" = extended.configBlock;
}
