# dev-envs

A Nix flake that provides a declarative harness for setting up Bob
development environments.  A downstream consumer adds this flake as an input
and uses `lib.mkEnvironment` (or `lib.mkEnvironmentIn`) to build
`writeShellApplication` derivations that provision a target directory with
rules, skills, MCP-server registrations, and tool symlinks.

---

## Quick start

```nix
# flake.nix (downstream consumer)
{
  inputs = {
    nixpkgs.url    = "github:NixOS/nixpkgs/nixos-unstable";
    dev-envs.url   = "github:your-org/dev-envs";
    dev-envs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, dev-envs }:
    let
      system = "x86_64-linux";
      pkgs   = import nixpkgs { inherit system; };

      # mkEnv resolves utils.root relative to *this* flake's root
      mkEnv  = dev-envs.lib.mkEnvironmentIn pkgs self;
    in {
      packages.${system}.my-env =
        mkEnv "my-env" ./environments/my-env/default.nix;
    };
}
```

Run the provisioned environment:

```bash
nix run .#my-env -- /path/to/target-directory
```

The target directory must already exist.  The app creates or overwrites every
file declared in its configuration.

---

## Repository layout

```
flake.nix                        Flake definition; exposes lib and packages
modules/
  environments.nix               Core mkEnvironment engine
environments/
  blank/default.nix              Minimal built-in example environment
packages/
  analyze-plx-security/          Nix package wrapping analyze_plx_security.py
  plx-scrape-comments/           Nix package wrapping comment-scraper
  verify-code-snippets/          Nix package wrapping verify_code_snippets.py
```

---

## Flake outputs

### `lib.mkEnvironment pkgs`

Returns a curried function `name → moduleFile → derivation`.

`pkgs` is a nixpkgs package set.  `utils.root` inside the resulting module
will resolve paths relative to **this** flake's root.  Use
`lib.mkEnvironmentIn` instead when you want `utils.root` to resolve relative
to a different repository.

```nix
mkEnv = inputs.dev-envs.lib.mkEnvironment pkgs;
packages.my-env = mkEnv "my-env" ./environments/my-env/default.nix;
```

### `lib.mkEnvironmentIn pkgs flakeRoot`

Like `lib.mkEnvironment` but with an explicit flake root.  Downstream
consumers should pass their own `self` so that `utils.root` resolves relative
to their repository.

```nix
mkEnv = inputs.dev-envs.lib.mkEnvironmentIn pkgs self;
```

### `packages.<system>.env-blank`

A built-in demo environment that writes a single `hello.txt` to the target
directory.

### `packages.<system>.{analyze-plx-security,plx-scrape-comments,verify-code-snippets}`

Nix derivations wrapping the Python utility scripts found under `utilities/`.
These are intended for use inside environment modules:

```nix
{ pkgs, envs, utils }:
let
  analyzePlxSecurity = pkgs.callPackage inputs.dev-envs + "/packages/analyze-plx-security" { inherit pkgs; };
in {
  envs."my-env" = {
    environment.packages = [ analyzePlxSecurity ];
  };
}
```

---

## Writing an environment module

An environment module is a Nix function with the signature
`{ pkgs, envs, utils }` that returns an attrset containing a single
`envs."<name>"` key.

```nix
# environments/my-env/default.nix
{ pkgs, envs, utils }:
{
  envs."my-env" = {

    # Arbitrary files written into the target directory
    environment.file."README.md" = ''
      # My project
    '';

    # Bob rules written under .bob/rules/
    environment.bob.rules."my-rules.md" = {
      source = utils.root "rules/my-rules.md";
    };

    # Bob skills written under .bob/skills/
    environment.bob.skills."MySkill" = {
      source = utils.root "skills/MySkill";
    };

    # MCP server registered in .bob/mcp.json
    environment.bob.mcpServers.open-websearch = {
      command     = "${pkgs.nodejs}/bin/npx";
      args        = [ "-y" "open-websearch@latest" ];
      env         = { MODE = "stdio"; };
      alwaysAllow = [ "search" "fetchWebContent" ];
    };

    # Binaries symlinked into .local/bin/
    environment.packages = [ pkgs.ripgrep pkgs.jq ];
  };
}
```

Register the environment in your downstream flake:

```nix
packages.${system}.env-my-env = mkEnv "my-env" ./environments/my-env/default.nix;
```

---

## Module options reference

All options are set inside the `envs."<name>"` block.

### `environment.file`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Files written directly into the target directory.  The attribute name is the
relative destination path (including subdirectories).  The value is either a
plain string or a `{ text = …; }` / `{ source = …; }` submodule.

### `environment.bob.rules`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Shorthand for files under `.bob/rules/`.

### `environment.bob.skills`

| | |
|---|---|
| **Type** | `attrsOf fileEntry` |
| **Default** | `{}` |

Shorthand for files under `.bob/skills/`.

### `environment.bob.mcpServers`

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

### `environment.packages`

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
`lib.mkEnvironmentIn`).

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
  environment.bob.skills."external".source = utils.repo external "skills";
}
```
