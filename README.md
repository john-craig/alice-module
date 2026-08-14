# alice-module

![Alice](../demos/alice_head.png)

**alice-module** is the foundational layer of the Alice framework — a Nix flake
that provides the declarative workspace-provisioning engine used by all other
Alice repositories. It exposes `lib.mkWorkspace` / `lib.mkWorkspaceIn`, which
downstream consumers (`alice-workspaces`, `alice-image`) use to build
`writeShellApplication` derivations that provision a target directory with rules,
skills, MCP-server registrations, and tool symlinks.

---

## Architecture

The Alice framework is split across three repositories with clearly separated
responsibilities:

| Repository | Purpose |
|---|---|
| **[alice-module](https://github.com/john-craig/alice-module)** (this repo) | Reusable declarative workspace-provisioning framework |
| **[alice-workspaces](https://github.com/john-craig/alice-workspaces)** | Concrete workspace definitions built using alice-module |
| **[alice-image](https://github.com/john-craig/alice-image)** | Dockerfile, entrypoint, build logic and runtime environment |

Dependency flow:

```
alice-module
     │
     ├──────────────► alice-image
     │
     ▼
alice-workspaces ───► alice-image
```

---

## Repository layout

```
flake.nix                        Flake definition; exposes lib and packages
modules/
  workspaces.nix                 Core mkWorkspace / mkWorkspaceFromFile engine
workspaces/
  blank/default.nix              Minimal built-in example workspace
.alice/
  workspace.nix                  Example consumer workspace configuration
docs/
  TESTING.md                     Test cases and validation commands
```

---

## Quick start — consuming from a downstream flake

```nix
# flake.nix (downstream consumer)
{
  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-unstable";
    alice-module.url  = "git+ssh://git@github.com/john-craig/alice-module.git";
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

## Docker image

Docker image build and runtime are managed in the separate
[`alice-image`](https://github.com/john-craig/alice-image) repository.
See [`alice-image/README.md`](https://github.com/john-craig/alice-image/blob/main/README.md)
for build instructions, run commands, environment variable reference,
and troubleshooting.

---

## Writing a workspace module

A workspace module is a Nix function accepted in two equivalent forms.

### Simplified form (recommended for `.alice/workspace.nix`)

```nix
# .alice/workspace.nix
{ pkgs, utils, ... }:
{
  name = "my-project";          # optional; defaults to "workspace"

  # Arbitrary files written into the output directory
  workspace.file."README.md".text = ''
    # My project
  '';

  # Bob rules written under .bob/rules/
  workspace.bob.rules."my-rules.md" = "# My rules\n";

  # Bob skills written under .bob/skills/
  workspace.bob.skills."MySkill.md" = {
    source = utils.root "skills/MySkill.md";
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
}
```

### Full form (for advanced use / alice-workspaces modules)

```nix
# workspaces/my-workspace/default.nix
{ pkgs, workspaces, utils }:
{
  workspaces."my-workspace" = {
    workspace.file."README.md".text = "# My project\n";
    workspace.packages = [ pkgs.ripgrep ];
  };
}
```

Register in your downstream flake:

```nix
packages.${system}.workspace-my-workspace = mkWs "my-workspace" ./workspaces/my-workspace/default.nix;
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

### `lib.mkWorkspaceFromFile pkgs`

Returns a function `workspaceNixPath → derivation`.  Designed for runtime use
inside the Docker container — accepts an absolute path string to
`.alice/workspace.nix` and builds from it without needing a Nix path literal.
Supports both the simplified and full calling conventions.

```nix
mkWs = inputs.alice-module.lib.mkWorkspaceFromFile pkgs;
packages.${system}.workspace = mkWs "/workspace/source/.alice/workspace.nix";
```

### `packages.<system>.workspace-blank`

A built-in demo workspace that writes a single `hello.txt` to the target
directory.

---

## Module options reference

All options are set inside the `workspace` block (simplified form) or inside
`workspaces."<name>"` (full form).

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
