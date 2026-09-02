# examples/sample-workspace/default.nix
#
# Sample upstream workspace definition — demonstrates every supported field.
#
# This file is imported directly by mkWorkspace and also by the extending
# workspace in examples/workspace.nix, which overrides and adds to the
# config defined here.

{ pkgs, workspaces, utils }:

{
  workspaces."sample-workspace" = {

    # -------------------------------------------------------------------------
    # workspace.gitTools
    #
    # Options declared by the injected git-tools NixOS module.  The module
    # contributes rules, a skill, and packages only when enable = true.
    # Individual features can be turned off independently.
    # -------------------------------------------------------------------------
    workspace.gitTools.enable = true;
    # workspace.gitTools.rules    = false;  # uncomment to suppress git-rules.md
    # workspace.gitTools.skill    = false;  # uncomment to suppress GitWorkflow.md
    # workspace.gitTools.packages = false;  # uncomment to skip git + delta

    # -------------------------------------------------------------------------
    # workspace.file
    #
    # Arbitrary files written into the root of the target directory.
    # Values are either plain strings (coerced to { text = …; }) or
    # { text = …; } / { source = …; } submodules.
    # Set dontIgnore = true to exclude a file from the auto-.gitignore.
    # -------------------------------------------------------------------------
    workspace.file."README.md" = {
      dontIgnore = true;   # project README should stay tracked in git
      text = ''
        # sample-workspace

        This directory was provisioned by the sample-workspace alice-module example.
      '';
    };

    workspace.file."config/settings.json" = builtins.toJSON {
      theme   = "dark";
      autosave = true;
    };

    # -------------------------------------------------------------------------
    # workspace.bob.rules
    #
    # Markdown rule files written under .bob/rules/ in the target directory.
    # -------------------------------------------------------------------------
    workspace.bob.rules."sample-rules.md" = ''
      # Sample rules

      - Always write tests.
      - Prefer explicit over implicit.
    '';

    # -------------------------------------------------------------------------
    # workspace.bob.skills
    #
    # Skill files written under .bob/skills/ in the target directory.
    # -------------------------------------------------------------------------
    workspace.bob.skills."SampleSkill.md" = ''
      ---
      name: sample-skill
      description: A placeholder skill installed by the sample workspace.
      ---

      This skill does nothing yet — replace with real content.
    '';

    # -------------------------------------------------------------------------
    # workspace.bob.mcpServers
    #
    # MCP server registrations written into .bob/mcp.json.
    # Use `type`/`url`/`headers` for HTTP servers; `command`/`args`/`env` for
    # stdio servers.
    # -------------------------------------------------------------------------
    workspace.bob.mcpServers."sample-stdio-server" = {
      command     = "${pkgs.nodejs}/bin/node";
      args        = [ "/path/to/server.js" ];
      env         = { LOG_LEVEL = "info"; };
      alwaysAllow = [ "read" ];
    };

    workspace.bob.mcpServers."sample-http-server" = {
      type    = "http";
      url     = "https://mcp.example.com/";
      headers = { Authorization = "Bearer \${env:EXAMPLE_TOKEN}"; };
    };

    # -------------------------------------------------------------------------
    # workspace.packages
    #
    # Nix packages whose binaries are symlinked into .local/bin/.
    # -------------------------------------------------------------------------
    workspace.packages = [ pkgs.ripgrep pkgs.jq ];

  };
}
