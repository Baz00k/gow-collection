#!/bin/bash
# =============================================================================
# logging.sh — Shared logging utilities for GoW scripts
# =============================================================================
# Source this file to use standardized logging functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
#
# Functions provided:
#   log_info <message>    — Info log (green)
#   log_error <message>   — Error log (red)
#   log_warn <message>    — Warning log (yellow)
#   log_debug <message>   — Debug log (blue, GOW_DEBUG >= 1)
#   log_verbose <message> — Verbose log (blue, GOW_DEBUG >= 2)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GOW_DEBUG="${GOW_DEBUG:-0}"
case "${GOW_DEBUG,,}" in
    0|false|no|off) GOW_DEBUG_LEVEL=0 ;;
    1|true|yes|on) GOW_DEBUG_LEVEL=1 ;;
    2) GOW_DEBUG_LEVEL=2 ;;
    3) GOW_DEBUG_LEVEL=3 ;;
    *)
        echo -e "${YELLOW}[WARN]${NC} GOW_DEBUG: unknown value '${GOW_DEBUG}', defaulting to 0" >&2
        GOW_DEBUG_LEVEL=0
        ;;
esac
export GOW_DEBUG_LEVEL

if [ "${GOW_DEBUG_LEVEL}" -ge 3 ]; then
    export PS4='+ ${BASH_SOURCE:-}:${LINENO}: '
    set -x
fi

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_debug() { [ "${GOW_DEBUG_LEVEL}" -ge 1 ] && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }
log_verbose() { [ "${GOW_DEBUG_LEVEL}" -ge 2 ] && echo -e "${BLUE}[VERBOSE]${NC} $*" || true; }
