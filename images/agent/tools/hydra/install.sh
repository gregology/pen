#!/bin/bash
# tools/hydra/install.sh — install and verification for hydra.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install hydra

# `hydra -h` prints its banner and then exits 255 — hydra's own choice, not a
# failure, but `set -o pipefail` propagates it through the pipeline and `set -e`
# would abort on it. Suspend both, then gate on the grep: a missing banner must
# still fail the build, so acceptance is the grep's exit status, not the
# pipeline's. (Piping straight into `head` was worse — SIGPIPE as well.)
set +e
hydra -h 2>&1 | grep -m1 'Hydra v'
HYDRA_BANNER=$?
set -e
if [ "$HYDRA_BANNER" -ne 0 ]; then
    echo "hydra did not print its banner" >&2
    exit 1
fi
