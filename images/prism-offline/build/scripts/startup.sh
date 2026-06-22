#!/bin/bash -e

source /opt/gow/bash-lib/utils.sh

PrismLauncher=prismlauncher

gow_log "[start] Starting PrismLauncher"

source /opt/gow/launch-comp.sh
launcher "${PrismLauncher}"
