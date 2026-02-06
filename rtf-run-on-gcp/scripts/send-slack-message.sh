#!/usr/bin/env bash
# Send messages to Slack using a bot API token.
#
# Required environment variables:
#   SLACK_TOKEN      - Slack bot API token
#   SLACK_CHANNEL_ID - Target channel ID
#
# Optional environment variables:
#   SLACK_THREAD_TS  - Thread timestamp for replies
#
# Usage:
#   SLACK_CHANNEL_ID="..." SLACK_TOKEN="..." ./send-slack-message.sh 'Hello, world!'
#
# To create threads, capture the output of this script and set it as SLACK_THREAD_TS
# for subsequent messages.

set -euo pipefail

: "${SLACK_TOKEN:=""}"
: "${SLACK_THREAD_TS:=""}"
: "${SLACK_CHANNEL_ID:=""}"

if [ -z "$SLACK_TOKEN" ]; then
  echo "ERROR: SLACK_TOKEN environment variable is not set" >&2
  exit 1
fi

if [ -z "$SLACK_CHANNEL_ID" ]; then
  echo "ERROR: SLACK_CHANNEL_ID environment variable is not set" >&2
  exit 1
fi

if [ -n "$SLACK_THREAD_TS" ]; then
  THREAD_DETAILS=", \"thread_ts\": \"$SLACK_THREAD_TS\""
else
  THREAD_DETAILS=""
fi

curl -s \
  -H 'Content-type: application/json; charset=utf-8' \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -d "{ \"channel\": \"$SLACK_CHANNEL_ID\", \"text\": \"$*\" $THREAD_DETAILS }" \
  "https://slack.com/api/chat.postMessage" |
  jq -r '.ts'
