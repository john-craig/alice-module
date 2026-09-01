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
#   alice switch --file ./my-workspace.nix --target /path/to/dir
#   alice switch --file ./my-workspace.nix --name my-ws --target .
#
# Subcommands
# -----------
#   init      Create a .alice/workspace.nix starter file in the target directory.
#             Options:
#               -t, --target    <dir>    Directory to initialise (defaults to .).
#               -f, --force              Overwrite an existing workspace.nix.
#
#   switch    Evaluate the workspace file and provision the target directory.
#             Defaults: --file .alice/workspace.nix  --target .
#             Options:
#               -f, --file      <file>   Path to the workspace.nix module file.
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
    { workspaceFile, wsName, system, wsNative }:
    let
      pkgs   = import <nixpkgs> { inherit system; };
      native = wsNative == "1";
      engine = import "${workspacesModule}" {
        inherit pkgs;
        flakeRoot      = builtins.dirOf workspaceFile;
        nativeOverride = native;
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
      -f, --file         <file>   Path to workspace.nix (default: .alice/workspace.nix).
      -t, --target       <dir>    Target directory to provision (default: current directory).
      -n, --name         <name>   Workspace name key inside the file.
                                  Defaults to the first key found in the file.
      -s, --system       <sys>    Nix system string (defaults to the running system).
          --native                Force workspace.native = true (overrides the module).
          --no-native             Force workspace.native = false (overrides the module).
          --host-binaries <file>  Path to the host binaries manifest used when
                                  native = false (default: .alice/host-binaries inside
                                  the target directory).  The manifest is a plain text
                                  file with one executable name per line.
      -h, --help                  Show this help message.

    Examples:
      alice init
      alice init --target ~/projects/my-project
      alice switch
      alice switch --file ./workspace.nix --target .
      alice switch -f ~/projects/my-ws/workspace.nix -t ~/projects/my-ws
      alice switch -f ./workspace.nix -t . --name my-workspace
      alice switch --no-native
      alice switch --no-native --host-binaries /etc/alice/host-binaries
      alice switch --native
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
    # .alice/workspace.nix
    #
    # Alice workspace configuration for this repository.
    #
    # Run `alice switch` from this directory to provision the workspace.
    #
    # Every option below is commented out — uncomment and fill in the sections
    # you need.  The workspace name ("my-workspace") is used as the key passed
    # to `alice switch --name`; it defaults to the first key found in this file
    # so you do not normally need to pass it explicitly.

    { pkgs, utils, ... }:

    {
      workspaces."my-workspace" = {

        # -----------------------------------------------------------------------
        # workspace.file
        #
        # Arbitrary files written into the root of the target directory.
        #
        # The attribute name is the relative destination path.  Values are either
        # a plain string (coerced to { text = …; }) or a submodule:
        #
        #   { text = "…"; }              — inline content
        #   { source = /nix/store/path; } — copy a file from the Nix store
        #
        # Set dontIgnore = true to keep a file tracked in git rather than
        # appending it to .gitignore automatically.
        # -----------------------------------------------------------------------
        # workspace.file."README.md" = {
        #   dontIgnore = true;
        #   text = '''
        #     # my-workspace
        #
        #     This directory was provisioned by Alice.
        #   ''';
        # };
        #
        # workspace.file."config/settings.json" = builtins.toJSON {
        #   theme    = "dark";
        #   autosave = true;
        # };

        # -----------------------------------------------------------------------
        # workspace.bob.rules
        #
        # Markdown rule files written under .bob/rules/ in the target directory.
        # Bob reads these automatically as project-specific instructions.
        # -----------------------------------------------------------------------
        # workspace.bob.rules."my-rules.md" = '''
        #   # My rules
        #
        #   - Always write tests.
        #   - Prefer explicit over implicit.
        # ''';

        # -----------------------------------------------------------------------
        # workspace.bob.skills
        #
        # Skill files written under .bob/skills/ in the target directory.
        #
        # Skills can be defined inline (text = ) or pulled from an upstream
        # repository using utils.repo (see the fetchGit example in the let block
        # below).
        # -----------------------------------------------------------------------
        # workspace.bob.skills."MySkill.md" = '''
        #   ---
        #   name: my-skill
        #   description: Describe what this skill does in one sentence.
        #   ---
        #
        #   Detailed skill instructions go here.
        # ''';
        #
        # — or pull a skill file from an upstream repo (uncomment the
        #   `my-skills-repo` fetchGit block in the let section below first) —
        #
        # workspace.bob.skills."UpstreamSkill.md" = {
        #   source = utils.repo my-skills-repo "skills/UpstreamSkill.md";
        # };

        # -----------------------------------------------------------------------
        # workspace.bob.mcpServers
        #
        # MCP server registrations written into .bob/mcp.json.
        #
        # Stdio server  — launched as a local subprocess:
        #   command     = absolute path to the executable
        #   args        = list of CLI arguments
        #   env         = environment variables for the subprocess
        #   alwaysAllow = tool names auto-approved without user confirmation
        #
        # HTTP server   — contacted over the network:
        #   type        = "streamable-http"  (or "http" for legacy SSE)
        #   url         = server base URL
        #   headers     = HTTP headers sent with every request (e.g. auth tokens)
        #   alwaysAllow = tool names auto-approved without user confirmation
        # -----------------------------------------------------------------------
        # workspace.bob.mcpServers."my-stdio-server" = {
        #   command     = "/path/to/server";
        #   args        = [ "/path/to/server.js" ];
        #   env         = { LOG_LEVEL = "info"; };
        #   alwaysAllow = [ "read" ];
        # };
        #
        # workspace.bob.mcpServers."my-http-server" = {
        #   type    = "streamable-http";
        #   url     = "https://mcp.example.com/";
        #   headers = { Authorization = "Bearer ''${env:MY_TOKEN}"; };
        # };

        # -----------------------------------------------------------------------
        # workspace.packages
        #
        # Nix packages whose binaries are symlinked into .local/bin/ in the
        # target directory, making them available without altering $PATH globally.
        # -----------------------------------------------------------------------
        # workspace.packages = [ pkgs.ripgrep pkgs.jq ];

        # -----------------------------------------------------------------------
        # workspace.native
        #
        # Set to false when provisioning an environment where the Nix store is
        # not available (containers, restricted CI runners, etc.).  In non-native
        # mode the engine rejects workspace.packages, source-based file entries,
        # and MCP server commands that start with /nix/store/.
        #
        # Default: true
        # -----------------------------------------------------------------------
        # workspace.native = true;

        # -----------------------------------------------------------------------
        # workspace.assertHostBinaries
        #
        # Short executable names that must be present on the target host when
        # workspace.native = false.  At provision time alice checks each name
        # against a host binaries manifest file (default: .alice/host-binaries in
        # the target directory; override with --host-binaries <file>).
        #
        # Produce the manifest by running, e.g.:
        #   ls /usr/local/bin /usr/bin /bin | sort -u > .alice/host-binaries
        #
        # Ignored (with a warning) when workspace.native = true.
        # -----------------------------------------------------------------------
        # workspace.assertHostBinaries = [ "node" "npx" ];

      };
    }

    # ---------------------------------------------------------------------------
    # To pull files from an external git repository, add a fetchGit call in a
    # let block and reference it with utils.repo:
    #
    # { pkgs, utils, ... }:
    #
    # let
    #   my-skills-repo = builtins.fetchGit {
    #     url = "ssh://git@github.com/your-org/your-skills-repo.git";
    #     ref = "main";
    #     # Pin to a specific commit for reproducibility:
    #     # rev = "abc1234...";
    #   };
    # in
    # {
    #   workspaces."my-workspace" = {
    #     workspace.bob.skills."UpstreamSkill.md" = {
    #       source = utils.repo my-skills-repo "skills/UpstreamSkill.md";
    #     };
    #   };
    # }
    # ---------------------------------------------------------------------------
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
      local ws_native=""           # "" = defer to module; "1" = native; "0" = non-native
      local host_binaries_file=""  # "" = use default (.alice/host-binaries in target dir)

      # Parse options
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -f|--file)           workspace_file="$2";    shift 2 ;;
          -t|--target)         target_dir="$2";        shift 2 ;;
          -n|--name)           ws_name="$2";           shift 2 ;;
          -s|--system)         nix_system="$2";        shift 2 ;;
          --native)            ws_native="1";          shift   ;;
          --no-native)         ws_native="0";          shift   ;;
          --host-binaries)     host_binaries_file="$2"; shift 2 ;;
          -h|--help)           usage; exit 0 ;;
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

      # Auto-detect workspace.native if not overridden on the command line.
      local ws_native_resolved
      if [ -n "$ws_native" ]; then
        ws_native_resolved="$ws_native"
      else
        ws_native_resolved="$(nix eval --impure --raw --expr "
          let
            pkgs = import <nixpkgs> {};
            mod  = import $workspace_file {
              inherit pkgs;
              utils      = { root = p: p; repo = _: p: p; };
              workspaces = {};
            };
            ws = mod.workspaces.\"$ws_name\" or {};
            native = (ws.workspace or {}).native or true;
          in
          if native then \"1\" else \"0\"
        " 2>/dev/null)" || true
        # Default to native if eval fails or returns nothing
        if [ -z "$ws_native_resolved" ]; then
          ws_native_resolved="1"
        fi
      fi

      # ---------------------------------------------------------------------------
      # Host binaries manifest check (non-native mode only)
      # ---------------------------------------------------------------------------
      if [ "$ws_native_resolved" = "0" ]; then
        # Resolve manifest path
        local manifest_path
        if [ -n "$host_binaries_file" ]; then
          manifest_path="$host_binaries_file"
        else
          manifest_path="$target_dir/.alice/host-binaries"
        fi

        # Read assertHostBinaries from the workspace module
        local assert_binaries_json
        assert_binaries_json="$(nix eval --impure --json --expr "
          let
            pkgs = import <nixpkgs> {};
            mod  = import $workspace_file {
              inherit pkgs;
              utils      = { root = p: p; repo = _: p: p; };
              workspaces = {};
            };
            ws = mod.workspaces.\"$ws_name\" or {};
          in
          (ws.workspace or {}).assertHostBinaries or []
        " 2>/dev/null)" || assert_binaries_json="[]"

        # Only proceed with manifest check if assertHostBinaries is non-empty
        if [ "$assert_binaries_json" != "[]" ] && [ -n "$assert_binaries_json" ]; then
          if [ ! -f "$manifest_path" ]; then
            echo "alice switch: host binaries manifest not found: $manifest_path" >&2
            echo "              Create the manifest with one binary name per line, e.g.:" >&2
            echo "                ls /usr/local/bin /usr/bin /bin | sort -u > $manifest_path" >&2
            echo "              Or pass --host-binaries <file> to specify a different path." >&2
            exit 1
          fi

          # Check each asserted binary is present in the manifest.
          # nix eval --json gives us a JSON array; we iterate with a simple
          # approach using nix itself to print newline-separated names.
          local assert_binaries_list
          assert_binaries_list="$(nix eval --impure --raw --expr "
            let
              pkgs = import <nixpkgs> {};
              mod  = import $workspace_file {
                inherit pkgs;
                utils      = { root = p: p; repo = _: p: p; };
                workspaces = {};
              };
              ws = mod.workspaces.\"$ws_name\" or {};
              bins = (ws.workspace or {}).assertHostBinaries or [];
            in
            pkgs.lib.concatStringsSep \"\n\" bins
          " 2>/dev/null)" || assert_binaries_list=""

          local missing_binaries=""
          while IFS= read -r bin_name; do
            [ -z "$bin_name" ] && continue
            if ! grep -qxF "$bin_name" "$manifest_path"; then
              missing_binaries="$missing_binaries $bin_name"
            fi
          done <<< "$assert_binaries_list"

          if [ -n "$missing_binaries" ]; then
            echo "alice switch: the following host binaries are declared in workspace.assertHostBinaries" >&2
            echo "              but are not listed in the manifest ($manifest_path):" >&2
            for b in $missing_binaries; do
              echo "                - $b" >&2
            done
            echo "              Add the missing names to the manifest, or fix workspace.assertHostBinaries." >&2
            exit 1
          fi
        fi
      else
        # Native mode: warn if assertHostBinaries is non-empty (it will be ignored)
        local native_assert_check
        native_assert_check="$(nix eval --impure --raw --expr "
          let
            pkgs = import <nixpkgs> {};
            mod  = import $workspace_file {
              inherit pkgs;
              utils      = { root = p: p; repo = _: p: p; };
              workspaces = {};
            };
            ws = mod.workspaces.\"$ws_name\" or {};
            bins = (ws.workspace or {}).assertHostBinaries or [];
          in
          if bins != [] then \"nonempty\" else \"\"
        " 2>/dev/null)" || native_assert_check=""

        if [ "$native_assert_check" = "nonempty" ]; then
          echo "alice: warning: workspace.assertHostBinaries is set but workspace.native = true; host binary assertions will not be checked." >&2
        fi
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
        --argstr wsNative      "$ws_native_resolved" \
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
