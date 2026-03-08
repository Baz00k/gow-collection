#!/usr/bin/env bash
# Check for Prism Launcher updates from Diegiwg/PrismLauncher-Cracked
# Outputs to GITHUB_OUTPUT: current-version, new-version, update-available

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
PRISM_REPO="${PRISM_REPO:-Diegiwg/PrismLauncher-Cracked}"

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

current=$(grep '^PRISM_LAUNCHER_VERSION=' "$PINS_FILE" | cut -d'=' -f2)
echo "Current version: $current"
echo "current-version=$current" >> "$GITHUB_OUTPUT"

latest=$(gh api "repos/${PRISM_REPO}/releases/latest" --jq '.tag_name' | sed 's/^v//')
echo "Latest version: $latest"
echo "new-version=$latest" >> "$GITHUB_OUTPUT"

if [[ "$current" == "$latest" ]]; then
    echo "No update available"
    echo "update-available=false" >> "$GITHUB_OUTPUT"
else
    echo "Update available: $current -> $latest"
    echo "update-available=true" >> "$GITHUB_OUTPUT"
fi
