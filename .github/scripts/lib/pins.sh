#!/usr/bin/env bash
# Shared helper: replace one value in a pins.env file, literally.
#
# Update scripts write values that come from upstream (release tags, URLs), so
# a value must never become part of a sed/awk program, `eval`, or `source`:
# GNU sed alone can run shell commands from a crafted replacement. set_pin
# treats the value as plain data.
#
# Usage:
#   source .github/scripts/lib/pins.sh
#   set_pin KEY VALUE [FILE]      # FILE defaults to $PINS_FILE
#   set_pins UPDATES FILE         # UPDATES holds KEY=VALUE lines from apply.sh
#
# The key must already appear exactly once; adding keys is a reviewed change,
# not something an update run does. Values may not contain whitespace or
# control characters. What a value may look like is enforced again, per key,
# by .github/scripts/validate-pin-changes.sh before anything reaches a PR.

set_pin() {
    local key="$1" value="$2" file="${3:-${PINS_FILE:?}}"
    local tmp line found=0

    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo "ERROR: invalid pin key '${key}'" >&2
        return 1
    fi
    if [[ -z "$value" || "$value" == *[[:space:][:cntrl:]]* ]]; then
        echo "ERROR: invalid value for ${key}: '${value}'" >&2
        return 1
    fi

    tmp=$(mktemp "${file}.XXXXXX")
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "${key}="* ]]; then
            printf '%s=%s\n' "$key" "$value"
            found=$((found + 1))
        else
            printf '%s\n' "$line"
        fi
    done < "$file" > "$tmp"

    if [[ "$found" -ne 1 ]]; then
        rm -f "$tmp"
        echo "ERROR: expected one ${key}= line in ${file}, found ${found}" >&2
        return 1
    fi
    chmod --reference="$file" "$tmp"
    mv "$tmp" "$file"
}

set_pins() {
    local updates="$1" file="$2" line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" != *=* ]]; then
            echo "ERROR: expected KEY=VALUE, got '${line}'" >&2
            return 1
        fi
        set_pin "${line%%=*}" "${line#*=}" "$file" || return 1
    done < "$updates"
}
