#!/usr/bin/env bash
# Setup the VM for RTF test execution.
# This script runs on the remote VM, not the GitHub Actions runner.
#
# It authenticates to Artifact Registry using the VM's service account
# and pulls the rtf-toolbox Docker image.
#
# Required flags:
#   --image <image>        - RTF toolbox image to pull
#
# Optional flags:
#   --ghcr-token <token>   - GitHub token for ghcr.io authentication

set -euo pipefail

# Defaults
RTF_IMAGE=""
GHCR_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) RTF_IMAGE="$2"; shift 2 ;;
    --ghcr-token) GHCR_TOKEN="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validation
[ -z "$RTF_IMAGE" ] && { echo "ERROR: --image is required" >&2; exit 1; }

echo "Disabling unattended upgrades..."
sudo systemctl disable --now unattended-upgrades

echo "Configuring Docker authentication for Artifact Registry..."
# The VM's service account (rtf-morgue-github-actions) has reader access to Artifact Registry
# Use sudo since user may not be in docker group yet
#
# Use `docker login` with an access token instead of `gcloud auth configure-docker`.
# The latter writes a credHelpers entry referencing docker-credential-gcloud, which
# doesn't exist inside the RTF toolbox container where config.json is mounted.
# Direct login stores base64-encoded credentials in the auths section, avoiding any
# dependency on external credential helper binaries.
sudo gcloud auth print-access-token | sudo docker login -u oauth2accesstoken --password-stdin https://us-central1-docker.pkg.dev

if [ -n "$GHCR_TOKEN" ]; then
  echo "Authenticating with GitHub Container Registry..."
  echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u github --password-stdin
fi

echo "Pulling RTF toolbox image: $RTF_IMAGE"
sudo docker pull "$RTF_IMAGE"

echo "RTF toolbox setup complete"

# Verify the image is available
echo "Verifying RTF binary..."
sudo docker run --rm "$RTF_IMAGE" rtf --help | head -5
