#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam-os:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam-os}"
EVIDENCE_FILE="${EVIDENCE_DIR}/gaming-env.txt"

mkdir -p "${EVIDENCE_DIR}"
printf '=== Smoke Test: Gaming Session Environment ===\nImage: %s\n\n' "${IMAGE_NAME}" > "${EVIDENCE_FILE}"

# Each case sources the gaming env in a fresh shell against fake /dev/dri and
# /sys/class/drm trees, then prints the resulting dynamic VRS state.
# shellcheck disable=SC2016 # Expanded inside the container.
CASES_SCRIPT='
set -euo pipefail
root="$(mktemp -d)"

make_gpu() {
    local dir="$1" node="$2" driver="$3"
    mkdir -p "${dir}/dev" "${dir}/sys/${node}/device"
    touch "${dir}/dev/${node}"
    ln -s "../../../bus/pci/drivers/${driver}" "${dir}/sys/${node}/device/driver"
}

run_case() {
    local name="$1" gpu_dir="$2"
    shift 2
    (
        unset STEAM_USE_DYNAMIC_VRS RADV_FORCE_VRS_CONFIG_FILE VK_DRIVER_FILES VK_ICD_FILENAMES AMD_VULKAN_ICD
        for assignment in "$@"; do
            export "${assignment?}"
        done
        export DRI_DEVICE_DIR="${gpu_dir}/dev" SYSFS_DRM_DIR="${gpu_dir}/sys"
        source /opt/gow/steamos-gaming-env.sh
        steamos_export_gaming_env >/dev/null 2>&1
        # printenv is a child process, so like Steam it only sees exported values.
        vrs="$(printenv STEAM_USE_DYNAMIC_VRS || echo unset)"
        vrs_file="$(printenv RADV_FORCE_VRS_CONFIG_FILE)" && vrs_file="$(cat "${vrs_file}")" || vrs_file="none"
        echo "${name}: vrs=${vrs} file=${vrs_file}"
    )
}

make_gpu "${root}/amd" renderD128 amdgpu
make_gpu "${root}/mixed" renderD128 amdgpu
make_gpu "${root}/mixed" renderD129 nvidia
mkdir -p "${root}/none/dev" "${root}/none/sys"
printf "2x2\n" > "${root}/user-vrs"

run_case no-gpu "${root}/none"
run_case amd "${root}/amd"
run_case mixed "${root}/mixed"
run_case amd-other-icd "${root}/amd" VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json:/usr/share/vulkan/icd.d/nvidia_icd.json
run_case amd-amdvlk "${root}/amd" AMD_VULKAN_ICD=AMDVLK
run_case forced-on "${root}/none" STEAM_DYNAMIC_VRS=on
run_case forced-off "${root}/amd" STEAM_DYNAMIC_VRS=off
run_case user-values "${root}/amd" STEAM_USE_DYNAMIC_VRS=0 RADV_FORCE_VRS_CONFIG_FILE="${root}/user-vrs"
'

if ! OUTPUT="$(docker run --rm --entrypoint "" "${IMAGE_NAME}" bash -c "${CASES_SCRIPT}" 2>&1)"; then
    printf '%s\n' "${OUTPUT}" >> "${EVIDENCE_FILE}"
    echo "RESULT: FAILED (gaming env cases did not run)" >> "${EVIDENCE_FILE}"
    exit 1
fi
printf '%s\n' "${OUTPUT}" >> "${EVIDENCE_FILE}"

FAILED=0
for expected in \
    "no-gpu: vrs=unset file=none" \
    "amd: vrs=1 file=1x1" \
    "mixed: vrs=unset file=none" \
    "amd-other-icd: vrs=unset file=none" \
    "amd-amdvlk: vrs=unset file=none" \
    "forced-on: vrs=1 file=1x1" \
    "forced-off: vrs=unset file=none" \
    "user-values: vrs=0 file=2x2"; do
    if ! grep -qxF "${expected}" <<< "${OUTPUT}"; then
        echo "missing: ${expected}" >> "${EVIDENCE_FILE}"
        FAILED=1
    fi
done

if [[ ${FAILED} -ne 0 ]]; then
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    echo "[ERROR] gaming session environment cases failed; see ${EVIDENCE_FILE}" >&2
    exit 1
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "[INFO] Gaming session environment smoke test passed"
