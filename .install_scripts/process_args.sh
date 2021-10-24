#!/bin/bash

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -O|--ocp-version)
    export OCP_VERSION="$2"
    shift
    shift
    ;;
    -R|--rhcos-version)
    export RHCOS_VERSION="$2"
    shift
    shift
    ;;
    -m|--masters)
    test "$2" -gt "0" &>/dev/null || err "Invalid masters: $N_MAST"
    export N_MAST="$2"
    shift
    shift
    ;;
    -w|--workers)
    test "$2" -ge "0" &> /dev/null || err "Invalid workers: $N_WORK"
    export N_WORK="$2"
    shift
    shift
    ;;
    -p|--pull-secret)
    export PULL_SEC_F="$2"
    shift
    shift
    ;;
    -n|--libvirt-network)
    export VIR_NET="$2"
    shift
    shift
    ;;
    -N|--libvirt-oct)
    test "$2" -gt "0" -a "$2" -lt "255" || err "Invalid subnet octet $VIR_NET_OCT"
    export VIR_NET_OCT="$2"
    shift
    shift
    ;;
    -c|--cluster-name)
    export CLUSTER_NAME="$2"
    shift
    shift
    ;;
    -d|--cluster-domain)
    export BASE_DOM="$2"
    shift
    shift
    ;;
    -v|--vm-dir)
    export VM_DIR="$2"
    shift
    shift
    ;;
    -z|--dns-dir)
    export DNS_DIR="$2"
    shift
    shift
    ;;
    -s|--setup-dir)
    export SETUP_DIR="$2"
    shift
    shift
    ;;
    -x|--cache-dir)
    export CACHE_DIR="$2"
    shift
    shift
    ;;
    --master-cpu)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --master-cpu"
    export MAS_CPU="$2"
    shift
    shift
    ;;
    --master-mem)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --master-mem"
    export MAS_MEM="$2"
    shift
    shift
    ;;
    --worker-cpu)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --worker-cpu"
    export WOR_CPU="$2"
    shift
    shift
    ;;
    --worker-mem)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --worker-mem"
    export WOR_MEM="$2"
    shift
    shift
    ;;
    --bootstrap-cpu)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --bootstrap-cpu"
    export BTS_CPU="$2"
    shift
    shift
    ;;
    --bootstrap-mem)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --bootstrap-mem"
    export BTS_MEM="$2"
    shift
    shift
    ;;
    --lb-cpu)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --lb-cpu"
    export LB_CPU="$2"
    shift
    shift
    ;;
    --lb-mem)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --lb-mem"
    export LB_MEM="$2"
    shift
    shift
    ;;
    --ssh-pub-key-file)
    test -f "$2" || err "SSH public key file not found: ${2}"
    export SSH_PUB_KEY_FILE="$2"
    shift
    shift
    ;;
    -X|--fresh-download)
    export FRESH_DOWN="yes"
    shift
    ;;
    -k|--keep-bootstrap)
    export KEEP_BS="yes"
    shift
    ;;
    --autostart-vms)
    export AUTOSTART_VMS="yes"
    shift
    ;;
    --no-autostart-vms)
    export AUTOSTART_VMS="no"
    shift
    ;;
    --destroy)
    export DESTROY="yes"
    shift
    ;;
    -y|--yes)
    export YES="yes"
    shift
    ;;
    -h|--help)
    source ${SDIR}/.install_scripts/show_help.sh
    exit 0
    shift
    ;;
    *)
    echo "ERROR: Invalid argument $key"
    exit 1
    ;;
esac
done

test -z "${SETUP_DIR}" && export SETUP_DIR="/root/ocp4_cluster_${CLUSTER_NAME}" || true

test -n "$VIR_NET" -a -n "$VIR_NET_OCT" && err "Specify either -n or -N" || true
test -z "$VIR_NET" -a -z "$VIR_NET_OCT" && export VIR_NET="${DEF_LIBVIRT_NET}" || true
