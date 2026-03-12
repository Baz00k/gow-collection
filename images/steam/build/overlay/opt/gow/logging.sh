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
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
