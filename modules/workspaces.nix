# modules/workspaces.nix
#
# Core workspace-building machinery.
#
# This module is imported by flake.nix and re-exported as
# `self.lib.mkWorkspace` so that downstream flake consumers can call it
# directly.
#
# The public API is a single function:
#
#   mkWorkspace pkgs name moduleFile
#
# `pkgs`       – a nixpkgs package set (import nixpkgs { inherit system; })
# `name`       – the workspace name string, e.g. "my-workspace"
# `moduleFile` – a Nix path to the workspace module, e.g. ./workspaces/my-workspace/default.nix
#
# A workspace module is a function of the form:
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
# `utils.root relPath`       resolves a path relative to the flake root.
# `utils.repo repo relPath`  resolves a path inside an externally fetched repo.
#
# The produced derivation is a `writeShellApplication` named `workspace-<name>`.
# Run it with a target directory to provision that directory:
#
#   workspace-my-workspace /path/to/target-dir
#
{ pkgs, flakeRoot, nativeOverride ? null }:

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
      dontIgnore = lib.mkOption {
        type        = lib.types.bool;
        default     = false;
        description = ''
          When true, this file is not added to the workspace `.gitignore`.
          By default every file written by the module is appended to `.gitignore`.
        '';
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
            headers = lib.mkOption {
              type        = lib.types.attrsOf lib.types.str;
              default     = {};
              description = ''
                HTTP headers sent with every request to an
                HTTP-based MCP server (e.g. Authorization).
                Only applicable when `type` is set.
              '';
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

      native = lib.mkOption {
        type        = lib.types.bool;
        default     = true;
        description = ''
          When `true` (the default), the workspace assumes that the Nix store
          and host-native tooling are available on the target host.  Set to
          `false` to declare that the Nix store must not be assumed present
          (e.g. containers or restricted environments).  In non-native mode
          the engine rejects any option that requires a permanent Nix store
          path: `workspace.packages`, `source`-based file entries, and MCP
          server commands that start with `/nix/store/`.
        '';
      };

      assertHostBinaries = lib.mkOption {
        type        = lib.types.listOf lib.types.str;
        default     = [];
        description = ''
          Short executable names (e.g. `"node"`, `"npx"`) that the workspace
          depends on being present on the target host.  At provision time
          (`alice switch`) each name is checked against a host binaries
          manifest file (default: `.alice/host-binaries` in the target
          directory).  Any name absent from the manifest causes provisioning
          to abort with a hard error before any file is written.

          This option is meaningful only when `workspace.native = false`.
          When `native = true`, a non-empty list produces a warning but is
          otherwise ignored.
        '';
        example = [ "node" "npx" ];
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
    root  = relPath:          flakeRoot + "/${relPath}";
    repo  = repo: relPath:   repo + "/${relPath}";
  };

in

# ---------------------------------------------------------------------------
# mkWorkspace — public entry point
#
# Returns a `writeShellApplication` derivation named `workspace-<name>` that,
# when run with a target directory, provisions that directory according to the
# options declared in `moduleFile`.
# ---------------------------------------------------------------------------
name: moduleFile:
  let
    returned    = (import moduleFile) { inherit pkgs utils; workspaces = {}; };
    configBlock = returned.workspaces.${name};

    evaluated = lib.evalModules {
      modules = [
        workspaceOptions
        { config = configBlock; }
      ] ++ lib.optional (nativeOverride != null) {
        # CLI --native / --no-native override: takes priority over the module declaration.
        config.workspace.native = lib.mkForce nativeOverride;
      };
    };

    cfg = evaluated.config.workspace;

    # ---------------------------------------------------------------------------
    # Non-native enforcement — evaluated at Nix eval time so errors are caught
    # before any derivation is built or any file is written.
    # ---------------------------------------------------------------------------

    # Check a condition; throw a clear error if it fails.
    # Returns null so it can be sequenced with `lib.seq` or used in an assert.
    requireNative = condition: message:
      if !condition
      then throw "alice workspace '${name}': ${message}"
      else null;

    nonNativeChecks =
      if cfg.native then null
      else
        let
          # 2.1  packages must be empty
          _checkPackages = requireNative
            (cfg.packages == [])
            "workspace.native = false but workspace.packages is non-empty. \
             Packages require Nix store paths and cannot be used in non-native mode. \
             Remove all entries from workspace.packages.";

          # 2.2  file / rules / skills: no source entries
          checkSourceEntry = optionPath: entries:
            lib.mapAttrsToList (key: entry:
              requireNative
                (entry.source == null)
                "${optionPath}.\"${key}\" uses source = …, which requires a Nix store path. \
                 Use text = … instead, or remove the entry, when workspace.native = false."
            ) entries;

          _checkFileSources  = checkSourceEntry "workspace.file"       cfg.file;
          _checkRuleSources  = checkSourceEntry "workspace.bob.rules"  cfg.bob.rules;
          _checkSkillSources = checkSourceEntry "workspace.bob.skills" cfg.bob.skills;

          # 2.3  MCP servers: command must not be a Nix store path
          # 2.4  MCP servers: non-store command must be declared in assertHostBinaries
          _checkMcpCommands = lib.mapAttrsToList (serverName: srv:
            if srv.command == null then null          # HTTP server — no command
            else if lib.hasPrefix "/nix/store/" srv.command then
              requireNative false
                "workspace.bob.mcpServers.\"${serverName}\" has command = \"${srv.command}\", \
                 which is a Nix store path. Nix store paths are not permitted when \
                 workspace.native = false. Use a host binary name instead, or remove this server."
            else
              let binName = builtins.baseNameOf srv.command; in
              requireNative
                (builtins.elem binName cfg.assertHostBinaries)
                "workspace.bob.mcpServers.\"${serverName}\" uses command = \"${srv.command}\" \
                 (resolved name: \"${binName}\"), but \"${binName}\" is not listed in \
                 workspace.assertHostBinaries. Add \"${binName}\" to assertHostBinaries so \
                 alice can verify it is present on the target host at provision time."
          ) cfg.bob.mcpServers;

          # Force evaluation of all checks; the value itself is unused.
          _allChecks = {
            inherit _checkPackages _checkFileSources _checkRuleSources
                    _checkSkillSources _checkMcpCommands;
          };
        in
          _allChecks;

    toStorePath = destName: entry:
      if entry.source != null then entry.source
      else pkgs.writeText destName entry.text;

    mcpJsonEntry = lib.optionalAttrs (cfg.bob.mcpServers != {}) {
      ".bob/mcp.json" = {
        text   = null;
        source = pkgs.writeText "mcp.json" (builtins.toJSON {
          mcpServers = lib.mapAttrs (_: srv:
            if srv.type != null then
              { type = srv.type; url = srv.url; }
              // lib.optionalAttrs (srv.headers     != {}) { headers     = srv.headers; }
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

    # Paths to add to .gitignore — everything that does not set dontIgnore = true.
    gitignorePaths = lib.filter (p: !(allFiles.${p}.dontIgnore or false))
                       (lib.attrNames allFiles);

    gitignoreStatement =
      if gitignorePaths == [] then ""
      else
        let
          addLines = lib.concatStringsSep "\n" (
            map (p: ''grep -qxF ${lib.escapeShellArg p} "$GITIGNORE" || echo ${lib.escapeShellArg p} >> "$GITIGNORE"'')
              gitignorePaths
          );
        in
        ''
          GITIGNORE="$TARGET_DIR/.gitignore"
          touch "$GITIGNORE"
          ${addLines}
          echo "  updated .gitignore"
        '';

    writeStatements = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (filePath: entry:
        let stored = toStorePath filePath entry; in
        ''
          if [ -d "${stored}" ]; then
            mkdir -p "$TARGET_DIR/${filePath}"
            cp -r --no-preserve=mode "${stored}/." "$TARGET_DIR/${filePath}/"
            echo "  copied directory ${filePath}"
          else
            install -D --mode=0644 "${stored}" "$TARGET_DIR/${filePath}"
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
  # Force evaluation of all non-native checks before building the derivation.
  # deepSeq walks the entire structure so every throw inside nonNativeChecks
  # fires at Nix eval time, before any derivation is constructed.
  builtins.deepSeq nonNativeChecks
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

      echo "Setting up workspace '${name}' in $TARGET_DIR ..."
      ${writeStatements}
      ${linkStatements}
      ${gitignoreStatement}
      echo "Done."
    '';
  }
