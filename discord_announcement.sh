#!/bin/sh

# Replace the following with the webhook URL that you need to post
# messages to a private Discord server
WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_KEY"

# Replace the following with the Discord user name that will post the messages
USERNAME=YOUR_USERNAME

JSON=$(jq --null-input --compact-output --arg msg "$1" '{"username":"$USERNAME","content":$msg}')

curl -X POST -H "Content-Type: application/json" -d "$JSON" "$WEBHOOK_URL"
