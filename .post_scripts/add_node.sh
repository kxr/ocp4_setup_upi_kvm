#!/bin/bash
# https://github.com/kxr/ocp4_setup_upi_kvm
set -e

show_help() {
echo
echo "Usage: ${0} [OPTIONS]"
echo
cat << EOF | column -L -t -s '|' -N OPTION,DESCRIPTION -W DESCRIPTION

--name NAME|The node name without the domain.
|For example: If you specify storage-1, and your cluster name is "ocp4" and base domain is "local", the new node would be "storage-1.ocp4.local"
|Default: <not set> <REQUIRED>

-c, --cpu N|Number of CPUs to be attached to this node's VM.
|Default: 2

-m, --memory SIZE|Amount of Memory to be attached to this node's VM. Size in MB.
|Default: 4096

-a, --add-disk SIZE|You can add additional disks to this node. Size in GB.
|This option can be specified multiple times. Disks are added in order for example if you specify "--add-disk 10 --add-disk 100", two disks will be added (on top of the OS disk vda) first of 10GB (/dev/vdb) and second disk of 100GB (/dev/vdc)
|Default: <not set>

-v, --vm-dir|The location where you want to store the VM Disks
|By default the location used by the cluster VMs will be used.

-N, --libvirt-oct OCTET|You can specify a 192.168.{OCTET}.0 subnet octet and this script will create a new libvirt network for this node.
|The network will be named ocp-{OCTET}. If the libvirt network ocp-{OCTET} already exists, it will be used.
|This can be useful if you want to add a node in different network than the one used by the cluster.
|Default: <not set>

-n, --libvirt-network NETWORK|The libvirt network to use. Select this option if you want to use an existing libvirt network.
|By default the existing libvirt network used by the cluster will be used.

EOF

}

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
    --name)
    NODE="$2"
    shift
    shift
    ;;
    -c|--cpu)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --cpu"
    CPU="$2"
    shift
    shift
    ;;
    -m|--memory)
    test "$2" -gt "0" &>/dev/null || err "Invalid value $2 for --memory"
    MEM="$2"
    shift
    shift
    ;;
    -a|--add-disk)
    test "$2" -gt "0" &>/dev/null || err "Invalid disk size. Enter size in GB";
    ADD_DISK="${ADD_DISK} --disk ${VM_DIR}/${CLUSTER_NAME}-${NODE}-${2}GB-$(shuf -zer -n 5 {a..z}|tr -d '\0').qcow2,size=${2}"
    shift
    shift
    ;;
    -N|--libvirt-oct)
    VIR_NET_OCT="$2"
    test "$VIR_NET_OCT" -gt "0" -a "$VIR_NET_OCT" -lt "255" || err "Invalid subnet octet $VIR_NET_OCT"
    shift
    shift
    ;;
    -n|--libvirt-network)
    VIR_NET="$2"
    shift
    shift
    ;;
    -v|--vm-dir)
    VM_DIR="$2"
    shift
    shift
    ;;
    -h|--help)
    show_help
    exit
    ;;
    *)
    echo "ERROR: Invalid argument $key"
    exit 1
esac
done

test -z "$NODE" && err "Please specify the node name using --name <node-name>" \
                       "see --help for more details"
test -z "$CPU" && CPU="2"
test -z "$MEM" && MEM="4096"

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

echo -n "====> Checking if libvirt is running: "
    systemctl -q is-active libvirtd || err "libvirtd is not running"; ok

echo -n "====> Checking libvirt network: "
if [ -n "$VIR_NET_OCT" ]; then
    virsh net-uuid "ocp-${VIR_NET_OCT}" &> /dev/null
    if [ "$?" -eq "0" ]; then
        VIR_NET="ocp-${VIR_NET_OCT}"
        ok "re-using ocp-${VIR_NET_OCT}"
        unset VIR_NET_OCT
    else
        ok "will create ocp-${VIR_NET_OCT} (192.168.${VIR_NET_OCT}.0/24)"
    fi
elif [ -n "$VIR_NET" ]; then
    virsh net-uuid "${VIR_NET}" &> /dev/null || \
        err "${VIR_NET} doesn't exist"
    ok "using $VIR_NET"
else
    err "Sorry, unhandled situation. Exiting"
fi

if [ -n "$VIR_NET_OCT" ]; then
    echo -n "====> Creating libvirt network ocp-${VIR_NET_OCT} "
    /usr/bin/cp /usr/share/libvirt/networks/default.xml /tmp/new-net.xml > /dev/null || err "Network creation failed"
    sed -i "s/default/ocp-${VIR_NET_OCT}/" /tmp/new-net.xml
    sed -i "s/virbr0/ocp-${VIR_NET_OCT}/" /tmp/new-net.xml
    sed -i "s/122/${VIR_NET_OCT}/g" /tmp/new-net.xml
    virsh net-define /tmp/new-net.xml > /dev/null || err "virsh net-define failed"
    virsh net-autostart ocp-${VIR_NET_OCT} > /dev/null || err "virsh net-autostart failed"
    virsh net-start ocp-${VIR_NET_OCT} > /dev/null || err "virsh net-start failed"
    systemctl restart libvirtd > /dev/null || err "systemctl restart libvirtd failed"
    echo "ocp-${VIR_NET_OCT} created"
    VIR_NET="ocp-${VIR_NET_OCT}"
fi

cd ${SETUP_DIR}


if [ -n "$RHCOS_LIVE" ]; then
    RHCOS_I_ARG="coreos.live.rootfs_url"
else
    RHCOS_I_ARG="coreos.inst.image_url"
fi

echo -n "====> Creating ${NODE} VM: "
  virt-install --name ${CLUSTER_NAME}-${NODE} \
  --disk "${VM_DIR}/${CLUSTER_NAME}-${NODE}.qcow2,size=50" ${ADD_DISK} \
  --ram ${MEM} --cpu host --vcpus ${CPU} \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda ${RHCOS_I_ARG}=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/worker.ign" > /dev/null || err "Creating ${NODE} vm failed "; ok


echo "====> Waiting for RHCOS Installation to finish: "
while rvms=$(virsh list --name | grep "${CLUSTER_NAME}-${NODE}" 2> /dev/null); do
    sleep 15
    echo "  --> VMs with pending installation: $(echo "$rvms" | tr '\n' ' ')"
done

echo -n "====> Starting ${NODE} VM: "
virsh start ${CLUSTER_NAME}-${NODE} > /dev/null || err "virsh start ${CLUSTER_NAME}-worker-${i} failed"; ok


echo -n "====> Waiting for ${NODE} to obtain IP address: "
while true
do
    sleep 5
    IP=$(virsh domifaddr "${CLUSTER_NAME}-${NODE}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
    test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
done
MAC=$(virsh domifaddr "${CLUSTER_NAME}-${NODE}" | grep ipv4 | head -n1 | awk '{print $2}')

echo -n "  ==> Adding DHCP reservation: "
virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config > /dev/null || \
err "Adding DHCP reservation failed"; ok

echo -n "  ==> Adding /etc/hosts entry: "
echo "$IP ${NODE}.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts || err "failed"; ok

echo -n "====> Resstarting libvirt and dnsmasq: "
systemctl restart libvirtd || err "systemctl restart libvirtd failed"
systemctl $DNS_CMD $DNS_SVC || err "systemctl $DNS_CMD $DNS_SVC failed"; ok

echo
echo
echo "NOTE: Please check the cluster for CSRs and approve them"
echo
echo "      # oc get csr"
echo "      # oc adm certificate approve <csr>"
