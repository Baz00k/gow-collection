#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_DIR=""
for arg in "$@"; do
    if [[ "${arg}" == "--strict" ]]; then
        continue
    elif [[ -z "${IMAGE_DIR}" ]] && [[ "${arg}" != -* ]]; then
        IMAGE_DIR="${arg}"
    fi
done

RESULTS_DIR="${RESULTS_DIR:-${PROJECT_ROOT}/test-results/evidence}"
RESULTS_FILE="${RESULTS_DIR}/policy-check.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

mkdir -p "${RESULTS_DIR}"
: > "${RESULTS_FILE}"

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; echo "[INFO] $*" >> "${RESULTS_FILE}"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; echo "[PASS] $*" >> "${RESULTS_FILE}"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; echo "[ERROR] $*" >> "${RESULTS_FILE}"; ((ERRORS++)) || true; }

get_image_dirs() {
    if [[ -n "${IMAGE_DIR}" ]]; then
        if [[ -d "${IMAGE_DIR}" ]]; then
            echo "${IMAGE_DIR}"
        else
            log_error "Image directory not found: ${IMAGE_DIR}"
            return 1
        fi
    else
        find "${PROJECT_ROOT}/images" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true
    fi
}

check_base_pin() {
    if [[ -n "${IMAGE_DIR}" && "$(basename "${IMAGE_DIR}")" != "base" ]]; then
        return
    fi

    log_info "Checking base image pin..."

    local dockerfile="${PROJECT_ROOT}/images/base/build/Dockerfile"
    local pins_env="${PROJECT_ROOT}/images/base/build/pins.env"
    local base_image base_digest

    if [[ ! -f "${dockerfile}" || ! -f "${pins_env}" ]]; then
        log_error "Base image must have build/Dockerfile and build/pins.env"
        return
    fi

    base_image=$(grep '^BASE_IMAGE=' "${pins_env}" | head -1 | cut -d= -f2- || true)
    base_digest=$(grep '^BASE_IMAGE_DIGEST=' "${pins_env}" | head -1 | cut -d= -f2- || true)

    if [[ -z "${base_image}" || -z "${base_digest}" ]]; then
        log_error "${pins_env} must declare BASE_IMAGE and BASE_IMAGE_DIGEST"
    elif ! [[ "${base_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        log_error "BASE_IMAGE_DIGEST must be a sha256 digest: ${base_digest}"
    elif ! grep -qE '^FROM[[:space:]]+\$\{BASE_IMAGE\}@\$\{BASE_IMAGE_DIGEST\}' "${dockerfile}"; then
        log_error "${dockerfile} must use FROM \${BASE_IMAGE}@\${BASE_IMAGE_DIGEST}"
    else
        log_pass "Base image is pinned by digest"
    fi
}

check_app_base_contract() {
    if [[ -n "${IMAGE_DIR}" && "$(basename "${IMAGE_DIR}")" == "base" ]]; then
        return
    fi

    log_info "Checking app base image contract..."

    local found_violations=0
    local zero_digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"

    while IFS= read -r imgdir; do
        local name dockerfile pins_env base_image from_count
        name=$(basename "${imgdir}")
        [[ "${name}" == "base" ]] && continue

        dockerfile="${imgdir}/build/Dockerfile"
        pins_env="${imgdir}/build/pins.env"

        if [[ ! -f "${dockerfile}" || ! -f "${pins_env}" ]]; then
            log_error "${name} must have build/Dockerfile and build/pins.env"
            ((found_violations++)) || true
            continue
        fi

        if ! grep -q '^ARG BASE_APP_IMAGE' "${dockerfile}"; then
            log_error "${dockerfile} must declare ARG BASE_APP_IMAGE"
            ((found_violations++)) || true
        fi

        from_count=$(grep -cE '^FROM[[:space:]]+' "${dockerfile}" || true)
        if [[ "${from_count}" -ne 1 ]] || ! grep -qE '^FROM[[:space:]]+\$\{BASE_APP_IMAGE\}([[:space:]]|$)' "${dockerfile}"; then
            log_error "${dockerfile} must have exactly one FROM \${BASE_APP_IMAGE}"
            ((found_violations++)) || true
        fi

        base_image=$(grep '^BASE_APP_IMAGE=' "${pins_env}" | head -1 | cut -d= -f2- || true)
        if ! [[ "${base_image}" =~ ^ghcr\.io/[^/]+/gow-collection/base:edge@sha256:[0-9a-f]{64}$ ]]; then
            log_error "BASE_APP_IMAGE in ${pins_env} must pin ghcr.io/<owner>/gow-collection/base:edge by sha256 digest"
            ((found_violations++)) || true
        elif [[ "${base_image}" == *"${zero_digest}" ]]; then
            log_error "BASE_APP_IMAGE in ${pins_env} still uses placeholder digest"
            ((found_violations++)) || true
        fi
    done < <(get_image_dirs)

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "App images use the shared pinned base"
    fi
}

check_download_verification() {
    log_info "Checking Dockerfile download verification..."

    local found_violations=0

    while IFS= read -r dockerfile; do
        if grep -qE '\b(curl|wget)\b' "${dockerfile}" && ! grep -qE 'sha256sum[[:space:]]+-c|sha256sum[[:space:]]+--check' "${dockerfile}"; then
            log_error "${dockerfile} downloads files but does not verify them with sha256sum -c"
            ((found_violations++)) || true
        fi
    done < <(while IFS= read -r imgdir; do
        if [[ -f "${imgdir}/build/Dockerfile" ]]; then
            echo "${imgdir}/build/Dockerfile"
        fi
    done < <(get_image_dirs))

    if [[ ${found_violations} -eq 0 ]]; then
        log_pass "Dockerfile downloads are verified"
    fi
}

log_info "Starting policy check..."
if [[ -n "${IMAGE_DIR}" ]]; then
    log_info "Scanning image directory: ${IMAGE_DIR}"
else
    log_info "Scanning all image directories"
fi
echo "" >> "${RESULTS_FILE}"

check_base_pin
check_app_base_contract
check_download_verification

echo ""
log_info "Policy check complete"
log_info "Errors: ${ERRORS}"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    exit 1
fi

log_pass "All policy checks passed"
exit 0
