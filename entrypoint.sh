#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — Alice Nix Module container entrypoint
#
# Provisions a workspace from the consuming repository's .alice/workspace.nix.
#
# Expected mounts
# ---------------
#   /workspace/source   — the consuming repository root (read-only)
#                         must contain .alice/workspace.nix
#   /workspace/output   — directory to provision (read-write)
#
# Usage
# -----
#   docker run --rm \
#     -v "$PWD:/workspace/source:ro" \
#     -v "$PWD/generated-workspace:/workspace/output" \
#     alice-module:local
#
# Environment variables (optional overrides)
# ------------------------------------------
#   ALICE_SOURCE_DIR      consuming repository root
#                         (default: /workspace/source)
#   ALICE_OUTPUT_DIR      target directory to provision
#                         (default: /workspace/output)
#   ALICE_WORKSPACE_FILE  explicit path to workspace.nix
#                         (default: $ALICE_SOURCE_DIR/.alice/workspace.nix)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults — can be overridden by environment variables
# ---------------------------------------------------------------------------
SOURCE_DIR="${ALICE_SOURCE_DIR:-/workspace/source}"
OUTPUT_DIR="${ALICE_OUTPUT_DIR:-/workspace/output}"

# ---------------------------------------------------------------------------
# Resolve the workspace.nix path
# ---------------------------------------------------------------------------
if [ -n "${ALICE_WORKSPACE_FILE:-}" ]; then
  WORKSPACE_NIX="$ALICE_WORKSPACE_FILE"
else
  WORKSPACE_NIX="${SOURCE_DIR}/.alice/workspace.nix"
fi

# ---------------------------------------------------------------------------
# Validate the workspace configuration file
# ---------------------------------------------------------------------------
if [ ! -e "$WORKSPACE_NIX" ]; then
  echo "" >&2
  echo "ERROR: Alice workspace configuration was not found at:" >&2
  echo "  $WORKSPACE_NIX" >&2
  echo "" >&2
  echo "Create the file or run the command from a repository containing" >&2
  echo "an Alice workspace configuration." >&2
  echo "" >&2
  echo "Example .alice/workspace.nix:" >&2
  echo "" >&2
  echo '  { pkgs, utils, ... }:' >&2
  echo '  {' >&2
  echo '    name = "my-project";' >&2
  echo '    workspace.file."README-alice.txt".text = "Provisioned by Alice.\n";' >&2
  echo '    workspace.packages = [ pkgs.git pkgs.curl ];' >&2
  echo '  }' >&2
  echo "" >&2
  exit 1
fi

if [ ! -f "$WORKSPACE_NIX" ] || [ ! -r "$WORKSPACE_NIX" ]; then
  echo "" >&2
  echo "ERROR: Alice workspace configuration exists but is not a readable file:" >&2
  echo "  $WORKSPACE_NIX" >&2
  echo "" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate the output directory
#
# We check two things:
#   1. The directory exists (basic existence check)
#   2. It is an actual bind-mount from the host, not just the empty stub
#      created inside the image. We detect a stub by checking if the
#      directory is empty AND owned by root with no host files in it.
#      The reliable way is to check for a sentinel file — if /workspace/output
#      is the image stub it will be empty; a real host mount will either be
#      empty (new dir) or have files, but critically it will be writable and
#      resolve to a different inode than the stub.
#
# Simplest reliable approach: require the directory to exist AND be writable.
# The image stub is created as root:root 755 inside the image layer — it is
# technically writable by root. So instead we remove the stub from the image
# (Dockerfile) and rely solely on the host mount creating the directory.
# This check therefore only needs to verify existence.
# ---------------------------------------------------------------------------
if [ ! -d "$OUTPUT_DIR" ]; then
  echo "" >&2
  echo "ERROR: Output directory does not exist: $OUTPUT_DIR" >&2
  echo "" >&2
  echo "Mount a host directory at that path, e.g.:" >&2
  echo "  docker run --rm \\" >&2
  echo "    -v \"\$PWD:/workspace/source:ro\" \\" >&2
  echo "    -v \"\$PWD/generated-workspace:/workspace/output\" \\" >&2
  echo "    alice-module:local" >&2
  echo "" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build the workspace derivation at runtime
#
# We generate a minimal flake in a temporary directory that imports:
#   - the Alice engine from /alice-module (baked into the image)
#   - the consumer's workspace.nix via builtins.path (the mounted file)
#
# The generated flake is evaluated by `nix build`, which writes a ./result
# symlink pointing at the built workspace-<name> binary in the Nix store.
# ---------------------------------------------------------------------------
echo "Alice: reading workspace configuration from:"
echo "  $WORKSPACE_NIX"
echo ""

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Escape the absolute path for safe embedding inside a Nix string literal.
# Nix string literals only need backslash and double-quote escaped.
# Pure bash — no sed required.
_tmp="${WORKSPACE_NIX//\\/\\\\}"        # escape backslashes first
NIX_SAFE_PATH="${_tmp//\"/\\\"}"        # then escape double-quotes
unset _tmp

# Detect the current system triple in bash so we do not need
# builtins.currentSystem (which is forbidden in pure flake evaluation).
CURRENT_SYSTEM="$(nix eval --extra-experimental-features 'nix-command' --impure --raw --expr 'builtins.currentSystem')"

cat > "$BUILD_DIR/flake.nix" <<EOF
{
  description = "Alice runtime workspace build";

  inputs = {
    # Re-use the alice-module flake that is baked into the image so that
    # nixpkgs is already in the Nix store and no network access is needed.
    alice-module.url = "path:/alice-module";
  };

  outputs = { self, alice-module }:
    let
      system  = "${CURRENT_SYSTEM}";
      nixpkgs = alice-module.inputs.nixpkgs;
      pkgs    = import nixpkgs { inherit system; config.allowUnfree = true; };
      mkWs    = alice-module.lib.mkWorkspaceFromFile pkgs;
    in
    {
      packages.\${system}.workspace = mkWs "${NIX_SAFE_PATH}";
      defaultPackage.\${system}     = mkWs "${NIX_SAFE_PATH}";
    };
}
EOF

echo "Alice: building workspace (this may take a moment on first run)..."
echo ""

RESULT_LINK="$BUILD_DIR/result"

nix build \
  --no-warn-dirty \
  --impure \
  --extra-experimental-features "nix-command flakes" \
  --out-link "$RESULT_LINK" \
  "$BUILD_DIR#workspace" 2>&1

# ---------------------------------------------------------------------------
# Locate and run the provisioning binary produced by the build
# ---------------------------------------------------------------------------
WORKSPACE_BIN="$(find "$RESULT_LINK/bin" \( -type f -o -type l \) 2>/dev/null | head -n1)"

if [ -z "$WORKSPACE_BIN" ] || [ ! -x "$WORKSPACE_BIN" ]; then
  echo "" >&2
  echo "ERROR: Nix build succeeded but no executable was found under:" >&2
  echo "  $RESULT_LINK/bin/" >&2
  exit 2
fi

echo ""
echo "Alice: provisioning output directory:"
echo "  $OUTPUT_DIR"
echo ""

exec "$WORKSPACE_BIN" "$OUTPUT_DIR"
