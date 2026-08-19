# Alice Module — Test Cases

---

## TEST 1 — Nix flake check

### What it does
Validates all Nix code without Docker. Checks that `flake.nix` and
`modules/workspaces.nix` are syntactically and semantically correct.

> **Note:** Nix is already installed on this Mac (`which nix` confirms it).

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

## Docker tests

Tests covering Docker image build and runtime (Tests 2–9) have moved to
[`alice-image/TESTING.md`](https://github.com/your-org/alice-image/blob/main/TESTING.md).

---

## Test summary

| # | Test | Docker | SSH | What it validates |
|---|---|---|---|---|
| 1 | Nix flake check | ❌ | ❌ | Nix code is valid |
