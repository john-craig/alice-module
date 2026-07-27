# Alice Module — Test Cases

Complete test suite for repository-driven workspace provisioning.
Run tests in order. Each test includes the exact command, what it does, and expected result.

---

## Prerequisites — run once before starting

```bash
# 1. Navigate to the alice-module directory
cd $HOME/alice-module

# 2. Verify Docker Desktop is running
docker info > /dev/null 2>&1 && echo "Docker OK" || echo "Docker NOT running — start Docker Desktop first"

# 3. Load your SSH key into the agent
ssh-add ~/.ssh/id_rsa
# If your key has a different name, check: ls ~/.ssh/
# Then load whichever exists: ssh-add ~/.ssh/id_ed25519

# 4. Verify SSH key is loaded
ssh-add -l
# Should show your key. If empty, the ssh-add above failed.

# 5. Verify IBM GitHub SSH access
ssh -T git@github.com
# Should say: Hi <your-name>! You've successfully authenticated.

# 6. Create directories needed by the tests
mkdir -p generated-workspace
mkdir -p "$HOME/custom-project/.alice"
mkdir -p "$HOME/custom-output"
mkdir -p /tmp/empty-repo
mkdir -p /tmp/empty-output
```

---

## TEST 1 — Nix flake check

### What it does
Validates all Nix code without Docker. Checks that `flake.nix` and
`modules/workspaces.nix` are syntactically and semantically correct.

> **Note:** Nix is already installed on this Mac (`which nix` confirms it).
> If it ever says `command not found`, skip to TEST 2 — `docker build`
> runs the same check automatically inside the container.

### Command
```bash
nix flake check --no-warn-dirty -L
echo "Exit code: $?"
```

### Expected output
```
warning: app '...' lacks attribute 'meta'    ← harmless, ignore
warning: The check omitted these systems...  ← harmless, ignore
Exit code: 0
```

> Exit code `0` = PASS. Exit code `1` = FAIL.
> Lines starting with `warning:` are safe to ignore.
> Only lines starting with `error:` indicate a real failure.

---

## TEST 2 — Build the Docker image

### What it does
Builds the `alice-module:local` image. During the build:
- Copies the alice-module repo into the image
- Runs `nix flake check` — a broken flake fails the build
- Pre-warms nixpkgs into the Nix store so runtime builds are fast
- Installs `entrypoint.sh` as the container entrypoint

Only needs to be re-run when `Dockerfile`, `entrypoint.sh`, `flake.nix`,
or `modules/workspaces.nix` change.

### Command
```bash
docker build -t alice-module:local .
```

### Expected output
```
...
all checks passed!
...
Successfully tagged alice-module:local
```

---

## TEST 3 — Happy path: blank workspace from alice-workspaces

### What it does
The main end-to-end test. The container:
1. Reads `.alice/workspace.nix` from the mounted repo
2. Fetches the `blank` workspace from `alice-workspaces` (`test_workspace` branch) via SSH
3. Builds the workspace binary with Nix
4. Provisions the output directory with `hello.txt`

### Command
```bash
rm -rf generated-workspace && mkdir -p generated-workspace

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

### Expected output
```
Alice: reading workspace configuration from:
  /workspace/source/.alice/workspace.nix

Alice: building workspace (this may take a moment on first run)...

Alice: provisioning output directory:
  /workspace/output

Setting up workspace 'blank' in /workspace/output ...
  wrote hello.txt
Done.
```

### Verify
```bash
cat generated-workspace/hello.txt
# → Hello, world!
```

---

## TEST 4 — Error: missing `.alice/workspace.nix`

### What it does
Mounts an empty directory that has no `.alice/workspace.nix`.
Validates the error message and exit code.

> **No SSH needed** — the container exits with an error before any
> network call is made. SSH mounts are not required for this test.

### Command
```bash
docker run --rm \
  -v "/tmp/empty-repo:/workspace/source:ro" \
  -v "/tmp/empty-output:/workspace/output" \
  alice-module:local

echo "Exit code: $?"
```

### Expected output
```
ERROR: Alice workspace configuration was not found at:
  /workspace/source/.alice/workspace.nix

Create the file or run the command from a repository containing
an Alice workspace configuration.

Exit code: 1
```

---

## TEST 5 — Error: missing output directory mount

### What it does
Runs the container without an output directory mount.
Validates the error message and exit code.

> **No SSH needed** — the container exits with an error before any
> network call is made. SSH mounts are not required for this test.

> **Important:** Run this from the `alice-module` directory, not `/tmp`.
> `$PWD` must point to a repo that has `.alice/workspace.nix` — otherwise
> TEST 4's error triggers first (missing workspace file before output dir is checked).

### Command
```bash
# Make sure you are in the alice-module directory first
cd $HOME/alice-module

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  alice-module:local

