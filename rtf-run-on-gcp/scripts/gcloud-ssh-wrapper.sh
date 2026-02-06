#!/usr/bin/env bash
# SSH wrapper for gcloud compute.
# Used by rsync and direct SSH commands to connect to GCP VMs.
#
# The GHA runner is already authenticated via Workload Identity,
# so no additional impersonation is needed.

: "${GCP_PROJECT:="runtime-testing-framework"}"

host="$1"
shift

# This prevents the "Pseudo-terminal will not be allocated because stdin is not a terminal" warning
exec gcloud compute ssh \
  --project="$GCP_PROJECT" \
  --zone="us-central1-b" \
  "$host" \
  -- "$@"
