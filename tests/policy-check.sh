#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse arguments - IMAGE_DIR before --strict
IMAGE_DIR=""
STRICT_MODE=""

for arg in "$@"; do
    if [[ "${arg}" == "--strict" ]]; then
        STRICT_MODE="--strict"
    elif [[ -z "${IMAGE_DIR}" ]] && [[ "${arg}" != -* ]]; then
        IMAGE_DIR="${arg}"
    fi
done

RESULTS_DIR="${RESULTS_DIR:-${PROJECT_ROOT}/test-results/evidence}"
RESULTS_FILE="${RESULTS_DIR}/policy-check.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

mkdir -p "${RESULTS_DIR}"

# Clear previous results
: > "${RESULTS_FILE}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    echo "[INFO] $*" >> "${RESULTS_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    echo "[ERROR] $*" >> "${RESULTS_FILE}"
    ((ERRORS++)) || true
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    echo "[WARN] $*" >> "${RESULTS_FILE}"
    ((WARNINGS++)) || true
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    echo "[PASS] $*" >> "${RESULTS_FILE}"
}

# Get list of image directories to check
get_image_dirs() {
    if [[ -n "${IMAGE_DIR}" ]]; then
        # Single image directory specified
        if [[ -d "${IMAGE_DIR}" ]]; then
            echo "${IMAGE_DIR}"
        else
            log_error "Image directory not found: ${IMAGE_DIR}"
            return 1
        fi
    else
        # Scan all images/*/ directories
        find "${PROJECT_ROOT}/images" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true
    fi
}

check_floating_refs() {
    log_info "Checking for floating image references..."
    local found_violations=0

    # Scan Dockerfiles in specified image dirs (or all if not specified)
    while IFS= read -r imgdir; do
        if [[ -d "${imgdir}/build" ]]; then
            while IFS= read -r file; do
                if [[ -f "${file}" ]]; then
                    while IFS= read -r line; do
                        if [[ -n "${line}" ]]; then
                            local linenum content
                            linenum=$(echo "${line}" | cut -d: -f1)
                            content=$(echo "${line}" | cut -d: -f2-)
                            if echo "${content}" | grep -qiE 'FROM.*:(edge|latest)' && \
                               ! echo "${content}" | grep -q '@sha256:'; then
                                if ! echo "${content}" | grep -q '\${BASE_APP_IMAGE}'; then
                                    log_error "Floating ref in ${file}:${linenum} - missing digest pin"
                                    ((found_violations++)) || true
                                fi
                            fi
                        fi
                    done < <(grep -n 'FROM' "${file}" 2>/dev/null || true)
                fi
            done < <(find "${imgdir}/build" -name "Dockerfile*" -o -name "*.dockerfile" 2>/dev/null || true)
        fi
    done < <(get_image_dirs)

    # Scan pins.env files in images/*/build/
    while IFS= read -r pins_env; do
        if [[ -f "${pins_env}" ]]; then
            if grep -q 'BASE_APP_IMAGE=' "${pins_env}"; then
                local base_image
                base_image=$(grep 'BASE_APP_IMAGE=' "${pins_env}" | head -1 | cut -d= -f2-)
                if [[ "${base_image}" == *":edge"* ]] && [[ "${base_image}" != *"@sha256:"* ]]; then
                    log_error "BASE_APP_IMAGE in ${pins_env} uses floating ref without digest: ${base_image}"
                    ((found_violations++)) || true
                fi
            fi
        fi
    done < <(find "${PROJECT_ROOT}/images" -path "*/build/pins.env" 2>/dev/null || true)

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "All image references are properly pinned"
    fi
}

check_shared_base_usage() {
    log_info "Checking shared base image usage..."
    local found_violations=0
    local zero_digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"

    while IFS= read -r imgdir; do
        local name dockerfile pins_env base_image from_lines
        name=$(basename "${imgdir}")
        [[ "${name}" == "base" ]] && continue

        dockerfile="${imgdir}/build/Dockerfile"
        pins_env="${imgdir}/build/pins.env"

        if [[ ! -f "${dockerfile}" ]]; then
            log_error "Missing Dockerfile for ${name}: ${dockerfile}"
            ((found_violations++)) || true
            continue
        fi

        if [[ ! -f "${pins_env}" ]]; then
            log_error "Missing pins.env for ${name}: ${pins_env}"
            ((found_violations++)) || true
            continue
        fi

        if ! grep -q '^ARG BASE_APP_IMAGE' "${dockerfile}"; then
            log_error "${dockerfile} must declare ARG BASE_APP_IMAGE"
            ((found_violations++)) || true
        fi

        if ! grep -qE '^FROM[[:space:]]+\$\{BASE_APP_IMAGE\}([[:space:]]|$)' "${dockerfile}"; then
            log_error "${dockerfile} must use FROM \${BASE_APP_IMAGE}"
            ((found_violations++)) || true
        fi

        from_lines=$(grep -nE '^FROM[[:space:]]+' "${dockerfile}" || true)
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            if ! echo "${line}" | grep -qE '^([0-9]+:)?FROM[[:space:]]+\$\{BASE_APP_IMAGE\}([[:space:]]|$)'; then
                log_error "App Dockerfile may only use the shared base in ${dockerfile}:${line}"
                ((found_violations++)) || true
            fi
        done <<< "${from_lines}"

        base_image=$(grep '^BASE_APP_IMAGE=' "${pins_env}" | head -1 | cut -d= -f2- || true)
        if [[ -z "${base_image}" ]]; then
            log_error "${pins_env} must declare BASE_APP_IMAGE"
            ((found_violations++)) || true
        elif ! [[ "${base_image}" =~ ^ghcr\.io/[^/]+/gow-collection/base:edge@sha256:[0-9a-f]{64}$ ]]; then
            log_error "BASE_APP_IMAGE in ${pins_env} must pin ghcr.io/<owner>/gow-collection/base:edge by sha256 digest: ${base_image}"
            ((found_violations++)) || true
        elif [[ "${base_image}" == *"${zero_digest}" ]]; then
            log_error "BASE_APP_IMAGE in ${pins_env} still uses placeholder digest"
            ((found_violations++)) || true
        fi
    done < <(get_image_dirs)

    while IFS= read -r match; do
        [[ -z "${match}" ]] && continue
        log_error "Legacy base image reference found: ${match}"
        ((found_violations++)) || true
    done < <(cd "${PROJECT_ROOT}" && grep -RIn 'ghcr.io/games-on-whales/base-app' \
        --include='Dockerfile*' --include='pins.env' --include='*.md' \
        images AGENTS.md CONTRIBUTING.md README.md 2>/dev/null || true)

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "All app images use the shared base image contract"
    fi
}

