#!/bin/bash
# https://github.com/kxr/ocp4_setup_upi_kvm

set -e
export START_TS=$(date +%s)
export SINV="${0} ${@}"
export SDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export COLS="$(stty size | awk '{print $2}')"

# Utility function err,ok,download etc.
source ${SDIR}/.install_scripts/utils.sh

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

# Process Arguments
source ${SDIR}/.defaults.sh
source ${SDIR}/.install_scripts/process_args.sh ${@}

# Destroy
if [ "${DESTROY}" == "yes" ]; then
    source ${SDIR}/.install_scripts/destroy.sh
    exit 0
fi

# Dependencies & Sanity checks
source ${SDIR}/.install_scripts/sanity_check.sh

# Libvirt Network
source ${SDIR}/.install_scripts/libvirt_network.sh

# DNS Check
source ${SDIR}/.install_scripts/dns_check.sh

# Version check
source ${SDIR}/.install_scripts/version_check.sh

# Download & Prepare
source ${SDIR}/.install_scripts/download_prepare.sh

# Create LB VM
source ${SDIR}/.install_scripts/create_lb.sh

# Create Cluster Nodes
source ${SDIR}/.install_scripts/create_nodes.sh

# OpenShift Bootstraping
source ${SDIR}/.install_scripts/bootstrap.sh

# OpenShift ClusterVersion
source ${SDIR}/.install_scripts/clusterversion.sh

# Generate env file and copy post scripts
source ${SDIR}/.install_scripts/post.sh

