# modules/workspaces.nix
#
# Core workspace-building machinery.
#
# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API — two entry points
# ─────────────────────────────────────────────────────────────────────────────
#
# 1. mkWorkspaceConfig  name moduleFile { extraModules? }
#    ────────────────────────────────────────────────────
#    System-independent.  Returns a workspace configuration object:
#
#      wsCfg.configBlock            – the raw config block passed in
#      wsCfg.config                 – evaluated workspace.* options attrset
#      wsCfg.override  overrideFn   – new wsCfg with config transformed by overrideFn
#      wsCfg.provision pkgs         – writeShellApplication that provisions a directory
#
#    Intended for use in `workspaceConfigurations` flake outputs:
#
#      workspaceConfigurations."my-workspace" =
#        alice.lib.mkWorkspaceConfig "my-workspace" ./workspace.nix {};
#
#    To get a runnable derivation for a specific system:
#
#      wsCfg.provision (import nixpkgs { system = "x86_64-linux"; })
#
# 2. mkWorkspace  name moduleFile          (legacy / convenience)
#    ─────────────────────────────────────
#    System-bound.  Returns a writeShellApplication derivation (the provisioning
#    script) with .override attached.  Maintained for backwards compatibility
#    and convenience when the consumer already has a pkgs in scope.
#
#      drv              – the workspace-<name> provisioning script
#      drv.override fn  – new drv with config transformed by fn
#
# ─────────────────────────────────────────────────────────────────────────────
# WORKSPACE MODULE FORMAT
# ─────────────────────────────────────────────────────────────────────────────
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
{ pkgs, flakeRoot, nativeOverride ? null }:

