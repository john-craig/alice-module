# =============================================================================
# Dockerfile — Alice Nix Module
#
# Builds a short-lived CLI container that provisions a Bob workspace into a
# bind-mounted host directory.
#
# Build:
#   docker build -t alice-module:local .
#
# Run:
#   mkdir -p generated-workspace
#   docker run --rm \
#     -v "$PWD/generated-workspace:/workspace" \
#     alice-module:local
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
# 3. Validate the flake and pre-build the workspace-blank package
#
#    nix flake check  — runs the blank-workspace-output check; a failing
#                       flake produces a failed Docker build, not a bad image.
#    nix build        — bakes the workspace-blank store closure into the
#                       image and creates a ./result symlink pointing at it.
#                       The entrypoint uses this symlink so no Nix evaluation
#                       is needed at container runtime.
# ---------------------------------------------------------------------------
RUN nix flake check --no-warn-dirty -L && \
    nix build .#workspace-blank --no-warn-dirty -o /workspace-blank-result

# ---------------------------------------------------------------------------
# 4. Install the entrypoint script
# ---------------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------------------------------------------------------------------------
# 5. Runtime defaults
#
#    /workspace is the bind-mount point.  The host directory must be mounted
#    here with:  -v "$PWD/my-dir:/workspace"
#    The directory is created here as a convenience mount-point stub.
# ---------------------------------------------------------------------------
RUN mkdir -p /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
