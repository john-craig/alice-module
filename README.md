# alice-module

**Alice Nix Module** — a Nix flake that provides a declarative harness for
setting up Bob workspaces.  A downstream consumer adds this flake as an input
and uses `lib.mkWorkspace` (or `lib.mkWorkspaceIn`) to build
`writeShellApplication` derivations that provision a target directory with
rules, skills, MCP-server registrations, and tool symlinks.

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
packages/
  hello/                         Sample package (hello-world shell script)
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

## Docker usage — repository-driven provisioning

The repository ships a `Dockerfile` that provisions a workspace at **runtime**
from the consuming repository's `.alice/workspace.nix` — no workspace
definition is baked into the image.

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker
  Engine on Linux) installed and the daemon running.
- No Nix installation required on the host.
- A `.alice/workspace.nix` file in the consuming repository root.

### 1. Create `.alice/workspace.nix` in your repository

```nix
# <your-repo>/.alice/workspace.nix
{ pkgs, utils, ... }:

{
  name = "my-project";

  workspace.file."README-alice.txt".text = ''
    This workspace was generated from the consuming repository.
  '';

  workspace.packages = [ pkgs.git pkgs.curl ];
}
```

### 2. Build the Docker image (once)

```bash
docker build -t alice-module:local .
```

`nix flake check` is executed during the build and all flake inputs (nixpkgs)
are pre-warmed into the image's Nix store — runtime builds are fast and do not
require network access for base packages.

### 3. Run the container

```bash
mkdir -p generated-workspace

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

**What happens:**

| Step | Detail |
|---|---|
| `--rm` | Container is removed automatically when it exits |
| `-v "$PWD:/workspace/source:ro"` | Bind-mounts your repository root (read-only) so `.alice/workspace.nix` is visible inside the container |
| `-v "$PWD/generated-workspace:/workspace/output"` | Bind-mounts the output directory (read-write) |
| `-v "$HOME/.ssh:/root/.ssh:ro"` | Mounts SSH keys so the container can authenticate with IBM GitHub |
| `-v "$SSH_AUTH_SOCK:/ssh-agent"` | Forwards the SSH agent socket into the container |
| The entrypoint | Reads `/workspace/source/.alice/workspace.nix`, runs `nix build` on it, then executes the result against `/workspace/output` |
| After exit | Files written inside `/workspace/output` remain on your host |

**Expected output:**

```
Alice: reading workspace configuration from:
  /workspace/source/.alice/workspace.nix

Alice: building workspace (this may take a moment on first run)...

Alice: provisioning output directory:
  /workspace/output

Setting up workspace 'my-project' in /workspace/output ...
  wrote README-alice.txt
Done.
```

### Environment variable overrides

| Variable | Default | Description |
|---|---|---|
| `ALICE_SOURCE_DIR` | `/workspace/source` | Path to the consuming repository root inside the container |
| `ALICE_OUTPUT_DIR` | `/workspace/output` | Path to the directory to provision inside the container |
| `ALICE_WORKSPACE_FILE` | `$ALICE_SOURCE_DIR/.alice/workspace.nix` | Explicit path to the workspace configuration file |

### Troubleshooting

#### SSH authentication failure

```
Host key verification failed.
fatal: Could not read from remote repository.
```

The container has no SSH keys to authenticate with IBM GitHub. Add the SSH mounts:

```bash
docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

Also make sure your SSH key is loaded in the agent:

```bash
ssh-add -l          # check loaded keys
ssh-add ~/.ssh/id_rsa   # load if empty
ssh -T git@github.com  # verify access
```

#### `.alice/workspace.nix` not found

```
ERROR: Alice workspace configuration was not found at:
  /workspace/source/.alice/workspace.nix
```

Make sure your repository contains `.alice/workspace.nix` and that you mounted
the repository root (not a subdirectory):

```bash
docker run --rm \
  -v "$PWD:/workspace/source:ro" \     # ← must be the repo root
  -v "$PWD/generated-workspace:/workspace/output" \
  alice-module:local
```

#### Output directory does not exist

```
ERROR: Output directory does not exist: /workspace/output
```

Create the host directory before running the container:

```bash
mkdir -p generated-workspace
docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

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

### `packages.<system>.hello`

A sample shell-script package included as a starting point for adding real
packages to the flake.

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