let
  lib = pkgs.lib;

  # ---------------------------------------------------------------------------
  # fileEntry — submodule for a single file declaration
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
    root  = relPath:        flakeRoot + "/${relPath}";
    repo  = repo: relPath: repo + "/${relPath}";
  };

  # ---------------------------------------------------------------------------
  # mkMcpServerJson — render a single MCP server entry to its JSON-ready attrset.
  # ---------------------------------------------------------------------------
  mkMcpServerJson = srv:
    if srv.type != null then
      { type = srv.type; url = srv.url; }
      // lib.optionalAttrs (srv.headers     != {}) { headers     = srv.headers; }
      // lib.optionalAttrs (srv.alwaysAllow != []) { alwaysAllow = srv.alwaysAllow; }
    else
      { command = srv.command; }
      // lib.optionalAttrs (srv.args        != []) { args        = srv.args; }
      // lib.optionalAttrs (srv.env         != {}) { env         = srv.env; }
      // lib.optionalAttrs (srv.alwaysAllow != []) { alwaysAllow = srv.alwaysAllow; };

  # ---------------------------------------------------------------------------
  # nonNativeChecks — evaluate all non-native enforcement rules against cfg.
  # Returns null (native mode) or an attrset of check results.
  # Used with builtins.deepSeq to force evaluation before building a derivation.
  # ---------------------------------------------------------------------------
  mkNonNativeChecks = name: cfg:
    if cfg.native then null
    else
      let
        requireNative = condition: message:
          if !condition
          then throw "alice workspace '${name}': ${message}"
          else null;

        _checkPackages = requireNative
          (cfg.packages == [])
          "workspace.native = false but workspace.packages is non-empty. \
           Packages require Nix store paths and cannot be used in non-native mode. \
           Remove all entries from workspace.packages.";

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

        _checkMcpCommands = lib.mapAttrsToList (serverName: srv:
          if srv.command == null then null
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
      in
      {
        inherit _checkPackages _checkFileSources _checkRuleSources
                _checkSkillSources _checkMcpCommands;
      };

  # ---------------------------------------------------------------------------
  # buildProvisionDrv — produce the workspace-<name> provisioning shell script.
  #
  # `provisionPkgs` is used for the build environment (writeShellApplication,
  # writeText, coreutils).  It may differ from the module-level `pkgs` used
  # for option type evaluation.
  # ---------------------------------------------------------------------------
  buildProvisionDrv = name: cfg: provisionPkgs:
    let
      toStorePath = destName: entry:
        if entry.source != null then entry.source
        else provisionPkgs.writeText destName entry.text;

      mcpJsonEntry = lib.optionalAttrs (cfg.bob.mcpServers != {}) {
        ".bob/mcp.json" = {
          text   = null;
          source = provisionPkgs.writeText "mcp.json" (builtins.toJSON {
            mcpServers = lib.mapAttrs (_: mkMcpServerJson) cfg.bob.mcpServers;
          });
        };
      };

      allFiles =
        cfg.file //
        lib.mapAttrs' (k: v: lib.nameValuePair ".bob/rules/${k}"  v) cfg.bob.rules  //
        lib.mapAttrs' (k: v: lib.nameValuePair ".bob/skills/${k}" v) cfg.bob.skills //
        mcpJsonEntry;

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

      nonNativeChecks = mkNonNativeChecks name cfg;
    in
    # Force non-native checks before building the derivation.
    builtins.deepSeq nonNativeChecks
    provisionPkgs.writeShellApplication {
      name          = "workspace-${name}";
      runtimeInputs = [ provisionPkgs.coreutils ];

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
    };

  # ---------------------------------------------------------------------------
  # buildPrintDrv — produce the workspace-<name>-print config-inspection script.
  #
  # The evaluated config is serialised to a Nix expression at build time via
  # lib.generators.toPretty and baked into the store.  The shell script
  # simply installs that store path to the caller-supplied output file — no
  # runtime Nix evaluation is required.
  # ---------------------------------------------------------------------------
  buildPrintDrv = name: cfg: printPkgs:
    let
      serializeEntry = entry: {
        inherit (entry) dontIgnore;
        text   = entry.text;
        source = if entry.source != null then builtins.toString entry.source else null;
      };

      configNix = printPkgs.writeText "workspace-${name}-config.nix"
        (lib.generators.toPretty {} {
          inherit name;
          file     = lib.mapAttrs (_: serializeEntry) cfg.file;
          bob      = {
            rules      = lib.mapAttrs (_: serializeEntry) cfg.bob.rules;
            skills     = lib.mapAttrs (_: serializeEntry) cfg.bob.skills;
            mcpServers = lib.mapAttrs (_: mkMcpServerJson) cfg.bob.mcpServers;
          };
          packages = map (p: builtins.toString (lib.getBin p)) cfg.packages;
        });
    in
    printPkgs.writeShellApplication {
      name          = "workspace-${name}-print";
      runtimeInputs = [ printPkgs.coreutils ];

      text = ''
        set -euo pipefail

        usage() {
          cat <<'USAGE'
        Usage: workspace-${name}-print <output-file>

        Prints the "${name}" workspace configuration as a Nix expression to
        the given file.

        Arguments:
          output-file   Destination file path (parent directory must exist).
        USAGE
        }

        if [ "$#" -ne 1 ]; then
          echo "Error: exactly one argument (output-file) is required." >&2
          usage >&2
          exit 1
        fi

        OUTPUT_FILE="$1"

        install -D --mode=0644 "${configNix}" "$OUTPUT_FILE"
        echo "Workspace '${name}' configuration written to $OUTPUT_FILE"
      '';
    };

  # ---------------------------------------------------------------------------
  # buildWorkspaceConfig — system-independent core builder.
  #
  # Returns:
  #   wsCfg.configBlock    – the raw config block passed in
  #   wsCfg.config         – evaluated workspace.* options attrset
  #   wsCfg.override fn    – new wsCfg with configBlock transformed by fn
  #   wsCfg.provision pkgs – workspace-<name> provisioning derivation
  #   wsCfg.print     pkgs – workspace-<name>-print config-inspection derivation
  #
  # `extraModules` – additional NixOS-style modules injected into evalModules.
  #   Modules receive `pkgs` (the closure-level one) via `_module.args`.
  # ---------------------------------------------------------------------------
  buildWorkspaceConfig = name: configBlock: extraModules:
    let
      evaluated = lib.evalModules {
        modules =
          [ workspaceOptions ]
          ++ extraModules
          ++ [
            { config = configBlock; }
            # Inject pkgs so extra modules can reference e.g. pkgs.git.
            { _module.args = { inherit pkgs; }; }
          ]
          ++ lib.optional (nativeOverride != null) {
            config.workspace.native = lib.mkForce nativeOverride;
          };
      };

      cfg = evaluated.config.workspace;
    in
    {
      # The raw config block attrset (pre-evaluation).
      # Re-export this from a workspace module file to let mkWorkspace/
      # mkWorkspaceConfig import the result under a new name.
      inherit configBlock;

      # The fully-evaluated workspace options attrset.
      config = cfg;

      # Return a new wsCfg with the config block transformed by overrideFn.
      # extraModules are preserved across the override.
      override = overrideFn:
        buildWorkspaceConfig name (overrideFn configBlock) extraModules;

      # Return a provisioning writeShellApplication for the given pkgs.
      provision = provisionPkgs: buildProvisionDrv name cfg provisionPkgs;

      # Return a config-inspection writeShellApplication for the given pkgs.
      print = printPkgs: buildPrintDrv name cfg printPkgs;
    };

  # ---------------------------------------------------------------------------
  # bindWorkspaceConfig — legacy compatibility wrapper.
  #
  # Eagerly calls .provision with boundPkgs and attaches .override so the
  # return value is a derivation (not a wsCfg attrset), matching the old API.
  # ---------------------------------------------------------------------------
  bindWorkspaceConfig = name: configBlock: extraModules: boundPkgs:
    let
      wsCfg   = buildWorkspaceConfig name configBlock extraModules;
      provDrv = wsCfg.provision boundPkgs;
    in
    provDrv // {
      override = overrideFn:
        bindWorkspaceConfig name (overrideFn configBlock) extraModules boundPkgs;
      print = wsCfg.print boundPkgs;
    };

in
{
  # ---------------------------------------------------------------------------
  # mkWorkspaceConfig — system-independent public entry point.
  #
  # Returns a workspace configuration object (see buildWorkspaceConfig above).
  # Use this to populate `workspaceConfigurations` flake outputs.
  #
  # `extraModules` is an optional list of NixOS-style module paths/functions
  # that extend the option schema.  Defaults to [].
  # ---------------------------------------------------------------------------
  mkWorkspaceConfig = name: moduleFile:
    { extraModules ? [] }:
    let
      returned    = (import moduleFile) { inherit pkgs utils; workspaces = {}; };
      configBlock = returned.workspaces.${name};
    in
    buildWorkspaceConfig name configBlock extraModules;

  # ---------------------------------------------------------------------------
  # mkWorkspace — system-bound legacy entry point.
  #
  # Returns a writeShellApplication derivation (workspace-<name>) with
  # .override attached, bound to the module-level pkgs.
  # Passes no extraModules — for module injection use mkWorkspaceConfig.
  # ---------------------------------------------------------------------------
  mkWorkspace = name: moduleFile:
    let
      returned    = (import moduleFile) { inherit pkgs utils; workspaces = {}; };
      configBlock = returned.workspaces.${name};
    in
    bindWorkspaceConfig name configBlock [] pkgs;
}
