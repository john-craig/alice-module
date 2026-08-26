# packages/alice/default.nix
#
# The `alice` command-line tool.
#
# Inspired by `home-manager` and `nixos-rebuild`, alice is the imperative
# front-end for the alice-module workspace system.  Rather than building a
# pre-baked workspace derivation at `nix build` time, it accepts a
# workspace.nix file and a target directory at *runtime* and provisions the
# directory on the spot — the workspace evaluation still happens in a Nix
# sandbox, but is driven by the user's local file.
#
# Usage
# -----
#   alice init [--target <dir>]
#   alice switch
#   alice switch --workspace ./my-workspace.nix --target /path/to/dir
#   alice switch --workspace ./my-workspace.nix --name my-ws --target .
#
# Subcommands
# -----------
#   init      Create a .alice/workspace.nix starter file in the target directory.
#             Options:
#               -t, --target    <dir>    Directory to initialise (defaults to .).
#               -f, --force              Overwrite an existing workspace.nix.
#
#   switch    Evaluate the workspace file and provision the target directory.
#             Defaults: --workspace .alice/workspace.nix  --target .
#             Options:
#               -w, --workspace <file>   Path to the workspace.nix module file.
#               -t, --target    <dir>    Target directory to provision.
#               -n, --name      <name>   Workspace name key inside the file.
#                                        If omitted, the first key in
#                                        `workspaces` is used automatically.
#               -s, --system    <sys>    Nix system string (defaults to
#                                        builtins.currentSystem).
#
# How it works
# ------------
# A helper Nix expression file (`alice-build-workspace.nix`) is embedded into
# the derivation at build time via pkgs.writeText.  Its store path and the
# store path of `modules/workspaces.nix` are baked into the shell script.
#
# At runtime `alice switch`:
#   1. Resolves the workspace name (auto-detected or explicit).
#   2. Runs `nix build --impure -f alice-build-workspace.nix --arg workspaceFile …`
#      to produce the workspace provisioning derivation.  All variable data is
#      passed via --arg / --argstr so no shell variable appears inside a Nix
#      expression string.
#   3. Runs the produced `workspace-<name>` script against the target directory.

{ pkgs, workspacesModule }:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # alice-build-workspace.nix
  #
  # Used at runtime as:
  #   nix build --impure --no-link --print-out-paths
  #       --arg    workspaceFile /abs/path/workspace.nix
  #       --argstr wsName        my-workspace
  #       --argstr system        x86_64-linux
  #       -f alice-build-workspace.nix
  #
  # The workspacesModule store path is baked in at build time via Nix string
  # interpolation here (inside a pkgs.writeText, which is a regular Nix string,
  # so ${workspacesModule} is valid Nix interpolation).
  # ---------------------------------------------------------------------------
  buildWorkspaceExpr = pkgs.writeText "alice-build-workspace.nix" ''
    { workspaceFile, wsName, system }:
    let
      pkgs   = import <nixpkgs> { inherit system; };
      engine = import "${workspacesModule}" {
        inherit pkgs;
        flakeRoot = builtins.dirOf workspaceFile;
      };
    in
    engine wsName workspaceFile
  '';

