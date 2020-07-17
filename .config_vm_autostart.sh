#!/bin/bash
# https://github.com/kxr/ocp4_setup_upi_kvm

###############################################################################
# .config_vm_autostart.sh
#
# This will configure the autostart flag on all VMs in the cluster.
# This allows you to enable all VMs to start automatically upon host restart.
# This script can be run at cluster install time by passing in the option
# "--autostart-cluster" to the ocp4-setup-upi-kvm.sh script.
# If the VMs are already configured to autostart but you do not want them to
# start at boot time, you can turn off that behavior via "--autostart false".
# Before you can run this script, you must have already
# successfully installed your OpenShift cluster via the
# ocp4-setup-upi-kvm.sh script.
###############################################################################

set -e

err() {
    echo; echo;
    echo -e "\e[97m\e[101m[ERROR]\e[0m ${1}"; shift; echo;
    while [[ $# -gt 0 ]]; do echo "    $1"; shift; done
    echo; exit 1;
}
ok() {
    test -z "$1" && echo "ok" || echo "$1"
}
SDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${SDIR}/env || err "${SDIR}/env not found."

# Process Arguments
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -a|--autostart)
    AUTOSTART="$2"
    test "$AUTOSTART" == "true" -o "$AUTOSTART" == "false" || err "Autostart flag must be true or false"
    shift
    shift
    ;;
    -h|--help)
    SHOW_HELP="yes"
    shift
    ;;
    -y|--yes)
    YES="yes"
    shift
    ;;
    *)
    echo "ERROR: Invalid argument $key"
    exit 1
    ;;
esac
done

if [ "$SHOW_HELP" == "yes" ]; then
echo
echo "Usage: ${0} [OPTIONS]"
echo
cat << EOF | column -L -t -s '|' -N OPTION,DESCRIPTION -W DESCRIPTION

-a, --autostart FLAG|Determines if you want the VMs to autostart on host reboot.
|Valid options are "true" and "false"
|<REQUIRED>

-y, --yes|Set this for the script to be non-interactive and continue with out asking for confirmation
|Default: <not set>

EOF
exit
fi

check_if_we_can_continue() {
    if [ "$YES" != "yes" ]; then
        echo;
        test -n "$1" && echo "[NOTE] $1"
        echo -n "Press enter to continue"; read x;
    fi
}

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

# Check if we have the --autostart set
test -n "$AUTOSTART" || \
    err "Please set the autostart flag using --autostart" \
        "Run:  '${0} --help' for details"

# Check if we have the required variables from env file
test -n "$CLUSTER_NAME" || \
    err "Unable to find existing cluster info"

if [ "$AUTOSTART" == "true" ]; then
    vms_to_configure="$(virsh list --all --name --no-autostart | grep "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" || true)"
    disable_opt=""
    msg="Will configure VMs to autostart at boot time"
elif [ "$AUTOSTART" == "false" ]; then
    vms_to_configure="$(virsh list --all --name --autostart | grep "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" || true)"
    disable_opt="--disable"
    msg="Will configure VMs to NOT autostart at boot time"
else
    err "Unknown autostart flag (must be true or false)"
fi

if [ -z "${vms_to_configure}" ]; then
    echo "No VMs to configure"
else
    echo ${msg} ":" $(echo -n ${vms_to_configure} | tr ' ' ',')
    check_if_we_can_continue

    for vm in ${vms_to_configure}
    do
        echo -n "Configuring VM: ${vm} ... "
        virsh autostart ${disable_opt} ${vm} > /dev/null || err "Failed to configure VM: ${vm}"; ok
    done
fi
exit 0
