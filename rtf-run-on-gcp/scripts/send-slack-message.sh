#!/usr/bin/env bash
# Send messages to Slack using a bot API token.
#
# Required flags:
#   --token <token>      - Slack bot API token
#   --channel <id>       - Target channel ID
#   --message <text>     - Message text
#
# Optional flags:
#   --thread-ts <ts>     - Thread timestamp for replies
#
# To create threads, capture the output of this script and pass it as
# --thread-ts for subsequent messages.

set -euo pipefail

# Defaults
SLACK_TOKEN=""
SLACK_CHANNEL_ID=""
SLACK_THREAD_TS=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) SLACK_TOKEN="$2"; shift 2 ;;
    --channel) SLACK_CHANNEL_ID="$2"; shift 2 ;;
    --thread-ts) SLACK_THREAD_TS="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validation
[ -z "$SLACK_TOKEN" ] && { echo "ERROR: --token is required" >&2; exit 1; }
[ -z "$SLACK_CHANNEL_ID" ] && { echo "ERROR: --channel is required" >&2; exit 1; }
[ -z "$MESSAGE" ] && { echo "ERROR: --message is required" >&2; exit 1; }

if [ -n "$SLACK_THREAD_TS" ]; then
  THREAD_DETAILS=", \"thread_ts\": \"$SLACK_THREAD_TS\""
else
  THREAD_DETAILS=""
fi

curl -s \
  -H 'Content-type: application/json; charset=utf-8' \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -d "{ \"channel\": \"$SLACK_CHANNEL_ID\", \"text\": \"$MESSAGE\" $THREAD_DETAILS }" \
  "https://slack.com/api/chat.postMessage" |
  jq -r '.ts'
