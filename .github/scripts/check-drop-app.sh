#!/usr/bin/env bash
# Check for drop-app updates from Drop-OSS/drop-app
# Outputs to GITHUB_OUTPUT: current-version, new-version, update-available

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

# Read current version from pins.env
current=$(grep '^DROP_APP_VERSION=' "$PINS_FILE" | cut -d'=' -f2)
echo "Current version: $current"
echo "current-version=$current" >> "$GITHUB_OUTPUT"

# Get latest release from GitHub API
latest_raw=$(curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty')
latest="${latest_raw#v}"  # Strip v prefix
echo "Latest version: $latest"
echo "new-version=$latest" >> "$GITHUB_OUTPUT"

if [[ "$current" == "$latest" ]]; then
    echo "No update available"
    echo "update-available=false" >> "$GITHUB_OUTPUT"
else
    echo "Update available: $current -> $latest"
    echo "update-available=true" >> "$GITHUB_OUTPUT"
fi
