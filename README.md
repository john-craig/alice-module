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
examples/
  sample-workspace/default.nix   Full example workspace (all fields demonstrated)
  workspace.nix                  Extended workspace (shows override/extend pattern)
packages/
  hello/                         Sample package (hello-world shell script)
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

### `packages.<system>.workspace-sample-workspace`

A built-in example workspace that demonstrates every supported option —
`workspace.file`, `workspace.bob.rules`, `workspace.bob.skills`,
`workspace.bob.mcpServers`, and `workspace.packages`.

### `packages.<system>.workspace-extended-workspace`

A built-in example that shows how to override and extend
`workspace-sample-workspace` without forking it (see
[Overriding and extending a workspace](#overriding-and-extending-a-workspace)).

### `packages.<system>.hello`

A sample shell-script package included as a starting point for adding real
packages to the flake.

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

## Overriding and extending a workspace

You can build on an existing workspace definition — from this flake or any
other — without forking it.  The pattern uses plain Nix attribute operators:

- `//` merges two attrsets, with the right-hand side winning on conflicts.
  Use it to override individual files, rules, skills, or MCP server entries
  while preserving every key you don't mention.
- `++` appends lists.  Use it for `workspace.packages` to add packages on top
  of the upstream set rather than replacing it.

```nix
# workspaces/my-workspace/default.nix
{ pkgs, workspaces, utils }:

let
  # Import the upstream workspace module and extract its config block.
  upstream = import (inputs.alice-module + "/examples/sample-workspace/default.nix")
               { inherit pkgs workspaces utils; };

  base = upstream.workspaces."sample-workspace";
in
{
  workspaces."my-workspace" = base // {

    # Override individual files; all other upstream files are preserved.
    workspace.file = base.workspace.file // {
      "README.md" = {
        dontIgnore = true;
        text = "# my-workspace\n";
      };
      "my-extra-file.md" = "Extra content.\n";
    };

    # Add extra rules on top of the upstream set.
    workspace.bob.rules = base.workspace.bob.rules // {
      "my-rules.md" = { source = utils.root "rules/my-rules.md"; };
    };

    # Add packages without dropping the upstream ones.
    workspace.packages = base.workspace.packages ++ [ pkgs.fd ];
  };
}
```

A working implementation of this pattern is in
[`examples/workspace.nix`](examples/workspace.nix).

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
| `headers` | `attrsOf str` | `{}` | HTTP headers sent with every request (e.g. `Authorization`). HTTP servers only. |
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

| Field | Type | Default | Description |
|---|---|---|---|
| `text` | `lines` or `null` | `null` | Inline text content. |
| `source` | `path` or `null` | `null` | Nix path (file or directory) to copy into the target. |
| `dontIgnore` | `bool` | `false` | When `true`, this file is **not** appended to the workspace `.gitignore`. By default every file written by the module is added to `.gitignore`. |

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

---

## Docker usage

The repository ships a `Dockerfile` that lets you provision a workspace
**without installing Nix on your host machine**.  The image is built once;
at runtime it runs the pre-built `workspace-blank` binary directly from the
Nix store closure baked into the image — no Nix evaluation or network access
is needed when the container starts.

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker
  Engine on Linux) installed and the daemon running.
- No Nix installation required on the host.

### Build the image

```bash
docker build -t alice-module:local .
```

`nix flake check` is executed during the build.  If the flake check fails,
the Docker build fails — a broken flake can never produce a successful image.

> **Apple Silicon (M1/M2/M3) vs Intel/AMD**
> The `nixos/nix` base image is published for both `linux/amd64` and
> `linux/arm64`.  Docker Desktop on Apple Silicon automatically selects
> `linux/arm64`; on Linux x86-64 hosts it selects `linux/amd64`.  No flags
> or overrides are required.

### Run the container

```bash
mkdir -p generated-workspace

docker run --rm \
  -v "$PWD/generated-workspace:/workspace" \
  alice-module:local
```

**What happens:**

| Step | Detail |
|---|---|
| `--rm` | Container is removed automatically when it exits |
| `-v "$PWD/generated-workspace:/workspace"` | Bind-mounts your host directory into the container at `/workspace` |
| The entrypoint | Calls the pre-built `workspace-blank` binary with `/workspace` as the target |
| After exit | Files written inside `/workspace` remain on your host |

**Expected output:**

```
Setting up workspace 'blank' in /workspace ...
  wrote hello.txt
Done.
```

### Verify the output

```bash
cat generated-workspace/hello.txt
# → Hello, world!
```

### Pass a custom target path

If you mount to a different container path, pass it as an argument:

```bash
docker run --rm \
  -v "$PWD/generated-workspace:/output" \
  alice-module:local /output
```

### Troubleshooting

#### Target directory does not exist

```
Error: target directory does not exist: /workspace
```

The host directory must exist **before** running the container.
Create it first:

```bash
mkdir -p generated-workspace
docker run --rm -v "$PWD/generated-workspace:/workspace" alice-module:local
```

#### Docker daemon not running

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

Start Docker Desktop (macOS/Windows) or run `sudo systemctl start docker`
(Linux), then retry.

#### Permission or ownership issues

Files written by the container are owned by `root` (UID 0) because the
`nixos/nix` image runs as root.  To fix ownership after provisioning:

```bash
sudo chown -R "$USER" generated-workspace
```

Alternatively, add `--user "$(id -u):$(id -g)"` to the `docker run` command
if your workspace does not require symlinks (symlinks to the Nix store will
not work with a non-root user inside the container).

#### Nix dependency download failures during build

The `docker build` step downloads Nix store paths from `cache.nixos.org`.
If your build environment has restricted internet access:

1. Check that `cache.nixos.org` is reachable from the build host.
2. If using a corporate proxy, set `--build-arg https_proxy=...` or configure
   Docker's proxy settings.
3. Re-run `docker build` — Nix downloads are content-addressed and resumable.
