#!/bin/bash

cat <<EOF > env
# OCP4 Automated Install using https://github.com/kxr/ocp4_setup_upi_kvm
# Script location: ${SDIR}
# Script invoked with: ${SINV}
# OpenShift version: ${OCP_NORMALIZED_VER}
# Red Hat CoreOS version: ${RHCOS_NORMALIZED_VER}
#
# Script start time: $(date -d @${START_TS})
# Script end time:   $(date -d @${END_TS})
# Script finished in: ${TIME_TAKEN} minutes
#
# VARS:

export SDIR="${SDIR}"
export SETUP_DIR="${SETUP_DIR}"
export DNS_DIR="${DNS_DIR}"
export VM_DIR="${VM_DIR}"
export KUBECONFIG="${SETUP_DIR}/install_dir/auth/kubeconfig"

export CLUSTER_NAME="${CLUSTER_NAME}"
export BASE_DOM="${BASE_DOM}"

export LBIP="${LBIP}"
export WS_PORT="${WS_PORT}"
export IMAGE="${IMAGE}"
export RHCOS_LIVE="${RHCOS_LIVE}"

export VIR_NET="${VIR_NET}"
export DNS_CMD="${DNS_CMD}"
export DNS_SVC="${DNS_SVC}"

EOF

cp ${SDIR}/.post_scripts/*.sh ${SETUP_DIR}/

