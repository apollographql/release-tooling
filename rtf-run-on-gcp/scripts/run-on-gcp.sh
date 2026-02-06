#!/usr/bin/env bash
# Main orchestration script for running RTF test plans on GCP VMs.
#
# Required environment variables:
#   TEST_PLAN_PATH       - Path to the test plan YAML file
#   VM_NAME              - Name for the VM (without 'rtf-' prefix)
#   RTF_IMAGE            - RTF toolbox Docker image
#   TRIGGERING_USER      - User who triggered the workflow
#   GH_RUN_URL           - URL to the GitHub Actions run
#   REPO_NAME            - Name of the repository
#
# Optional environment variables:
#   GCP_PROJECT          - GCP project ID (default: runtime-testing-framework)
#   SERVICE_ACCOUNT_NAME - GCP service account name (default: rtf-morgue-github-actions)
#   VARIABLES_FILE       - Path to variables.json file
#   SLACK_CHANNEL_ID     - Slack channel for notifications
#   SLACK_TOKEN          - Slack bot token
#   GITHUB_TOKEN         - GitHub token for GitHub providers
#   APOLLO_KEY           - Apollo API key
#   APOLLO_SUDO          - Enable Apollo sudo mode
#   DD_API_KEY           - Datadog API key for metric emission
#   VM_TIMEOUT           - Maximum VM runtime (default: 6h)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================

# Used to filter out annoying gcloud warning messages while preserving exit codes
FILTER_OUT="WARNING:"

: "${VM_TIMEOUT:="6h"}"
: "${APOLLO_SUDO:=""}"
: "${SLACK_CHANNEL_ID:=""}"
: "${SLACK_TOKEN:=""}"
: "${GITHUB_TOKEN:=""}"
: "${APOLLO_KEY:=""}"
: "${DD_API_KEY:=""}"
: "${VARIABLES_FILE:=""}"
: "${GCP_PROJECT:="runtime-testing-framework"}"
: "${SERVICE_ACCOUNT_NAME:="rtf-morgue-github-actions"}"

SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
GCLOUD_SSH_WRAPPER="${SCRIPT_DIR}/gcloud-ssh-wrapper.sh"

# =============================================================================
# Slack
# =============================================================================

SLACK_ENABLED=false
if [ -n "$SLACK_TOKEN" ] && [ -n "$SLACK_CHANNEL_ID" ]; then
  SLACK_ENABLED=true
  export SLACK_TOKEN SLACK_CHANNEL_ID
fi

function slack_message {
  if [ "$SLACK_ENABLED" = "true" ]; then
    "${SCRIPT_DIR}/send-slack-message.sh" "$@"
  else
    echo "[Slack] $*"
  fi
}

function slack_file {
  if [ "$SLACK_ENABLED" = "true" ]; then
    "${SCRIPT_DIR}/share-file-to-slack.sh" "$@"
  else
    echo "[Slack] Would upload: $*"
  fi
}

# =============================================================================
# VM Operations
# =============================================================================

function rsync_to_vm {
  local vm_name="$1" local_dir="$2" remote_dir="$3"
  heading "Syncing $local_dir to $vm_name:$remote_dir"
  rsync -e "bash $GCLOUD_SSH_WRAPPER" \
    --compress --recursive --times \
    --exclude "gha-creds-*.json" \
    --exclude "target/" \
    --exclude ".git/" \
    "$local_dir" "$vm_name:$remote_dir" \
    2> >(grep -v "${FILTER_OUT}")
}

function rsync_from_vm {
  local vm_name="$1" remote_path="$2" local_dir="$3"
  heading "Pulling $remote_path from $vm_name"
  mkdir -p "$local_dir"
  rsync -e "bash $GCLOUD_SSH_WRAPPER" \
    --compress --recursive --times \
    "$vm_name:$remote_path" "$local_dir" \
    2> >(grep -v "${FILTER_OUT}")
}

function vm_ssh {
  local vm_name="$1"; shift
  bash "$GCLOUD_SSH_WRAPPER" "$vm_name" "$@" \
    2> >(grep -v "${FILTER_OUT}")
}

