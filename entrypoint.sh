#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — Alice Nix Module container entrypoint
#
# Runs the pre-built workspace-blank binary against the target directory.
# The binary was built during `docker build` and its store path is captured
# in the /workspace-blank-result symlink — no Nix evaluation at runtime.
#
# Usage inside the container (called by Docker automatically):
#   entrypoint.sh [target-directory]
#
# If no argument is given, /workspace is used as the default target.
# The target directory must exist (mount it with -v on the host side).
# =============================================================================

set -euo pipefail

WORKSPACE_BINARY="/workspace-blank-result/bin/workspace-blank"
DEFAULT_TARGET="/workspace"

# ---------------------------------------------------------------------------
# Locate the pre-built binary
# ---------------------------------------------------------------------------
if [ ! -x "$WORKSPACE_BINARY" ]; then
  echo "Error: pre-built binary not found at $WORKSPACE_BINARY" >&2
  echo "       The image may not have been built correctly." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve the target directory
# ---------------------------------------------------------------------------
if [ "$#" -eq 0 ]; then
  TARGET_DIR="$DEFAULT_TARGET"
elif [ "$#" -eq 1 ]; then
  TARGET_DIR="$1"
else
  echo "Error: too many arguments." >&2
  echo "" >&2
  echo "Usage: docker run --rm -v \"\$PWD/my-dir:/workspace\" alice-module:local [target-dir]" >&2
  echo "" >&2
  echo "  target-dir   Directory to provision (default: /workspace)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate the target directory exists
# ---------------------------------------------------------------------------
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: target directory does not exist: $TARGET_DIR" >&2
  echo "" >&2
  echo "Hint: mount a host directory with:" >&2
  echo "  docker run --rm -v \"\$PWD/generated-workspace:/workspace\" alice-module:local" >&2
  echo "  (the host directory must already exist before running docker)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Provision the workspace
# ---------------------------------------------------------------------------
exec "$WORKSPACE_BINARY" "$TARGET_DIR"
