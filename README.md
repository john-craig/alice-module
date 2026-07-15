# alice-module

**Alice Nix Module** — a Nix flake that provides a declarative harness for
setting up Bob workspaces.  A downstream consumer adds this flake as an input
and uses `lib.mkWorkspace` (or `lib.mkWorkspaceIn`) to build
`writeShellApplication` derivations that provision a target directory with
rules, skills, MCP-server registrations, and tool symlinks.

---

## Quick start

```nix
# flake.nix (downstream consumer)
{
  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-unstable";
    alice-module.url  = "github:your-org/alice-module";
    alice-module.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, alice-module }:
    let
      system = "x86_64-linux";
      pkgs   = import nixpkgs { inherit system; };

      # mkWs resolves utils.root relative to *this* flake's root
      mkWs   = alice-module.lib.mkWorkspaceIn pkgs self;
    in {
      packages.${system}.my-workspace =
        mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
    };
}
```

Run the provisioned workspace:

```bash
nix run .#my-workspace -- /path/to/target-directory
```

The target directory must already exist.  The app creates or overwrites every
file declared in its configuration.

---

## Repository layout

```
flake.nix                        Flake definition; exposes lib and packages
modules/
  workspaces.nix                 Core mkWorkspace engine
workspaces/
  blank/default.nix              Minimal built-in example workspace
packages/
  analyze-plx-security/          Nix package wrapping analyze_plx_security.py
  plx-scrape-comments/           Nix package wrapping comment-scraper
  verify-code-snippets/          Nix package wrapping verify_code_snippets.py
```

---

## Flake outputs

### `lib.mkWorkspace pkgs`

Returns a curried function `name → moduleFile → derivation`.

`pkgs` is a nixpkgs package set.  `utils.root` inside the resulting module
will resolve paths relative to **this** flake's root.  Use
`lib.mkWorkspaceIn` instead when you want `utils.root` to resolve relative
to a different repository.

```nix
mkWs = inputs.alice-module.lib.mkWorkspace pkgs;
packages.my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
```

### `lib.mkWorkspaceIn pkgs flakeRoot`

Like `lib.mkWorkspace` but with an explicit flake root.  Downstream
consumers should pass their own `self` so that `utils.root` resolves relative
to their repository.

```nix
mkWs = inputs.alice-module.lib.mkWorkspaceIn pkgs self;
```

### `packages.<system>.workspace-blank`

A built-in demo workspace that writes a single `hello.txt` to the target
directory.

### `packages.<system>.{analyze-plx-security,plx-scrape-comments,verify-code-snippets}`

Nix derivations wrapping the Python utility scripts found under `utilities/`.
These are intended for use inside workspace modules:

```nix
{ pkgs, workspaces, utils }:
let
  analyzePlxSecurity = pkgs.callPackage inputs.alice-module + "/packages/analyze-plx-security" { inherit pkgs; };
in {
  workspaces."my-workspace" = {
    workspace.packages = [ analyzePlxSecurity ];
  };
}
```

---

## Writing a workspace module

A workspace module is a Nix function with the signature
`{ pkgs, workspaces, utils }` that returns an attrset containing a single
`workspaces."<name>"` key.

```nix
# workspaces/my-workspace/default.nix
{ pkgs, workspaces, utils }:
{
  workspaces."my-workspace" = {

    # Arbitrary files written into the target directory
    workspace.file."README.md" = ''
      # My project
    '';

    # Bob rules written under .bob/rules/
    workspace.bob.rules."my-rules.md" = {
      source = utils.root "rules/my-rules.md";
    };

    # Bob skills written under .bob/skills/
    workspace.bob.skills."MySkill" = {
      source = utils.root "skills/MySkill";
    };

    # MCP server registered in .bob/mcp.json
    workspace.bob.mcpServers.open-websearch = {
      command     = "${pkgs.nodejs}/bin/npx";
      args        = [ "-y" "open-websearch@latest" ];
      env         = { MODE = "stdio"; };
      alwaysAllow = [ "search" "fetchWebContent" ];
    };

    # Binaries symlinked into .local/bin/
    workspace.packages = [ pkgs.ripgrep pkgs.jq ];
  };
}
```

Register the workspace in your downstream flake:

```nix
packages.${system}.workspace-my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
```

---

## Module options reference

All options are set inside the `workspaces."<name>"` block.

### `workspace.file`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Files written directly into the target directory.  The attribute name is the
relative destination path (including subdirectories).  The value is either a
plain string or a `{ text = …; }` / `{ source = …; }` submodule.

### `workspace.bob.rules`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Shorthand for files under `.bob/rules/`.

### `workspace.bob.skills`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Shorthand for files under `.bob/skills/`.

### `workspace.bob.mcpServers`

| | |
|---|---|
| **Type** | `attrsOf` server submodule |
| **Default** | `{}` |

Entries merged into `.bob/mcp.json`.

#### Server fields

| Field | Type | Default | Description |
|---|---|---|---|
| `type` | `str` or `null` | `null` | Transport type (`"streamable-http"`). Set for HTTP servers; omit for stdio. |
| `url` | `str` or `null` | `null` | URL for HTTP-based servers. |
| `command` | `str` or `null` | `null` | Executable for stdio servers. |
| `args` | `listOf str` | `[]` | Arguments for the server executable. |
| `env` | `attrsOf str` | `{}` | Environment variables for the server process. |
| `alwaysAllow` | `listOf str` | `[]` | Tools auto-approved without user confirmation. |

### `workspace.packages`

| | |
|---|---|
| **Type** | `listOf package` |
| **Default** | `[]` |

Nix packages whose executables are symlinked into `.local/bin/` in the target
directory.

### `fileEntry` submodule

| Field | Type | Description |
|---|---|---|
| `text` | `lines` or `null` | Inline text content. |
| `source` | `path` or `null` | Nix path (file or directory) to copy into the target. |

A plain string is automatically coerced to `{ text = "…"; }`.

---

## `utils` helpers

### `utils.root relPath`

Resolves a path relative to the repository root (as configured by
`lib.mkWorkspaceIn`).

```nix
utils.root "rules/AGENTS.md"   # → <flakeRoot>/rules/AGENTS.md
```

### `utils.repo fetchedRepo relPath`

Resolves a path inside an externally fetched repository.

```nix
let
  external = builtins.fetchGit {
    url = "git@github.com:my-org/my-repo.git";
    rev = "abc123";
  };
in {
  workspace.bob.skills."external".source = utils.repo external "skills";
}
```
