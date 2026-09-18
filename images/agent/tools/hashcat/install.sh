#!/bin/bash
# tools/hashcat/install.sh — install and verification for hashcat.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# bookworm carries 6.2.6; upstream 7.x moves faster than is worth
# re-implementing as a source build here. PoCL supplies the OpenCL ICD —
# hashcat aborts with no ICD even for pure CPU work.
apt_install hashcat ocl-icd-libopencl1 pocl-opencl-icd

verify_output '6.2.6' hashcat --version
