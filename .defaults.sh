#!/bin/bash

# These are the default values used by the script i.e,
# If an option/switch is not provided, these are the values that the script will use.
# These values can be overridden by providing corresponding switches/options.
# You can change these default values to the ones appropriate to your environment,
# to avoid passing them every time.

# -O, --ocp-version VERSION
export OCP_VERSION="stable"

# -R, --rhcos-version VERSION
export RHCOS_VERSION=""

# -m, --masters N
export N_MAST="3"

# -w, --workers N
export N_WORK="2"

# --master-cpu N(vCPU)
export MAS_CPU="4"

# --master-mem SIZE(MB)
export MAS_MEM="16000"

# --worker-cpu N(vCPU)
export WOR_CPU="2"

# --worker-mem SIZE(MB)
export WOR_MEM="8000"

# --bootstrap-cpu N(vCPU)
export BTS_CPU="4"

# --bootstrap-mem SIZE(MB)
export BTS_MEM="16000"

# --lb-cpu N(vCPU)
export LB_CPU="1"

# --lb-mem SIZE(MB)
export LB_MEM="1024"

# -n, --libvirt-network NETWORK
export DEF_LIBVIRT_NET="default"

# -N, --libvirt-oct OCTET
export VIR_NET_OCT=""

# -c, --cluster-name NAME
export CLUSTER_NAME="ocp4"

# -d, --cluster-domain DOMAIN
export BASE_DOM="local"

# -z, --dns-dir DIR
export DNS_DIR="/etc/NetworkManager/dnsmasq.d"

# -v, --vm-dir DIR
export VM_DIR="/var/lib/libvirt/images"

# -s, --setup-dir DIR
# By default set to /root/ocp4_cluster_$CLUSTER_NAME
export SETUP_DIR=""

# -x, --cache-dir DIR
export CACHE_DIR="/root/ocp4_downloads"

# -p, --pull-secret FILE
export PULL_SEC_F="/root/pull-secret"

# --ssh-pub-key-file
# By default a new ssh key pair is generated in $SETUP_DIR
export SSH_PUB_KEY_FILE=""


# Below are some "flags" which by default are set to "no"
# and can be overriden by their respective switches.
# If you set them to "yes" here, you won't need pass those
# switches everytime you run the script.

# --autostart-vms
export AUTOSTART_VMS="no"

# -k, --keep-bootstrap
export KEEP_BS="no"

# -X, --fresh-download
export FRESH_DOWN="no"

# --destroy
# Don't set this to yes
export DESTROY="no"

# -y, --yes
export YES="no"


export OCP_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
export RHCOS_MIRROR="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos"
export LB_IMG_URL="https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
