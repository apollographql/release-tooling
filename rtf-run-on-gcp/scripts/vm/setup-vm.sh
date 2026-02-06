#!/usr/bin/env bash
# Setup the VM for RTF test execution.
# This script runs on the remote VM, not the GitHub Actions runner.
#
# It authenticates to Artifact Registry using the VM's service account
# and pulls the rtf-toolbox Docker image.
#
# Arguments:
#   $1 - RTF toolbox image to pull

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <RTF_IMAGE>"
  exit 1
fi

RTF_IMAGE="$1"

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

echo "Pulling RTF toolbox image: $RTF_IMAGE"
sudo docker pull "$RTF_IMAGE"

echo "RTF toolbox setup complete"

# Verify the image is available
echo "Verifying RTF binary..."
sudo docker run --rm "$RTF_IMAGE" rtf --help | head -5
