# modules/workspaces.nix
#
# Core workspace-building machinery.
#
# This module is imported by flake.nix and re-exported as
# `self.lib.mkWorkspace` / `self.lib.mkWorkspaceFromFile` so that downstream
# flake consumers can call it directly.
#
# ── Public API ───────────────────────────────────────────────────────────────
#
#   mkWorkspace pkgs name moduleFile
#
#     Build a workspace derivation from a module file that uses the full
#     { pkgs, workspaces, utils } calling convention.
#
#     `pkgs`       – a nixpkgs package set
#     `name`       – the workspace name string, e.g. "my-workspace"
#     `moduleFile` – a Nix path to the workspace module
#
#   mkWorkspaceFromFile pkgs workspaceNixPath
#
#     Build a workspace derivation from a consuming repository's
#     .alice/workspace.nix.  The file may use either the full
#     { pkgs, workspaces, utils } convention OR the simplified
#     { pkgs, utils, ... } convention shown below.
#
#     `pkgs`              – a nixpkgs package set
#     `workspaceNixPath`  – an absolute path string to the workspace.nix file
#                           (typically mounted at runtime inside the container)
#
# ── Workspace module conventions ─────────────────────────────────────────────
#
# Full convention (original; preserves full backwards compatibility):
#
#   { pkgs, workspaces, utils }:
#   {
#     workspaces."my-workspace" = {
#       workspace.file."hello.txt" = "Hello, world!\n";
#       workspace.bob.rules."my-rule.md" = { source = utils.root "rules/my-rule.md"; };
#       workspace.bob.skills."MySkill.md" = { source = utils.root "skills/MySkill.md"; };
#       workspace.bob.mcpServers.my-server = {
#         command     = "${pkgs.nodejs}/bin/npx";
#         args        = [ "-y" "my-server@latest" ];
#         alwaysAllow = [ "search" ];
#       };
#       workspace.packages = [ pkgs.ripgrep ];
#     };
#   }
#
# Simplified convention (for consuming repositories):
#
#   { pkgs, utils, ... }:
#   {
#     name = "my-project";           # workspace name (default: "workspace")
#
#     workspace.file."README-alice.txt".text = ''
#       Provisioned by Alice.
#     '';
#
#     workspace.bob.rules."my-rules.md" = "# My rules\n";
#
#     workspace.packages = [ pkgs.git pkgs.curl ];
#   }
#
# `utils.root relPath`       resolves a path relative to the flake root.
# `utils.repo repo relPath`  resolves a path inside an externally fetched repo.
#
# The produced derivation is a `writeShellApplication` named `workspace-<name>`.
# Run it with a target directory to provision that directory:
#
#   workspace-my-workspace /path/to/target-dir
#
{ pkgs, flakeRoot }:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # fileEntry — submodule for a single file declaration
  #
  # Accepts either:
  #   text   = "<string contents>"   (inline text; mutually exclusive with source)
  #   source = /nix/store/path       (any Nix path; mutually exclusive with text)
  #
  # A bare string assigned to an attrsOf fileEntry option is coerced to
  # { text = "<string>"; } by the mkCoercedTo wrapper below.
  # ---------------------------------------------------------------------------
  fileEntryType = lib.types.submodule {
    options = {
      text = lib.mkOption {
        type        = lib.types.nullOr lib.types.lines;
        default     = null;
        description = "Inline text content for the file.";
      };
      source = lib.mkOption {
        type        = lib.types.nullOr lib.types.path;
        default     = null;
        description = "Nix path to copy verbatim into the target directory.";
      };
    };
  };

  # Coerce a plain string into { text = s; } so the shorthand still works.
  coercedFileEntry =
    lib.types.coercedTo lib.types.lines (s: { text = s; }) fileEntryType;

  # ---------------------------------------------------------------------------
  # workspaceOptions — the full NixOS-style module options accepted by every
  # workspace's config block.
  # ---------------------------------------------------------------------------
  workspaceOptions = {
    options.workspace = {

      assertExecutables = lib.mkOption {
        type        = lib.types.listOf lib.types.str;
        default     = [];
        description = ''
          Names of executables that must be present in the host's PATH when this
          workspace is provisioned.  alice-shell scans the host PATH and mounts
          a newline-separated list of available executable basenames at
          /alice-host/executables (ALICE_HOST_EXECUTABLES).

          At provisioning time the workspace binary reads that file and fails
          if any listed name is absent.

          If no executable list file is provided (ALICE_HOST_EXECUTABLES is
          unset) and this list is non-empty, provisioning fails — unless
          alice-shell is run with --skip-executable-check, which sets
          ALICE_SKIP_EXECUTABLE_CHECK=1 inside the container.

          Example: assert that the user has docker and git installed on the host.
        '';
        example = lib.literalExpression ''[ "docker" "git" "node" ]'';
      };

      file = lib.mkOption {
        type        = lib.types.attrsOf coercedFileEntry;
        default     = {};
        description = ''
          Files to create inside the target directory.
          The attribute name is the relative file path; the value is either
          a string (inline text) or a submodule with `text` or `source`.
        '';
        example = {
          "hello.txt"   = "Hello, world!\n";
          "config.yaml" = { source = ./config.yaml; };
        };
      };

      bob.rules = lib.mkOption {
        type        = lib.types.attrsOf coercedFileEntry;
        default     = {};
        description = ''
          Bob rule files written under `.bob/rules/` in the target directory.
          The attribute name is the relative path beneath `.bob/rules/`.
        '';
        example = {
          "dev-rules/myrules.md" = "# My rule\n";
          "dev-rules/extra.md"   = { source = ../rules/extra.md; };
        };
      };

      bob.skills = lib.mkOption {
        type        = lib.types.attrsOf coercedFileEntry;
        default     = {};
        description = ''
          Bob skill files written under `.bob/skills/` in the target directory.
          The attribute name is the relative path beneath `.bob/skills/`.
        '';
        example = {
          "MySkill.md"        = "# My skill\n";
          "extra/MySkill.md"  = { source = ../skills/MySkill.md; };
        };
      };

      bob.mcpServers = lib.mkOption {
        default     = {};
        description = ''
          MCP servers to register in `.bob/mcp.json` in the target directory.
          The attribute name is the server identifier; the value is a submodule
          describing the server's transport, command, arguments, environment
          variables, and auto-allowed tools.
        '';
        example = {
          open-websearch = {
            command     = "/nix/store/.../bin/npx";
            args        = [ "-y" "open-websearch@latest" ];
            env         = { MODE = "stdio"; };
            alwaysAllow = [ "search" "fetchWebContent" ];
          };
        };
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            type = lib.mkOption {
              type        = lib.types.nullOr lib.types.str;
              default     = null;
              description = ''
                Transport type (e.g. "streamable-http").
                Set for HTTP-based servers; omit for stdio servers.
              '';
            };
            url = lib.mkOption {
              type        = lib.types.nullOr lib.types.str;
              default     = null;
              description = "URL for HTTP-based MCP servers. Required when `type` is set.";
            };
            command = lib.mkOption {
              type        = lib.types.nullOr lib.types.str;
              default     = null;
              description = "Executable to run for stdio MCP servers. Required when `type` is null.";
            };
            args = lib.mkOption {
              type        = lib.types.listOf lib.types.str;
              default     = [];
              description = "Command-line arguments passed to the server executable.";
            };
            env = lib.mkOption {
              type        = lib.types.attrsOf lib.types.str;
              default     = {};
              description = "Environment variables set when the server process starts.";
            };
            alwaysAllow = lib.mkOption {
              type        = lib.types.listOf lib.types.str;
              default     = [];
              description = "Tool names that are auto-approved without user confirmation.";
            };
          };
        });
      };

      packages = lib.mkOption {
        type        = lib.types.listOf lib.types.package;
        default     = [];
        description = ''
          Packages whose binaries are symlinked into `.local/bin/` in the
          target directory.
        '';
        example = lib.literalExpression "[ pkgs.ripgrep pkgs.jq ]";
      };

    };
  };

  # ---------------------------------------------------------------------------
  # utils — helpers passed into every workspace module.
  #
  # `utils.root relPath`       →  <flakeRoot>/<relPath>   (a Nix path)
  # `utils.repo fetched path`  →  <fetched>/<path>        (a Nix path)
  # ---------------------------------------------------------------------------
  utils = {
    root  = relPath:        flakeRoot + "/${relPath}";
    repo  = repo: relPath: repo + "/${relPath}";
  };

  # ---------------------------------------------------------------------------
  # buildDerivation — shared derivation builder used by both mkWorkspace and
  # mkWorkspaceFromFile.
  #
  # Takes the evaluated workspace config and the name, returns the
  # writeShellApplication derivation.
  # ---------------------------------------------------------------------------
  buildDerivation = name: cfg:
    let
      toStorePath = destName: entry:
        if entry.source != null then entry.source
        else pkgs.writeText destName entry.text;

      # -----------------------------------------------------------------------
      # assertExecutablesCheck
      #
      # A shell fragment baked into the workspace script.  At run-time it:
      #   1. If workspace.assertExecutables is empty, does nothing.
      #   2. If ALICE_SKIP_EXECUTABLE_CHECK=1, prints a notice and skips.
      #      (Set by alice-shell --skip-executable-check; not a user env var.)
      #   3. If ALICE_HOST_EXECUTABLES is unset, fails with guidance.
      #   4. Reads the executable list file and fails for any name not found.
      #
      # The list of required names is embedded at build time as a Nix string
      # so there is no run-time dependency on Nix or alice-module.
      # -----------------------------------------------------------------------
      requiredExecs = cfg.assertExecutables;

      assertExecutablesCheck =
        if requiredExecs == [] then ""
        else
          let
            # Embed the list as a space-separated string of Nix-interpolated
            # names.  Each name is double-quoted so spaces (unusual but valid)
            # survive word-splitting.
            quotedNames = lib.concatMapStringsSep " " (n: ''"${n}"'') requiredExecs;
          in
          ''
            # ── workspace.assertExecutables check ─────────────────────────────
            _REQUIRED_EXECS=(${quotedNames})

            if [ "''${ALICE_SKIP_EXECUTABLE_CHECK:-0}" = "1" ]; then
              echo "  [skip] host executable check skipped (--skip-executable-check)"
            elif [ -z "''${ALICE_HOST_EXECUTABLES:-}" ]; then
              echo "" >&2
              echo "Error: workspace '${name}' requires these host executables:" >&2
              for _exe in "''${_REQUIRED_EXECS[@]}"; do
                echo "    $_exe" >&2
              done >&2
              echo "" >&2
              echo "No host executable list was provided (ALICE_HOST_EXECUTABLES is unset)." >&2
              echo "Run alice-shell to provision — it automatically scans the host PATH." >&2
              echo "To skip this check: pass --skip-executable-check to alice run." >&2
              echo "" >&2
              exit 1
            else
              declare -A _AVAILABLE_EXECS=()
              while IFS= read -r _line || [ -n "$_line" ]; do
                [[ -n "$_line" ]] && _AVAILABLE_EXECS["$_line"]=1
              done < "$ALICE_HOST_EXECUTABLES"

              _MISSING=()
              for _exe in "''${_REQUIRED_EXECS[@]}"; do
                if [[ -z "''${_AVAILABLE_EXECS[$_exe]:-}" ]]; then
                  _MISSING+=("$_exe")
                fi
              done

              if [[ "''${#_MISSING[@]}" -gt 0 ]]; then
                echo "" >&2
                echo "Error: workspace '${name}' requires these host executables" >&2
                echo "  that were not found in the host's PATH:" >&2
                for _exe in "''${_MISSING[@]}"; do
                  echo "    $_exe" >&2
                done
                echo "" >&2
                echo "Install the missing tools on your host system and re-run." >&2
                echo "To skip this check: pass --skip-executable-check to alice run." >&2
                echo "" >&2
                exit 1
              fi
              echo "  Host executable check passed (''${#_REQUIRED_EXECS[@]} required, all present)"
            fi
            unset _REQUIRED_EXECS _MISSING _AVAILABLE_EXECS _exe _line
            # ── end assertExecutables check ───────────────────────────────────
          '';

      mcpJsonEntry = lib.optionalAttrs (cfg.bob.mcpServers != {}) {
        ".bob/mcp.json" = {
          text   = null;
          source = pkgs.writeText "mcp.json" (builtins.toJSON {
            mcpServers = lib.mapAttrs (_: srv:
              if srv.type != null then
                { type = srv.type; url = srv.url; }
                // lib.optionalAttrs (srv.alwaysAllow != []) { alwaysAllow = srv.alwaysAllow; }
              else
                { command = srv.command; }
                // lib.optionalAttrs (srv.args        != []) { args        = srv.args; }
                // lib.optionalAttrs (srv.env         != {}) { env         = srv.env; }
                // lib.optionalAttrs (srv.alwaysAllow != []) { alwaysAllow = srv.alwaysAllow; }
            ) cfg.bob.mcpServers;
          });
        };
      };

      allFiles =
        cfg.file //
        lib.mapAttrs' (k: v: lib.nameValuePair ".bob/rules/${k}"  v) cfg.bob.rules  //
        lib.mapAttrs' (k: v: lib.nameValuePair ".bob/skills/${k}" v) cfg.bob.skills //
        mcpJsonEntry;

      writeStatements = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (filePath: entry:
          let stored = toStorePath filePath entry; in
          ''
            if [ -d "${stored}" ]; then
              mkdir -p "$TARGET_DIR/${filePath}"
              cp -r "${stored}/." "$TARGET_DIR/${filePath}/"
              chmod -R u+w "$TARGET_DIR/${filePath}/" || true
              echo "  copied directory ${filePath}"
            else
              mkdir -p "$(dirname "$TARGET_DIR/${filePath}")"
              cp "${stored}" "$TARGET_DIR/${filePath}"
              chmod u+w "$TARGET_DIR/${filePath}" || true
              echo "  wrote ${filePath}"
            fi
          ''
        ) allFiles
      );

      linkStatements = lib.concatStringsSep "\n" (
        map (pkg:
          let binDir = "${lib.getBin pkg}/bin"; in
          ''
            if [ -d "${binDir}" ]; then
              mkdir -p "$TARGET_DIR/.local/bin"
              for bin in "${binDir}"/*; do
                [ -e "$bin" ] || continue
                ln -sf "$bin" "$TARGET_DIR/.local/bin/$(basename "$bin")"
                echo "  linked $(basename "$bin")"
              done
            fi
          ''
        ) cfg.packages
      );
    in
    pkgs.writeShellApplication {
      name          = "workspace-${name}";
      runtimeInputs = [ pkgs.coreutils ];

      text = ''
        set -euo pipefail

        usage() {
          cat <<'USAGE'
        Usage: workspace-${name} <directory>

        Sets up the "${name}" workspace in the given directory.

        Arguments:
          directory   Path to the target directory (must already exist)
        USAGE
        }

        if [ "$#" -ne 1 ]; then
          echo "Error: exactly one argument (directory) is required." >&2
          usage >&2
          exit 1
        fi

        TARGET_DIR="$1"

        if [ ! -d "$TARGET_DIR" ]; then
          echo "Error: directory does not exist: $TARGET_DIR" >&2
          exit 1
        fi

        ${assertExecutablesCheck}
        echo "Setting up workspace '${name}' in $TARGET_DIR ..."
        ${writeStatements}
        ${linkStatements}
        echo "Done."
      '';
    };

  # ---------------------------------------------------------------------------
  # evalConfig — evaluate a raw config attrset through the NixOS module system.
  # ---------------------------------------------------------------------------
  evalConfig = configBlock:
    let
      evaluated = lib.evalModules {
        modules = [
          workspaceOptions
          { config = configBlock; }
        ];
      };
    in
    evaluated.config.workspace;

  # ---------------------------------------------------------------------------
  # normaliseConsumerModule — accept either the full { pkgs, workspaces, utils }
  # convention or the simplified { pkgs, utils, ... } convention used by
  # consuming repositories.
  #
  # The simplified form returns an attrset that:
  #   - may have a `name` key (string; default "workspace")
  #   - has `workspace.*` keys at the top level instead of nested under
  #     `workspaces."<name>"`
  #
  # Both forms are normalised to { name, configBlock } so that the rest of
  # the engine is convention-agnostic.
  # ---------------------------------------------------------------------------
  normaliseConsumerModule = moduleFile:
    let
      # Import the file, passing both calling conventions' arguments.  The
      # simplified form uses `{ pkgs, utils, ... }` so it ignores `workspaces`.
      raw = (import moduleFile) { inherit pkgs utils; workspaces = {}; };

      # Detect which convention was used:
      # Full convention   → raw has a `workspaces` key at the top level.
      # Simplified form   → raw has `workspace` (or `name`) at the top level.
      isFullConvention = raw ? workspaces;
    in
    if isFullConvention then
      # ── Full convention ──────────────────────────────────────────────────
      # raw = { workspaces."<name>" = { workspace.file = ...; ... }; }
      # Pick the first (and typically only) workspace name.
      let
        names = builtins.attrNames raw.workspaces;
        name  = builtins.head names;
      in
      { inherit name; configBlock = raw.workspaces.${name}; }
    else
      # ── Simplified convention ─────────────────────────────────────────────
      # raw = { name = "..."; workspace.file = ...; workspace.packages = ...; }
      let
        name = raw.name or "workspace";
        # Strip the `name` key; everything else is the config block.
        configBlock = builtins.removeAttrs raw [ "name" ];
      in
      { inherit name; inherit configBlock; };

in

# ---------------------------------------------------------------------------
# Public API — returned as an attrset so flake.nix can expose individual
# functions without needing to import this file multiple times.
#
#   engine.mkWorkspace name moduleFile
#     Original entry point; expects the full { pkgs, workspaces, utils }
#     calling convention and an explicit workspace name.
#
#   engine.mkWorkspaceFromFile workspaceNixPath
#     Runtime entry point for repository-driven provisioning.
#     Accepts an absolute path *string* (not a Nix path literal) so it can
#     handle files that are only available inside the container at runtime.
#     Uses builtins.path to copy the file into the Nix store before evaluation.
#     Supports both calling conventions.
# ---------------------------------------------------------------------------
{
  mkWorkspace = name: moduleFile:
    let
      returned    = (import moduleFile) { inherit pkgs utils; workspaces = {}; };
      configBlock = returned.workspaces.${name};
      cfg         = evalConfig configBlock;
    in
    buildDerivation name cfg;

  mkWorkspaceFromFile = workspaceNixPath:
    let
      # builtins.path copies the file into the Nix store and returns a store
      # path that can be used as a Nix path literal in subsequent imports.
      moduleFile = builtins.path {
        path = workspaceNixPath;
        name = "workspace.nix";
      };
      normalised = normaliseConsumerModule moduleFile;
      cfg        = evalConfig normalised.configBlock;
    in
    buildDerivation normalised.name cfg;
}