check_unverified_downloads() {
    log_info "Checking for unverified downloads..."
    local found_violations=0

    # Scan all Dockerfiles in the repo for curl/wget without checksums
    while IFS= read -r file; do
        if [[ -f "${file}" ]]; then
            # Check for curl without sha256sum verification
            while IFS= read -r line; do
                if [[ -n "${line}" ]]; then
                    local linenum content
                    linenum=$(echo "${line}" | cut -d: -f1)
                    content=$(echo "${line}" | cut -d: -f2-)
                    # Flag curl/wget downloads that don't have subsequent sha256 verification
                    if echo "${content}" | grep -qE '(curl|wget).*-O|>(\s|$)'; then
                        # Check if there's no checksum verification on same line or context
                        if ! echo "${content}" | grep -qiE 'sha256|checksum|verify'; then
                            log_warn "Potential unverified download in ${file}:${linenum} - ensure checksum verification"
                            ((found_violations++)) || true
                        fi
                    fi
                fi
            done < <(grep -n -E '(curl|wget)' "${file}" 2>/dev/null || true)
        fi
    done < <(find "${PROJECT_ROOT}" -name "Dockerfile*" -o -name "*.dockerfile" 2>/dev/null | grep -v '.git' || true)

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "No unverified downloads detected"
    fi
}

check_secrets() {
    log_info "Checking for potential secrets..."
    local found_violations=0

    local secret_patterns=(
        "password\s*=\s*['\"][^'\"]+['\"]"
        "api_key\s*=\s*['\"][^'\"]+['\"]"
        "secret\s*=\s*['\"][^'\"]+['\"]"
        "token\s*=\s*['\"][^'\"]+['\"]"
        "private_key\s*=\s*['\"][^'\"]+['\"]"
        "-----BEGIN.*PRIVATE KEY-----"
        "aws_access_key_id\s*=\s*['\"][^'\"]+['\"]"
        "aws_secret_access_key\s*=\s*['\"][^'\"]+['\"]"
    )

    local exclude_patterns=(
        ".git/"
        "test-results/"
        "*.log"
    )

    for pattern in "${secret_patterns[@]}"; do
        while IFS= read -r match; do
            if [[ -n "${match}" ]]; then
                log_error "Potential secret found: ${match}"
                ((found_violations++)) || true
            fi
        done < <(cd "${PROJECT_ROOT}" && grep -riE "${pattern}" \
            --include="*.sh" --include="*.py" --include="*.js" --include="*.ts" \
            --include="*.env" --include="*.yaml" --include="*.yml" \
            --include="*.json" --include="*.cfg" --include="*.conf" \
            --exclude-dir=".git" --exclude-dir="test-results" \
            . 2>/dev/null || true)
    done

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "No secrets detected"
    fi
}

# Main execution
log_info "Starting policy check..."
log_info "Project root: ${PROJECT_ROOT}"
if [[ -n "${IMAGE_DIR}" ]]; then
    log_info "Scanning image directory: ${IMAGE_DIR}"
else
    log_info "Scanning all image directories"
fi
echo "" >> "${RESULTS_FILE}"

check_floating_refs
check_shared_base_usage
check_unverified_downloads
check_secrets

echo ""
log_info "Policy check complete"
log_info "Errors: ${ERRORS}, Warnings: ${WARNINGS}"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    log_error "Policy check failed with ${ERRORS} error(s)"
    exit 1
fi

if [[ "${STRICT_MODE}" == "--strict" ]] && [[ ${WARNINGS} -gt 0 ]]; then
    log_error "Policy check failed with ${WARNINGS} warning(s) in strict mode"
    exit 1
fi

if [[ ${WARNINGS} -gt 0 ]]; then
    log_warn "Policy check passed with ${WARNINGS} warning(s)"
fi

log_pass "All policy checks passed"
exit 0
