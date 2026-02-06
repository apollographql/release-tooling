#!/usr/bin/env bash
# Upload a file to Slack using a bot API token.
#
# Required flags:
#   --token <token>    - Slack bot API token
#   --channel <id>     - Target channel ID
#   --file <path>      - File to upload
#
# Optional flags:
#   --thread-ts <ts>   - Thread timestamp for sharing in a thread

set -euo pipefail

# Defaults
SLACK_TOKEN=""
SLACK_CHANNEL_ID=""
SLACK_THREAD_TS=""
FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) SLACK_TOKEN="$2"; shift 2 ;;
    --channel) SLACK_CHANNEL_ID="$2"; shift 2 ;;
    --thread-ts) SLACK_THREAD_TS="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validation
[ -z "$SLACK_TOKEN" ] && { echo "ERROR: --token is required" >&2; exit 1; }
[ -z "$SLACK_CHANNEL_ID" ] && { echo "ERROR: --channel is required" >&2; exit 1; }
[ -z "$FILE" ] && { echo "ERROR: --file is required" >&2; exit 1; }

FNAME="$(basename "$FILE")"

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