echo "Exit code: $?"
```

### Expected output
```
ERROR: Output directory does not exist: /workspace/output

Mount a host directory at that path, e.g.:
  docker run --rm \
    -v "$PWD:/workspace/source:ro" \
    -v "$PWD/generated-workspace:/workspace/output" \
    alice-module:local

Exit code: 1
```

---

## TEST 6 — Custom inline workspace (no alice-workspaces)

### What it does
Creates a `.alice/workspace.nix` from scratch using the simplified
`{ pkgs, utils, ... }` format — no alice-workspaces repo involved.
Validates that custom files and Bob rules are written correctly.

> **No SSH needed** — this workspace defines everything inline.
> No `builtins.fetchGit` call is made so no IBM GitHub access required.

> **Important:** Uses `$HOME/custom-project` (not `/tmp/`) because
> Docker Desktop on macOS does not always share `/tmp` by default.

### Command
```bash
# Create the custom workspace config
cat > "$HOME/custom-project/.alice/workspace.nix" << 'EOF'
{ pkgs, utils, ... }:
{
  name = "custom-test";

  workspace.file."README-alice.txt".text = ''
    Hello from my custom workspace!
  '';

  workspace.bob.rules."my-rules.md" = ''
    # My Rules
    Always write tests.
  '';
}
EOF

# Clean output directory and run
rm -rf "$HOME/custom-output" && mkdir -p "$HOME/custom-output"

docker run --rm \
  -v "$HOME/custom-project:/workspace/source:ro" \
  -v "$HOME/custom-output:/workspace/output" \
  alice-module:local
```

### Expected output
```
Setting up workspace 'custom-test' in /workspace/output ...
  wrote README-alice.txt
  wrote .bob/rules/my-rules.md
Done.
```

### Verify
```bash
cat "$HOME/custom-output/README-alice.txt"
# → Hello from my custom workspace!

cat "$HOME/custom-output/.bob/rules/my-rules.md"
# → # My Rules
# → Always write tests.
```

---

## TEST 7 — Environment variable override

### What it does
Passes `ALICE_WORKSPACE_FILE` explicitly to the container.
Validates that the env var override works correctly.

### Command
```bash
rm -rf generated-workspace && mkdir -p generated-workspace

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  -e ALICE_WORKSPACE_FILE=/workspace/source/.alice/workspace.nix \
  alice-module:local
```

### Expected output
Same as TEST 3 — env var points to the same file.

---

## TEST 8 — vulnerability-detection-workspace workspace from alice-workspaces

### What it does
Switches `.alice/workspace.nix` to import `vulnerability-detection-workspace` from
alice-workspaces. Fetches the `pvr-analysis` skill from the external
`bob-playbook` repository and provisions MCP server config.

**Requires SSH access to:** `github.com/john-craig/bob-playbook`

### Command
```bash
# Switch to vulnerability-detection-workspace
# sed -i ''   → edit .alice/workspace.nix in-place (macOS syntax)
# s|FIND|REPLACE|  → find "blank/default.nix" and replace with "vulnerability-detection-workspace/default.nix"
# | is used as separator instead of / to avoid escaping the slashes in the path
sed -i '' 's|blank/default.nix|vulnerability-detection-workspace/default.nix|' \
  .alice/workspace.nix

rm -rf generated-workspace && mkdir -p generated-workspace

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

### Expected output
```
Setting up workspace 'vulnerability-detection-workspace' in /workspace/output ...
  wrote .bob/mcp.json
  copied directory .bob/skills/pvr-analysis
Done.
```

### Verify
```bash
ls generated-workspace/.bob/skills/
# → pvr-analysis

cat generated-workspace/.bob/mcp.json | python3 -m json.tool
# → JSON with open-websearch MCP server
```

### Restore to blank
```bash
# Swap FIND and REPLACE to put it back to blank
sed -i '' 's|vulnerability-detection-workspace/default.nix|blank/default.nix|' \
  .alice/workspace.nix
```

---

## TEST 9 — example-workspace workspace from alice-workspaces

### What it does
Switches `.alice/workspace.nix` to import the `example-workspace` workspace —
the most complex workspace. Fetches from THREE separate IBM GitHub repos:
- `john-craig/bob-playbook` — pvr-analysis skill
- `WILSONRS/d4rthb0b` — skills, rules, modes, commands, scripts
- `john-craig/vulnerability-patterns` — vulnerability analysis skill

**Requires SSH access to all three repos above.**

