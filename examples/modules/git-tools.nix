# examples/modules/git-tools.nix
#
# NixOS-style workspace module that contributes git-related configuration.
#
# Declares options under the workspace.gitTools.* namespace.  Each feature
# is independently toggled so workspaces can enable only what they need.
# Configuration is only contributed when the corresponding option is true —
# no files or packages are written unless explicitly enabled.
#
# Options declared:
#
#   workspace.gitTools.enable       (bool, default: false)
#     Master switch.  Must be true for any other gitTools option to take effect.
#
#   workspace.gitTools.rules        (bool, default: true)
#     Write a git commit-message rule file under .bob/rules/.
#
#   workspace.gitTools.skill        (bool, default: true)
#     Write a GitWorkflow skill file under .bob/skills/.
#
#   workspace.gitTools.packages     (bool, default: true)
#     Add git and delta to workspace.packages.
#
# Usage in a workspace config block:
#
#   workspace.gitTools.enable = true;
#   # workspace.gitTools.packages = false;  # skip packages; keep rules + skill
#
# Pass this file via extraModules when building the workspace:
#
#   mkWsCfg "my-workspace" ./workspace.nix
#     { extraModules = [ ./modules/git-tools.nix ]; }

{ pkgs, lib, config, ... }:

{
  options.workspace.gitTools = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Master switch for the git-tools module.  When false (the default),
        no rules, skills, or packages are contributed regardless of the other
        gitTools options.
      '';
    };

    rules = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        When true (and enable = true), write git commit-message conventions
        to .bob/rules/git-rules.md in the target directory.
      '';
    };

    skill = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        When true (and enable = true), write a GitWorkflow skill file to
        .bob/skills/GitWorkflow.md in the target directory.
      '';
    };

    packages = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        When true (and enable = true), add git and delta to
        workspace.packages so their binaries are symlinked into .local/bin/.
      '';
    };

  };

  config = lib.mkIf config.workspace.gitTools.enable {

    workspace.bob.rules = lib.mkIf config.workspace.gitTools.rules {
      "git-rules.md" = ''
        # Git rules

        - Write commit messages in the imperative mood ("Add feature", not "Added feature").
        - Keep the subject line under 72 characters.
        - Reference issue numbers in the footer when applicable (e.g. `Fixes #42`).
        - Prefer small, focused commits over large, mixed-concern ones.
      '';
    };

    workspace.bob.skills = lib.mkIf config.workspace.gitTools.skill {
      "GitWorkflow.md" = ''
        ---
        name: git-workflow
        description: Common git workflow operations — branching, committing, and PR preparation.
        ---

        ## Branching

        Create a feature branch from the default branch:

        ```bash
        git switch -c feature/my-feature
        ```

        ## Committing

        Stage changes selectively and write a focused commit message:

        ```bash
        git add -p
        git commit -m "Add my feature"
        ```

        ## Preparing a pull request

        Rebase onto the default branch before opening a PR to keep history linear:

        ```bash
        git fetch origin
        git rebase origin/main
        ```
      '';
    };

    workspace.packages = lib.mkIf config.workspace.gitTools.packages
      [ pkgs.git pkgs.delta ];

  };
}
