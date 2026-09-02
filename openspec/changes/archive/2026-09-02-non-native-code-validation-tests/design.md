## Context

`flake.nix` already contains a `checks` block under `forEachSystem` that exercises the `workspace.native = false` enforcement code in `modules/workspaces.nix`. The existing checks use two patterns:

1. `builtins.tryEval` + bare `assert` — verifies Nix evaluation succeeds or fails as expected.
2. `pkgs.runCommand` with shell assertions — verifies provisioned file content.

Several scenarios from the `workspace-native-option` spec are covered, but the coverage is uneven: some "allow" scenarios (e.g. `native-false-allows-declared-host-binary`) do not verify the actual provisioned output, and some spec scenarios have no corresponding check at all.

## Goals / Non-Goals

**Goals:**
- One named Nix check per scenario in the `workspace-native-option` spec that describes a Nix-evaluation-time or provisioning-output behavior.
- Each check name mirrors the scenario it covers (e.g. `native-false-blocks-packages` → scenario "packages declared with native = false").
- Checks follow the existing patterns in the file: `builtins.tryEval`-based for "must throw" scenarios, `pkgs.runCommand` with shell assertions for "must produce output" scenarios.
- All checks are added inside the existing `checks = forEachSystem (system: let … in { … })` block — no structural changes to `flake.nix`.

**Non-Goals:**
- CLI / runtime checks (`alice switch` manifest verification, `--no-native` flag behaviour) — those require an impure Nix sandbox and are handled by the existing `alice-*` checks.
- Changes to `modules/workspaces.nix` or any production code.
- New inline workspace file fixtures beyond what is needed for uncovered scenarios.

## Decisions

### Decision: extend the existing `checks` block rather than a separate file

The current checks live inline in `flake.nix`. Extracting them to a `checks/` directory would be a larger refactor outside the scope of this change. Adding to the existing block keeps the diff minimal and consistent with existing style.

*Alternatives considered:* A `checks/non-native.nix` import — rejected because it would move existing checks and expand the diff beyond intent.

### Decision: name checks after spec scenarios, not after implementation symbols

Check names such as `native-false-blocks-packages` map directly to spec scenario titles. This makes traceability immediate without requiring comments.

*Alternatives considered:* Naming after function/module names (e.g. `mkNonNativeChecks-packages`) — rejected because the spec is the source of truth, not the implementation.

### Decision: "allow" scenarios that currently only test `result.success` will be upgraded to also provision and verify output

`native-false-allows-declared-host-binary` currently just asserts `result.success` without running the provisioning script or checking `.bob/mcp.json`. For parity with "allow" checks like `native-false-allows-http-mcp`, it will be upgraded to a `pkgs.runCommand` that provisions and asserts the MCP server entry appears in `.bob/mcp.json`.

*Alternatives considered:* Leave as-is for now — rejected because it gives a false sense of completeness; `result.success` confirms evaluation passes but not that the output is correct.

## Risks / Trade-offs

- **Longer `nix flake check` time** → Each new `pkgs.runCommand` adds a small evaluation + build. Impact is negligible; all checks are pure and cacheable.
- **Inline workspace fixtures grow `flake.nix`** → The file is already long. Risk is manageable for this scope; a future refactor can extract fixtures.

## Migration Plan

No deployment steps required. The change is purely additive to `flake.nix`. Run `nix flake check` to validate all checks pass after implementation.