in
pkgs.writeShellApplication {
  name = "alice";

  runtimeInputs = [
    pkgs.nix
    pkgs.coreutils
    pkgs.gnugrep
  ];

  text = ''
    # ---------------------------------------------------------------------------
    # alice — workspace provisioning CLI
    # ---------------------------------------------------------------------------

    # Store path of the build-helper Nix expression, captured at build time.
    BUILD_WORKSPACE_NIX="${buildWorkspaceExpr}"

    usage() {
      cat <<'USAGE'
    alice — declarative workspace provisioning

    Usage:
      alice <subcommand> [OPTIONS]

    Subcommands:
      init          Create a .alice/workspace.nix starter file in a directory.
      switch        Evaluate a workspace.nix file and provision a target directory.

    Options for init:
      -t, --target  <dir>    Directory to initialise (defaults to current directory).
      -f, --force            Overwrite an existing .alice/workspace.nix.
      -h, --help             Show this help message.

    Options for switch:
      -w, --workspace <file>   Path to workspace.nix (default: .alice/workspace.nix).
      -t, --target    <dir>    Target directory to provision (default: current directory).
      -n, --name      <name>   Workspace name key inside the file.
                               Defaults to the first key found in the file.
      -s, --system    <sys>    Nix system string (defaults to the running system).
      -h, --help               Show this help message.

    Examples:
      alice init
      alice init --target ~/projects/my-project
      alice switch
      alice switch --workspace ./workspace.nix --target .
      alice switch -w ~/projects/my-ws/workspace.nix -t ~/projects/my-ws
      alice switch -w ./workspace.nix -t . --name my-workspace
    USAGE
    }

    # ---------------------------------------------------------------------------
    # cmd_init — implement `alice init`
    # ---------------------------------------------------------------------------
    cmd_init() {
      local target_dir="."
      local force=0

      while [ "$#" -gt 0 ]; do
        case "$1" in
          -t|--target) target_dir="$2"; shift 2 ;;
          -f|--force)  force=1;         shift   ;;
          -h|--help)   usage; exit 0 ;;
          *) echo "alice init: unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
      done

      if [ ! -d "$target_dir" ]; then
        echo "alice init: target directory does not exist: $target_dir" >&2
        exit 1
      fi

      local dest
      dest="$(realpath "$target_dir")/.alice/workspace.nix"

      if [ -f "$dest" ] && [ "$force" -eq 0 ]; then
        echo "alice init: $dest already exists (use --force to overwrite)" >&2
        exit 1
      fi

      mkdir -p "$(dirname "$dest")"

      cat > "$dest" <<'WORKSPACE_NIX'
    # .alice/workspace.nix — Alice workspace configuration
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
    (import "''${alice-workspaces}/workspaces/blank/default.nix")
      { inherit pkgs utils; workspaces = {}; }

    # ---------------------------------------------------------------------------
    # Option B — define your own workspace inline (comment out Option A above
    # and uncomment this block instead)
    # ---------------------------------------------------------------------------
    # {
    #   name = "my-workspace";
    #
    #   workspace.file."README-alice.txt".text = '''
    #     This workspace was provisioned by Alice.
    #   ''';
    #
    #   workspace.packages = [ pkgs.git pkgs.curl ];
    # }
    WORKSPACE_NIX

      echo "alice: created $dest"
    }

    # ---------------------------------------------------------------------------
    # cmd_switch — implement `alice switch`
    # ---------------------------------------------------------------------------
    cmd_switch() {
      local workspace_file=""
      local target_dir=""
      local ws_name=""
      local nix_system=""

      # Parse options
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -w|--workspace) workspace_file="$2"; shift 2 ;;
          -t|--target)    target_dir="$2";     shift 2 ;;
          -n|--name)      ws_name="$2";        shift 2 ;;
          -s|--system)    nix_system="$2";     shift 2 ;;
          -h|--help)      usage; exit 0 ;;
          *) echo "alice switch: unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
      done

      # Apply defaults
      if [ -z "$workspace_file" ]; then
        workspace_file=".alice/workspace.nix"
      fi
      if [ -z "$target_dir" ]; then
        target_dir="."
      fi

      # Resolve to absolute paths so Nix can reference them as path literals
      workspace_file="$(realpath "$workspace_file")"

      if [ ! -f "$workspace_file" ]; then
        echo "alice switch: workspace file not found: $workspace_file" >&2
        exit 1
      fi

      if [ ! -d "$target_dir" ]; then
        echo "alice switch: target directory does not exist: $target_dir" >&2
        exit 1
      fi

      target_dir="$(realpath "$target_dir")"

      # Determine system string
      if [ -z "$nix_system" ]; then
        nix_system="$(nix eval --impure --raw --expr 'builtins.currentSystem')"
      fi

      # Auto-detect workspace name if not supplied.
      #
      # The workspace file path is an absolute path produced by `realpath`, so
      # it is safe to splice directly into a Nix --expr string as a bare path
      # literal (e.g. /home/user/workspace.nix is valid unquoted Nix syntax).
      # This avoids the need for a separate helper .nix file and bypasses the
      # `nix eval -f <func>` limitation where --arg is not applied automatically.
      if [ -z "$ws_name" ]; then
        ws_name="$(nix eval --impure --raw --expr "
          let
            pkgs = import <nixpkgs> {};
            mod  = import $workspace_file {
              inherit pkgs;
              utils      = { root = p: p; repo = _: p: p; };
              workspaces = {};
            };
          in
          builtins.head (builtins.attrNames mod.workspaces)
        " 2>/dev/null)" || true

        if [ -z "$ws_name" ]; then
          echo "alice switch: could not auto-detect workspace name from $workspace_file" >&2
          echo "              Pass --name <name> explicitly." >&2
          exit 1
        fi
        echo "alice: detected workspace name '$ws_name'"
      fi

      echo "alice: building workspace '$ws_name' for $nix_system ..."

      # Build the workspace provisioning derivation.
      # alice-build-workspace.nix is a function — nix build -f applies it
      # automatically via --arg / --argstr, keeping all variable data out of
      # Nix expression strings.
      result="$(nix build --impure --no-link --print-out-paths \
        --arg    workspaceFile "$workspace_file" \
        --argstr wsName        "$ws_name" \
        --argstr system        "$nix_system" \
        -f "$BUILD_WORKSPACE_NIX")"

      echo "alice: provisioning '$target_dir' ..."
      "$result/bin/workspace-$ws_name" "$target_dir"
      echo "alice: done."
    }

    # ---------------------------------------------------------------------------
    # Entry point — dispatch on subcommand
    # ---------------------------------------------------------------------------
    if [ "$#" -eq 0 ]; then
      usage
      exit 1
    fi

    subcommand="$1"
    shift

    case "$subcommand" in
      init)      cmd_init   "$@" ;;
      switch)    cmd_switch "$@" ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "alice: unknown subcommand: $subcommand" >&2
        usage >&2
        exit 1
        ;;
    esac
  '';
}