function create_vm {
  local vm_name="$1"
  heading "Creating VM '$vm_name'"

  gcloud beta compute instances create "$vm_name" \
    --project="$GCP_PROJECT" \
    --zone=us-central1-b \
    --machine-type=e2-highcpu-32 \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --instance-termination-action=DELETE \
    --max-run-duration="$VM_TIMEOUT" \
    --min-cpu-platform=Automatic \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels="goog-ec-src=vm_add-gcloud,perf-test=$vm_name" \
    --reservation-affinity=any \
    --source-machine-image=router-perf-master \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    2> >(grep -v "${FILTER_OUT}") \
    > /dev/null

  heading "Waiting for VM to come up..."
  local ssh_cmd="bash $GCLOUD_SSH_WRAPPER $vm_name ls"
  local login_success=false
  local i=0

  while (( i < 20 )); do
    echo "  Attempting SSH to $vm_name (attempt $((i+1))/20)..."
    if $ssh_cmd 2> >(grep -v "${FILTER_OUT}") > /dev/null; then
      heading "SSH to $vm_name success"
      login_success=true
      break
    fi
    echo "  Attempt $((i+1)) failed. Retrying..."
    sleep 10
    ((i++))
  done

  if [ "$login_success" = false ]; then
    error_and_exit "Failed to SSH to $vm_name after 20 attempts"
  fi
}

function setup_vm {
  local vm_name="$1"
  rsync_to_vm "$vm_name" "${SCRIPT_DIR}/vm/" "./.rtf-action/"
  rsync_to_vm "$vm_name" "${GITHUB_WORKSPACE:-.}/" "./${REPO_NAME}/"
  heading "Setting up RTF toolbox"
  vm_ssh "$vm_name" bash -i "./.rtf-action/setup-vm.sh" "$RTF_IMAGE"
}

function run_test_plan {
  local vm_name="$1" test_plan="$2" extra_args="${3:-}"
  heading "Running: $test_plan"
  vm_ssh "$vm_name" bash -i "./.rtf-action/execute-test-plan.sh" \
    "$test_plan" "${APOLLO_KEY:-NOT_SET}" "${APOLLO_SUDO:-false}" "$RTF_IMAGE" "${GITHUB_TOKEN:-NOT_SET}" "${DD_API_KEY:-NOT_SET}" "$extra_args"
}

function collect_results {
  local vm_name="$1"
  heading "Archiving results"
  vm_ssh "$vm_name" tar -czvf results.tar.gz output/
  rsync_from_vm "$vm_name" "results.tar.gz" "output/"
}

# =============================================================================
# Main
# =============================================================================

[ -z "${TEST_PLAN_PATH:-}" ] && error_and_exit "TEST_PLAN_PATH is required"
[ -z "${VM_NAME:-}" ] && error_and_exit "VM_NAME is required"
[ -z "${RTF_IMAGE:-}" ] && error_and_exit "RTF_IMAGE is required"
[ -z "${REPO_NAME:-}" ] && error_and_exit "REPO_NAME is required"

VM_FULL_NAME="rtf-${VM_NAME}"

heading "RTF Run on GCP"
echo "  Test Plan: $TEST_PLAN_PATH"
echo "  VM: $VM_FULL_NAME"
echo "  Timeout: $VM_TIMEOUT"
echo "  Slack: $SLACK_ENABLED"

# Start Slack thread
if [ "$SLACK_ENABLED" = "true" ]; then
  SLACK_THREAD_TS="$(slack_message ":frog-thread: Starting RTF run <${GH_RUN_URL}|here>\n- Test: \`${TEST_PLAN_PATH}\`\n- By: \`${TRIGGERING_USER}\`")"
  export SLACK_THREAD_TS
fi

# Create and setup VM
slack_message ":frog-typing-away: Creating VM \`${VM_FULL_NAME}\`..."
if ! create_vm "$VM_FULL_NAME"; then
  slack_message ":frog-alarm: VM creation failed"
  exit 1
fi
slack_message ":frog-thumbs-up: VM created"

setup_vm "$VM_FULL_NAME"

# Run test
GH_BASE="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/blob/${GITHUB_REF_NAME:-main}"
slack_message ":frog-eyes: Test plan: <${GH_BASE}/${TEST_PLAN_PATH}|link>"
slack_message ":frog-run: Running..."

TEST_PLAN_PATH_VM="${REPO_NAME}/${TEST_PLAN_PATH}"
EXTRA_ARGS=""
[ -n "$VARIABLES_FILE" ] && EXTRA_ARGS="--vars ${REPO_NAME}/${VARIABLES_FILE}"

if run_test_plan "$VM_FULL_NAME" "$TEST_PLAN_PATH_VM" "$EXTRA_ARGS"; then
  slack_message ":yay-frog: Complete!"
  slack_message ":frog-reading: Collecting results..."
  collect_results "$VM_FULL_NAME"

  [ -f "output/results.tar.gz" ] && {
    slack_message ":frog-rocket: Uploading results..."
    slack_file "output/results.tar.gz"
  }

  slack_message ":frog-good-thinking: VM \`${VM_FULL_NAME}\` available for ${VM_TIMEOUT}"
  heading "Done"
else
  slack_message ":frog-alarm: Test failed"
  slack_message ":frog-stop: VM \`${VM_FULL_NAME}\` available for ${VM_TIMEOUT}"
  exit 1
fi
