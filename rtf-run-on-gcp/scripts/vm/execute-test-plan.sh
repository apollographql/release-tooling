#!/usr/bin/env bash
# Execute an RTF test plan on a VM using the rtf-toolbox Docker image.
# This script runs on the remote VM, not the GitHub Actions runner.
#
# Required flags:
#   --test-plan <path>   - Test plan path (relative to home directory)
#   --image <image>      - RTF toolbox Docker image
#
# Optional flags:
#   --apollo-key <key>   - Apollo API key
#   --apollo-sudo        - Enable Apollo sudo mode (boolean flag)
#   --github-token <tok> - GitHub token
#   --dd-api-key <key>   - Datadog API key
#   --                   - Everything after this passes through to RTF

set -euo pipefail

# Defaults
TEST_PLAN=""
APOLLO_KEY=""
APOLLO_SUDO=false
RTF_IMAGE=""
GITHUB_TOKEN=""
DD_API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test-plan) TEST_PLAN="$2"; shift 2 ;;
    --apollo-key) APOLLO_KEY="$2"; shift 2 ;;
    --apollo-sudo) APOLLO_SUDO=true; shift ;;
    --image) RTF_IMAGE="$2"; shift 2 ;;
    --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
    --dd-api-key) DD_API_KEY="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validation
[ -z "$TEST_PLAN" ] && { echo "ERROR: --test-plan is required" >&2; exit 1; }
[ -z "$RTF_IMAGE" ] && { echo "ERROR: --image is required" >&2; exit 1; }

OUTDIR="output"

echo "Deleting any pre-existing RTF output directory..."
rm -rf "$OUTDIR/"

# Build Docker environment arguments
ENV_ARGS=()
if [ -n "$APOLLO_KEY" ]; then
  ENV_ARGS+=("-e" "APOLLO_KEY=$APOLLO_KEY")
fi
if [ "$APOLLO_SUDO" = "true" ]; then
  ENV_ARGS+=("-e" "APOLLO_SUDO=true")
fi
if [ -n "$GITHUB_TOKEN" ]; then
  ENV_ARGS+=("-e" "GITHUB_TOKEN=$GITHUB_TOKEN")
fi
if [ -n "$DD_API_KEY" ]; then
  ENV_ARGS+=("-e" "DD_API_KEY=$DD_API_KEY")
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
  rtf run "$TEST_PLAN" --outdir "$OUTDIR" "$@"; then
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
