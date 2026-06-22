#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

if [ "${PUID}" = "0" ]; then
    log_warn "PUID=0, skipping runtime user device groups"
    return 0 2>/dev/null || exit 0
fi

log_info "Configuring device group access"

declare -A dev_groups=()
for dev_glob in /dev/dri/* /dev/nvidia* /dev/input/* /dev/hidraw* /dev/uinput; do
    # shellcheck disable=SC2086
    for dev in $dev_glob; do
        if [ -e "${dev}" ]; then
            group_name=$(stat -c "%G" "${dev}")
            group_id=$(stat -c "%g" "${dev}")
            if [ "${group_name}" = "UNKNOWN" ]; then
                group_name="gow-gid-${group_id}"
                if ! getent group "${group_name}" > /dev/null 2>&1; then
                    groupadd -g "${group_id}" "${group_name}"
                fi
            fi
            dev_groups[${group_name}]=1

            if [ "$(stat -c "%a" "${dev}" | cut -c2)" -lt 6 ]; then
                chmod g+rw "${dev}"
            fi
        fi
    done
done

if [ "${#dev_groups[@]}" -gt 0 ]; then
    groups_csv=$(IFS=,; echo "${!dev_groups[*]}")
    log_info "Adding user '${UNAME}' to device groups: ${groups_csv}"
    usermod -aG "${groups_csv}" "${UNAME}"
else
    log_info "No matching device groups found"
fi
