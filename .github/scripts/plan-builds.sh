#!/usr/bin/env bash
# Decide which images CI must act on for the current event.
#
# Domain rule (intentionally hard-coded, not a generic graph engine):
#   - `base` is the only parent image.
#   - every non-base image depends on `base`.
#   - apps never depend on other apps.
#
# So:
#   - base changed            -> validate base + ALL apps in one run
#   - only apps changed       -> build just those apps
#   - workflow/global changed -> build everything (base graph validation)
#
# Inputs (env):
#   EVENT_NAME   github.event_name
#   BASE_REF     diff base (e.g. origin/main or a commit sha); empty => build all
#   HEAD_REF     diff head (default HEAD)
#
# Outputs (written to $GITHUB_OUTPUT, also echoed):
#   base_changed     true|false
#   has_app_changes  true|false   (apps to build on the normal path)
#   app_matrix       JSON {"include":[{image_name,image_dir}, ...]}
#   summary          human-readable affected list

set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
BASE_REF="${BASE_REF:-}"
HEAD_REF="${HEAD_REF:-HEAD}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

all_app_dirs() {
    find images -maxdepth 1 -mindepth 1 -type d ! -name base | sort
}

emit() {
    local base_changed="$1" app_dirs="$2"
    local matrix='{"include":[]}'
    local items=() summary_apps=()

    for dir in $app_dirs; do
        local name
        name=$(basename "$dir")
        [[ -f "${dir}/build/pins.env" ]] || continue
        items+=("{\"image_name\":\"${name}\",\"image_dir\":\"${dir}\"}")
        summary_apps+=("$name")
    done

    if [[ ${#items[@]} -gt 0 ]]; then
        matrix="{\"include\":[$(IFS=,; echo "${items[*]}")]}"
    fi

    local has_app_changes=false
    [[ ${#items[@]} -gt 0 ]] && has_app_changes=true

    local summary=""
    [[ "$base_changed" == "true" ]] && summary="base"
    if [[ ${#summary_apps[@]} -gt 0 ]]; then
        [[ -n "$summary" ]] && summary+=", "
        summary+="$(IFS=,; echo "${summary_apps[*]}")"
    fi
    [[ -z "$summary" ]] && summary="(no images)"

    {
        echo "base_changed=${base_changed}"
        echo "has_app_changes=${has_app_changes}"
        echo "app_matrix=${matrix}"
        echo "summary=${summary}"
    } | tee -a "$GITHUB_OUTPUT"
}

build_all() {
    echo "Planning: build everything (base + all apps)" >&2
    emit true "$(all_app_dirs)"
}

# Force full graph for manual runs or when we cannot trust a diff.
if [[ "$EVENT_NAME" == "workflow_dispatch" || -z "$BASE_REF" ]]; then
    build_all
    exit 0
fi

if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
    echo "::warning::Diff base ${BASE_REF} unavailable - building everything" >&2
    build_all
    exit 0
fi

CHANGED=$(git diff --name-only "$BASE_REF" "$HEAD_REF" || true)
echo "Changed files:" >&2
echo "$CHANGED" >&2

# Changes to CI plumbing or global tests can affect every image.
if echo "$CHANGED" | grep -qE '^(\.github/workflows/ci\.yml|\.github/scripts/|tests/)'; then
    echo "Planning: CI/global change detected - building everything" >&2
    build_all
    exit 0
fi

# Any change under images/base means validate the whole graph.
if echo "$CHANGED" | grep -qE '^images/base/'; then
    echo "Planning: base changed - validate base + all apps" >&2
    emit true "$(all_app_dirs)"
    exit 0
fi

# Otherwise: only the directly-changed apps.
CHANGED_APPS=$(echo "$CHANGED" | grep -oE '^images/[^/]+' | sort -u | grep -v '^images/base$' || true)
if [[ -z "$CHANGED_APPS" ]]; then
    echo "Planning: no image changes" >&2
    emit false ""
    exit 0
fi

echo "Planning: changed apps -> $CHANGED_APPS" >&2
emit false "$CHANGED_APPS"