### Command
```bash
# Switch to example-workspace
# sed -i ''   → edit .alice/workspace.nix in-place (macOS syntax)
# s|FIND|REPLACE|  → find "blank/default.nix" and replace with "example-workspace/default.nix"
# | is used as separator instead of / to avoid escaping the slashes in the path
sed -i '' 's|blank/default.nix|example-workspace/default.nix|' \
  .alice/workspace.nix

rm -rf generated-workspace && mkdir -p generated-workspace

docker run --rm \
  -v "$PWD:/workspace/source:ro" \
  -v "$PWD/generated-workspace:/workspace/output" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  alice-module:local
```

### Expected output
```
Setting up workspace 'example-workspace' in /workspace/output ...
  copied directory .bob/skills/pvr-analysis
  copied directory .bob/skills/vulnerability-analysis
  copied directory .bob/skills/d4rthb0b
  wrote .bob/rules/d4rthb0b-common.md
  wrote .bob/rules/rules-d4rthb0b-exploiter/AGENTS.md
  wrote .bob/rules/rules-d4rthb0b-inquisitor/AGENTS.md
  wrote .bob/rules/rules-d4rthb0b-interrogator/AGENTS.md
  wrote .bob/rules/rules-d4rthb0b-recon/AGENTS.md
  wrote .bob/rules/rules-d4rthb0b-rectifier/AGENTS.md
  wrote .bob/rules/rules-d4rthb0b-scanner/AGENTS.md
  wrote .bob/custom_modes.yaml
  copied directory .bob/commands
  copied directory d4rthb0b/scripts
  copied directory d4rthb0b/schemas
  copied directory d4rthb0b/templates
  wrote .bob/mcp.json
Done.
```

### Verify
```bash
ls generated-workspace/.bob/skills/
# → d4rthb0b  pvr-analysis  vulnerability-analysis

ls generated-workspace/.bob/rules/
# → d4rthb0b-common.md  rules-d4rthb0b-exploiter  rules-d4rthb0b-inquisitor ...

cat generated-workspace/.bob/mcp.json | python3 -m json.tool
# → JSON with z-knowledgebase and IBM Z Developer Experience servers

cat generated-workspace/.bob/custom_modes.yaml
```

### Restore to blank
```bash
# Swap FIND and REPLACE to put it back to blank
sed -i '' 's|example-workspace/default.nix|blank/default.nix|' \
  .alice/workspace.nix
```

---

## Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `Host key verification failed` | SSH keys not mounted into container | Add `-v "$HOME/.ssh:/root/.ssh:ro" -v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent` |
| `The agent has no identities` | SSH key not loaded in agent | Run `ssh-add ~/.ssh/id_rsa` |
| `ERROR: Output directory does not exist` | Missing output mount | Add `-v "$PWD/generated-workspace:/workspace/output"` and `mkdir -p generated-workspace` |
| `ERROR: Alice workspace configuration was not found` | Missing `.alice/workspace.nix` | Create the file or mount the correct repo |
| `Repository not found` | No access to that IBM GitHub repo | Request access from the team |
| `Cannot connect to the Docker daemon` | Docker Desktop not running | Start Docker Desktop and retry |

---

## Restore `.alice/workspace.nix` to blank

If any test left `.alice/workspace.nix` pointing at a non-blank workspace,
run all three lines — only the matching one will make a change:

```bash
# Each sed finds the current workspace name and replaces it with "blank"
# s|FIND|REPLACE| — only the line that matches will change anything
sed -i '' 's|vulnerability-detection-workspace/default.nix|blank/default.nix|' .alice/workspace.nix
sed -i '' 's|zos-plx-workspace/default.nix|blank/default.nix|' .alice/workspace.nix
sed -i '' 's|example-workspace/default.nix|blank/default.nix|' .alice/workspace.nix

# Verify it is back to blank
grep "default.nix" .alice/workspace.nix
# → should show: workspaces/blank/default.nix
```

---

## Test summary

| # | Test | Docker | SSH | What it validates |
|---|---|---|---|---|
| 1 | Nix flake check | ❌ | ❌ | Nix code is valid |
| 2 | Docker image build | ✅ | ❌ | Image builds cleanly |
| 3 | Happy path — blank | ✅ | ✅ | Full end-to-end flow |
| 4 | Missing `workspace.nix` | ✅ | ❌ | Error message + exit 1 |
| 5 | Missing output mount | ✅ | ❌ | Error message + exit 1 |
| 6 | Custom inline workspace | ✅ | ❌ | Simplified convention |
| 7 | Env var override | ✅ | ✅ | `ALICE_WORKSPACE_FILE` |
| 8 | vulnerability-detection-workspace | ✅ | ✅ | External repo fetch |
| 9 | example-workspace | ✅ | ✅ | Multi-repo fetch |
