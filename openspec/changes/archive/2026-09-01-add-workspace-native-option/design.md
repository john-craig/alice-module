## Context

The alice-module provides a Nix-based workspace provisioning system. Workspace modules declare files, Bob rules/skills, MCP servers, and packages using a NixOS-style module system in `modules/workspaces.nix`. The `alice` CLI (`packages/alice/default.nix`) is the imperative front-end that evaluates a user's `workspace.nix` at runtime and drives provisioning.

Non-native environments (containers, ephemeral CI runners, restricted hosts) may not have the Nix store mounted. The options that require permanent Nix store paths are:

- `workspace.packages` — binaries symlinked from store derivation `bin/` directories
- `workspace.file.*.source`, `workspace.bob.rules.*.source`, `workspace.bob.skills.*.source` — file content copied from a store path
- `workspace.bob.mcpServers.<n>.command` — an executable whose path starts with `/nix/store/`

HTTP-based MCP servers (`type = "streamable-http"` or `"http"`) carry no local path dependency and are unconditionally permitted in non-native mode.

Stdio MCP servers are a middle case: a server invoked via a host binary (e.g. `"npx"`, `"node"`) rather than a Nix store path is permissible in non-native mode, but only if the workspace explicitly declares that binary as a dependency and the host is confirmed to provide it at provision time.

## Goals / Non-Goals

**Goals:**
- Add a `workspace.native` boolean option (default `true`) to `modules/workspaces.nix`.
- When `native = false`, enforce at Nix evaluation time (via `config.assertions`) that `workspace.packages` is empty and that all file/rules/skills entries use `text` only.
- When `native = false`, enforce at Nix evaluation time that no stdio MCP server `command` starts with `/nix/store/`.
- Add a `workspace.assertHostBinaries` option (`listOf str`, default `[]`) for declaring host binary names the workspace depends on.
- At `alice switch` time, when `native = false` and `assertHostBinaries` is non-empty, read a host binaries manifest file and hard-error if any declared binary is absent.
- Permit a stdio MCP server in non-native mode when its `command` is a plain name that appears in `assertHostBinaries` and passes the manifest check.
- When `native = true` and `assertHostBinaries` is non-empty, emit a warning to stderr and continue without reading any manifest.
- Add `--no-native` / `--native` flags to `alice switch`.
- Add `--host-binaries <file>` flag to `alice switch` (default: `.alice/host-binaries` in the target directory).
- Thread the `native` override through `alice-build-workspace.nix` via `--argstr wsNative`.
- Update the `alice init` template to document both new options.

**Non-Goals:**
- Checking that asserted host binaries are functional, only named presence in the manifest is verified.
- Adding `workspace.native` or `workspace.assertHostBinaries` to the extended-workspace example.
- Restricting the *content* of text-only files (only the mechanism by which they are delivered is checked).
- Making `assertHostBinaries` entries resolve full paths; only executable names are matched.

## Decisions

### Decision: boolean option, not an enum

**Chosen:** `lib.types.bool` with `default = true`.

**Alternatives considered:** An enum such as `"native" | "container"` to allow more modes. Rejected — there are only two meaningful values right now, and a bool is simpler to parse, document, and override. If more modes are needed later, a migration to an enum is straightforward.

### Decision: enforcement split — Nix assertions for paths, runtime check for host binaries

**Chosen:** Store-path violations (packages, `source` entries, store-path MCP commands) are caught by `config.assertions` in `modules/workspaces.nix` at Nix evaluation time. Host-binary presence is checked by a shell function in `alice switch` at provisioning time.

**Rationale:** Nix-store violations are statically detectable from the module values alone and should be caught as early as possible — before any files are written. Host binary presence, by contrast, is a runtime property of the target machine; it cannot be known at Nix eval time and must be deferred to the provisioning step.

**Alternatives considered:** Checking everything at runtime in the shell script. Rejected — store-path violations would only be caught after `nix build` succeeds and the script starts running, by which point the derivation has already been built. Nix assertions produce cleaner, earlier errors.

