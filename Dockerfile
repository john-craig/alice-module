# =============================================================================
# Dockerfile — Alice Nix Module
#
# Builds a container that provisions a Bob workspace from the consuming
# repository's .alice/workspace.nix at runtime — no workspace definition
# is baked into the image.
#
# Build:
#   docker build -t alice-module:local .
#
# Run:
#   mkdir -p generated-workspace
#   docker run --rm \
#     -v "$PWD:/workspace/source:ro" \
#     -v "$PWD/generated-workspace:/workspace/output" \
#     -v "$HOME/.ssh:/root/.ssh:ro" \
#     -v "$SSH_AUTH_SOCK:/ssh-agent" \
#     -e SSH_AUTH_SOCK=/ssh-agent \
#     alice-module:local
#
# Mount points
# ------------
#   /workspace/source   the consuming repository root (read-only)
#                       must contain .alice/workspace.nix
#   /workspace/output   the directory to be provisioned (read-write)
#
# The container exits after provisioning; files remain on the host.
# =============================================================================

# Official multi-arch Nix image (linux/amd64 and linux/arm64).
# The architecture is selected automatically by the Docker daemon — no
# macOS-specific system values are ever hardcoded here.
FROM nixos/nix:latest

# ---------------------------------------------------------------------------
# 1. Global Nix configuration
#    - Enable flakes and the new nix command
#    - Allow the root user inside the container (required by nixos/nix image)
# ---------------------------------------------------------------------------
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf && \
    echo "filter-syscalls = false" >> /etc/nix/nix.conf

# ---------------------------------------------------------------------------
# 2. Copy repository into the image
# ---------------------------------------------------------------------------
WORKDIR /alice-module
COPY . .

# ---------------------------------------------------------------------------
# 3. Validate the flake and pre-warm the Nix store
#
#    nix flake check  — verifies the alice-module flake is valid; a failing
#                       flake produces a failed Docker build, not a bad image.
#
#    nix build .#workspace-blank  — pre-fetches nixpkgs and builds the blank
#                       workspace so that all flake inputs (especially nixpkgs)
#                       are already in the Nix store inside the image.  This
#                       means runtime builds from .alice/workspace.nix can
#                       reuse the cached store and do not need network access
#                       for the base packages.
#
#    The pre-built result symlink is NOT used at runtime — the entrypoint
#    always evaluates the consumer's .alice/workspace.nix dynamically.
# ---------------------------------------------------------------------------
RUN nix flake check --no-warn-dirty -L && \
    nix build .#workspace-blank --no-warn-dirty -o /workspace-blank-result

# ---------------------------------------------------------------------------
# 4. Install the entrypoint script
# ---------------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------------------------------------------------------------------------
# 5. Runtime mount stubs
#
#    /workspace/source  — bind-mount the consuming repository here (read-only)
#                         must contain .alice/workspace.nix
#    /workspace/output  — bind-mount the output directory here (read-write)
#
#    NOTE: /workspace/output is intentionally NOT pre-created here.
#    If it were, the entrypoint's "output directory does not exist" check
#    would always pass even when the host forgot to mount it.
#    The host must explicitly mount a directory at /workspace/output.
# ---------------------------------------------------------------------------
RUN mkdir -p /workspace/source

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
