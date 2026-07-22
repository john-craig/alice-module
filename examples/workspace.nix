# examples/workspace.nix
#
# Extended workspace — demonstrates how to override and extend an upstream
# workspace definition without forking it.
#
# Pattern
# -------
# 1. Import the upstream module file and extract the config block you want to
#    build on.
# 2. Construct a new config block using Nix attribute merging:
#      //    — shallow-merge attrsets (override individual files/servers/rules)
#      ++    — append lists (add packages without dropping upstream ones)
#    For nested attrsOf options (file, rules, skills, mcpServers), merge at
#    that level so upstream entries are preserved unless explicitly replaced.
# 3. Pass the merged block as the config to mkWorkspace under a new name.
#
# The resulting derivation is completely independent of the upstream one —
# both can be run separately and provision different directories.

{ pkgs, workspaces, utils }:

let
  # -------------------------------------------------------------------------
  # Import the upstream workspace module.
  #
  # We call it with the same argument set the engine would use so the upstream
  # file evaluates normally.  We then pick out just the config block we want
  # to extend.
  # -------------------------------------------------------------------------
  upstream = import ./sample-workspace/default.nix { inherit pkgs workspaces utils; };

  # The upstream config block for "sample-workspace".
  base = upstream.workspaces."sample-workspace";

in
{
  workspaces."extended-workspace" =

    # -------------------------------------------------------------------------
    # Merge the upstream config into the new workspace.
    #
    # `base` already contains workspace.file, workspace.bob.*, and
    # workspace.packages from the upstream definition.  We then override or
    # extend each option selectively below.
    # -------------------------------------------------------------------------
    base // {

      # workspace.file — keep all upstream files, override README, add a new one.
      workspace.file =
        base.workspace.file // {
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
      workspace.bob.rules =
        base.workspace.bob.rules // {
          "extended-rules.md" = ''
            # Extended rules

            - Follow all upstream rules.
            - Additionally: document every public function.
          '';
        };

      # workspace.bob.mcpServers — keep upstream servers, override the HTTP one.
      workspace.bob.mcpServers =
        base.workspace.bob.mcpServers // {
          # Replace the upstream HTTP server entry with a different URL.
          "sample-http-server" = {
            type    = "http";
            url     = "https://mcp.extended-example.com/";
            headers = { Authorization = "Bearer \${env:EXTENDED_TOKEN}"; };
          };
        };

      # workspace.packages — append to the upstream list rather than replacing it.
      workspace.packages =
        base.workspace.packages ++ [ pkgs.fd ];

    };
}
