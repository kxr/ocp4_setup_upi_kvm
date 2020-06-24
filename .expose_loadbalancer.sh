#!/bin/bash
# https://github.com/kxr/ocp4_setup_upi_kvm

###############################################################################
# .expose_loadbalancer.sh
# This will expose the OpenShift cluster load balancer via firewall port
# forward rules. Before you can run this script, you must have already
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

# Process Arguments
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -c|--cluster-name)
    CLUSTER_NAME="$2"
    shift
    shift
    ;;
    -s|--setup-dir)
    SETUP_DIR="$2"
    shift
    shift
    ;;
    -h|--help)
    SHOW_HELP="yes"
    shift
    ;;
    *)
    echo "ERROR: Invalid argument $key"
    exit 1
    ;;
esac
done

# Default Values
test -z "$CLUSTER_NAME" && CLUSTER_NAME="ocp4"
test -z "$SETUP_DIR" && SETUP_DIR="/root/ocp4_setup_${CLUSTER_NAME}"

if [ "$SHOW_HELP" == "yes" ]; then
echo
echo "Usage: ${0} [OPTIONS]"
echo
cat << EOF | column -L -t -s '|' -N OPTION,DESCRIPTION -W DESCRIPTION

-c, --cluster-name NAME|OpenShift 4 cluster name
|Default: ocp4

-s, --setup-dir DIR|The location where the install script kept all files related to the installation
|Default: /root/ocp4_setup_{CLUSTER_NAME}

EOF
exit
fi

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

# Check that we have the necessary firewall utility
test "$(which firewall-cmd)" || err "You do not have firewall-cmd in your PATH"

echo 
echo "###################################"
echo "### DETERMINE LOAD BALANCER IP  ###"
echo "###################################"
echo

envfile="${SETUP_DIR}/env"
test -f "$envfile" || err "Missing env file [$envfile] - make sure you have already installed the OpenShift cluster prior to running this script"
source $envfile || err "Failed to source the env file [${envfile}]"
test ! -z "$LBIP" || err "Missing LBIP in env file [$envfile] - make sure you have successfully installed the OpenShift cluster prior to running this script"

echo "Your OpenShift Cluster Load Balancer IP is: $LBIP"

echo 
echo "#################################"
echo "### CREATE PORT FORWARD RULES ###"
echo "#################################"
echo

test ! -z "$VIR_NET" || err "Missing VIR_NET in env file [$envfile] - make sure you have successfully installed the OpenShift cluster prior to running this script"

firewall-cmd --add-forward-port=port=443:proto=tcp:toaddr=${LBIP}:toport=443 || err "Failed to forward port 443 to [${LBIP}:443]"
firewall-cmd --add-forward-port=port=6443:proto=tcp:toaddr=${LBIP}:toport=6443 || err "Failed to forward port 6443 to [${LBIP}:6443]"
firewall-cmd --add-forward-port=port=80:proto=tcp:toaddr=${LBIP}:toport=80 || err "Failed to forward port 80 to [${LBIP}:80]"
firewall-cmd --direct --passthrough ipv4 -I FORWARD -i ${VIR_NET} -j ACCEPT || err "Failed to set up direct passthrough from [${VIR_NET}]"
firewall-cmd --direct --passthrough ipv4 -I FORWARD -o ${VIR_NET} -j ACCEPT || err "Failed to set up direct passthrough to [${VIR_NET}]"

echo 
echo "###############################################"
echo "### PORT FORWARD RULES CREATED SUCCESSFULLY ###"
echo "###############################################"
echo

echo "Port forward rules have been created."
echo "The following hosts need to be defined in DNS so they can be resolved by your clients:"
echo "  console-openshift-console.apps.${CLUSTER_NAME}.local"
echo "  api.${CLUSTER_NAME}.local"
echo "  oauth-openshift.apps.${CLUSTER_NAME}.local"

exit 0
