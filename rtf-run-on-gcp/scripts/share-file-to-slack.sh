#!/usr/bin/env bash
# Upload a file to Slack using a bot API token.
#
# Required environment variables:
#   SLACK_TOKEN      - Slack bot API token
#   SLACK_CHANNEL_ID - Target channel ID
#
# Optional environment variables:
#   SLACK_THREAD_TS  - Thread timestamp for sharing in a thread
#
# Usage:
#   SLACK_CHANNEL_ID="..." SLACK_TOKEN="..." ./share-file-to-slack.sh results.tar.gz

set -euo pipefail

: "${SLACK_TOKEN:=""}"
: "${SLACK_THREAD_TS:=""}"
: "${SLACK_CHANNEL_ID:=""}"

FILE="$1"
FNAME="$(basename "$FILE")"

if [ -z "$SLACK_TOKEN" ]; then
  echo "ERROR: SLACK_TOKEN environment variable is not set" >&2
  exit 1
fi

if [ -z "$SLACK_CHANNEL_ID" ]; then
  echo "ERROR: SLACK_CHANNEL_ID environment variable is not set" >&2
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 1
fi

if [ -n "$SLACK_THREAD_TS" ]; then
  THREAD_DETAILS=", \"thread_ts\": \"$SLACK_THREAD_TS\""
else
  THREAD_DETAILS=""
fi

# Get the upload URL
LENGTH=$(wc -c < "$FILE" | xargs)
OUTPUT="$(curl -s \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "filename=$FNAME" \
  -d "length=$LENGTH" \
  "https://slack.com/api/files.getUploadURLExternal"
)"

UPLOAD_URL="$(echo "$OUTPUT" | jq -r '.upload_url')"
FILE_ID="$(echo "$OUTPUT" | jq -r '.file_id')"

if [ "$UPLOAD_URL" = "null" ] || [ -z "$UPLOAD_URL" ]; then
  echo "ERROR: Failed to get upload URL from Slack" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

# Perform the upload
curl -s --data-binary "@$FILE" "$UPLOAD_URL"

# Complete and share
curl -s \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{ \"channel_id\": \"$SLACK_CHANNEL_ID\", \"files\": [{\"id\": \"$FILE_ID\"}] $THREAD_DETAILS }" \
  "https://slack.com/api/files.completeUploadExternal" | jq -r '.ok'
