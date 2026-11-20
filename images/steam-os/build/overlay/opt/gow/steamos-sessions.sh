#!/bin/bash
# Session names shared by steamos-session-select and the session supervisor.

# Prints the session a name or alias maps to; fails on an unknown name.
steamos_session_name() {
    case "$1" in
        steam|gamescope|gamepad|gaming)
            echo "gamescope"
            ;;
        plasma|desktop|kde)
            echo "plasma"
            ;;
        *)
            return 1
            ;;
    esac
}
