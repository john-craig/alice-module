# .alice/workspace.nix — Alice workspace configuration for this repository
#
# This file shows two ways to configure a workspace:
#
# ── Option A: pull a shared workspace from alice-workspaces (recommended) ────
#
#   Use this when a named workspace already exists in alice-workspaces that
#   matches your project's needs.  The workspace definition is fetched from
#   the shared repo at a pinned revision so it is reproducible.
#
# ── Option B: define your own workspace inline ────────────────────────────────
#
#   Use this for project-specific configuration that does not belong in the
#   shared alice-workspaces repo.
#
# ─────────────────────────────────────────────────────────────────────────────

{ pkgs, utils, ... }:

let
  # ---------------------------------------------------------------------------
  # Pin the alice-workspaces repository at a specific revision.
  # Update `rev` whenever you want to pick up new shared workspace definitions.
  # ---------------------------------------------------------------------------
  alice-workspaces = builtins.fetchGit {
    url = "ssh://git@github.com/your-org/alice-workspaces.git";
    ref = "main";
  };

in

# ---------------------------------------------------------------------------
# Option A — use the shared "blank" workspace from alice-workspaces
#
# Switch "blank" to any other workspace name defined in your alice-workspaces
# repo to get that workspace's full set of skills, rules, and MCP servers.
# ---------------------------------------------------------------------------
(import "${alice-workspaces}/workspaces/blank/default.nix")
  { inherit pkgs utils; workspaces = {}; }

# ---------------------------------------------------------------------------
# Option B — define your own workspace inline (comment out Option A above
# and uncomment this block instead)
# ---------------------------------------------------------------------------
# {
#   name = "alice-module-sample";
#
#   workspace.file."README-alice.txt".text = ''
#     This workspace was provisioned by Alice.
#   '';
#
#   workspace.packages = [ pkgs.git pkgs.curl ];
# }
