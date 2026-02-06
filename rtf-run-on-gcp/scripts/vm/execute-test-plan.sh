#!/usr/bin/env bash
# Execute an RTF test plan on a VM using the rtf-toolbox Docker image.
# This script runs on the remote VM, not the GitHub Actions runner.
#
# Arguments:
#   $1 - Test plan path (relative to home directory)
#   $2 - Apollo key (or "NOT_SET")
#   $3 - Apollo sudo mode ("true" or "false")
#   $4 - RTF toolbox Docker image
#   $5 - GitHub token (or "NOT_SET")
#   $6 - Datadog API key (or "NOT_SET")
#   $7+ - Additional RTF arguments

set -euo pipefail

TEST_PLAN="$1"
APOLLO_KEY_ARG="$2"
APOLLO_SUDO_ARG="$3"
RTF_IMAGE="$4"
GITHUB_TOKEN_ARG="$5"
DD_API_KEY_ARG="$6"
shift 6

OUTDIR="output"

echo "Deleting any pre-existing RTF output directory..."
rm -rf "$OUTDIR/"

# Build Docker environment arguments
ENV_ARGS=()
if [ "$APOLLO_KEY_ARG" != "NOT_SET" ]; then
  ENV_ARGS+=("-e" "APOLLO_KEY=$APOLLO_KEY_ARG")
fi
if [ "$APOLLO_SUDO_ARG" = "true" ]; then
  ENV_ARGS+=("-e" "APOLLO_SUDO=true")
fi
if [ "$GITHUB_TOKEN_ARG" != "NOT_SET" ]; then
  ENV_ARGS+=("-e" "GITHUB_TOKEN=$GITHUB_TOKEN_ARG")
fi
if [ "$DD_API_KEY_ARG" != "NOT_SET" ]; then
  ENV_ARGS+=("-e" "DD_API_KEY=$DD_API_KEY_ARG")
fi

SUCCESS=false

echo "Running test plan: $TEST_PLAN"
echo "Using RTF image: $RTF_IMAGE"

# Run RTF inside the toolbox container
# - Mount Docker socket for nested container execution
# - Mount home directory as workspace
# - Set working directory to home
# - Use sudo for Docker access since user may not be in docker group
if sudo docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME:$HOME" \
  -w "$HOME" \
  "${ENV_ARGS[@]}" \
  "$RTF_IMAGE" \
  rtf run "$TEST_PLAN" --outdir "$OUTDIR" $*; then
  echo "Test plan execution complete"
  SUCCESS=true
else
  echo "WARNING: rtf run failed"
fi

# Create output dir in case rtf run fails
mkdir -p "$OUTDIR"

echo "Deleting file provider output before syncing back results..."
find "$OUTDIR" -type d -name providers -exec rm -rf {} + 2>/dev/null || true
echo "File provider output deleted"

if [ "$SUCCESS" = false ]; then
  exit 1
fi