### Decision: how to distinguish a store-path command from a host binary command

**Chosen:** `lib.hasPrefix "/nix/store/"` on the `command` string. Commands beginning with that prefix are treated as Nix store paths and are unconditionally blocked in non-native mode. Any other non-null command string (e.g. `"npx"`, `"node"`, `"/usr/bin/node"`) is treated as a potential host binary.

**Alternatives considered:** Requiring the user to annotate each MCP server with `nativeBinary = true/false`. Rejected — a path prefix check requires no extra syntax and covers the dominant case (Nix-derived commands always start with `/nix/store/`).

**Known limitation:** A command at a non-store absolute path (e.g. `/home/user/bin/my-server`) will not be caught by the prefix check. It will pass the Nix assertion but must still appear in `assertHostBinaries` to be permitted at provision time — so it is not silently skipped, just flagged later.

### Decision: `assertHostBinaries` contains executable names, not full paths

**Chosen:** Short names only (e.g. `"node"`, `"npx"`). The host binaries manifest is also a list of short names.

**Rationale:** The workspace declaration should be portable across different host configurations where the same binary may live at different absolute paths. Name-based matching lets the manifest be produced by `ls /usr/local/bin` or `command -v` output without path sensitivity.

### Decision: host binaries manifest format and location

**Chosen:** A plain newline-delimited text file of executable names, one per line. Default location: `.alice/host-binaries` inside the target directory. Overrideable via `--host-binaries <file>` on `alice switch`.

**Rationale:** Plain text is trivially produced by shell commands (`ls $PATH_DIR | sort > .alice/host-binaries`), easy to audit, and requires no parsing library. The target-directory default keeps manifest and workspace co-located. The CLI override allows CI pipelines or container build steps to supply a centrally managed manifest.

**Alternatives considered:** JSON array. Rejected — adds no value over plain text and requires a parser at runtime.

### Decision: missing manifest when `native = false` and `assertHostBinaries` non-empty is a hard error

**Chosen:** If the manifest file is absent and `assertHostBinaries` is non-empty and `native = false`, `alice switch` aborts with a clear error message before any provisioning occurs.

**Rationale:** A missing manifest means the operator has not completed environment setup. Silent fallback would allow a half-verified provisioning to succeed and leave the user with a workspace that may be missing expected MCP servers.

### Decision: `assertHostBinaries` warning behaviour when `native = true`

**Chosen:** When `native = true` and `assertHostBinaries` is non-empty, `alice switch` prints a single warning line to stderr (e.g. `alice: warning: workspace.assertHostBinaries is set but native = true; host binary assertions will not be checked`) and continues normally.

**Rationale:** The option is meaningful only in non-native mode. Silently ignoring it could leave workspace authors confused about why assertions are not running.

### Decision: pass `wsNative` to `alice-build-workspace.nix` as a string arg (`"1"` / `"0"`)

**Chosen:** `--argstr wsNative "1"` / `"0"`. The embedded build expression converts this to a Nix bool with `wsNative == "1"`.

**Alternatives considered:** `--arg wsNative true` (Nix bool). Rejected — shell variable expansion into `--arg` produces the literal string `true` which is not valid Nix in `--arg` mode without quoting; `--argstr` is unconditionally safe.

## Risks / Trade-offs

- **Risk: prefix heuristic for store paths** — `lib.hasPrefix "/nix/store/"` misses wrapped binaries at non-standard paths. → Mitigation: such commands must appear in `assertHostBinaries` to be used in non-native mode; they are caught at manifest-check time.
- **Risk: manifest must be pre-populated** — the operator must produce `.alice/host-binaries` before running `alice switch` in non-native mode. → Mitigation: clear error message with instructions; `alice init` template explains the convention.
- **Risk: `--argstr` string-to-bool roundtrip** — passing `"1"`/`"0"` via `--argstr` and converting in Nix is slightly indirect. → Acceptable; the conversion is a single `==` comparison.

## Open Questions

None — scope is fully defined.
