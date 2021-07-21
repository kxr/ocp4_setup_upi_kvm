#!/bin/bash

echo 
echo "##################"
echo "####  DESTROY  ###"
echo "##################"
echo 

if [ -n "$VIR_NET_OCT" -a -z "$VIR_NET" ]; then
    VIR_NET="ocp-${VIR_NET_OCT}"
fi

for vm in $(virsh list --all --name | grep "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap"); do
    check_if_we_can_continue "Deleting VM $vm"
    MAC=$(virsh domiflist "$vm" | grep network | awk '{print $5}')
    DHCP_LEASE=$(virsh net-dumpxml ${VIR_NET} | grep '<host ' | grep "$MAC" | sed 's/^[ ]*//')
    echo -n "XXXX> Deleting DHCP reservation for VM $vm: "
        virsh net-update ${VIR_NET} delete ip-dhcp-host --xml "$DHCP_LEASE" --live --config &> /dev/null || \
            echo -n "dhcp reservation delete failed (ignoring) ... "
        ok
    echo -n "XXXX> Deleting VM $vm: "
        virsh destroy "$vm" &> /dev/null || echo -n "stopping vm failed (ignoring) ... "
        virsh undefine "$vm" --remove-all-storage &> /dev/null || echo -n "deleting vm failed (ignoring) ... "
        ok
done

if [ -n "$VIR_NET_OCT" ]; then
    virnet=$(virsh net-uuid "ocp-${VIR_NET_OCT}" 2> /dev/null || true)
    if [ -n "$virnet" ]; then
        check_if_we_can_continue "Deleting libvirt network ocp-${VIR_NET_OCT}"
        echo -n "XXXX> Deleting libvirt network ocp-${VIR_NET_OCT}: "
            virsh net-destroy "ocp-${VIR_NET_OCT}" > /dev/null ||  echo -n "virsh net-destroy ocp-${VIR_NET_OCT} failed (ignoring) ... "
            virsh net-undefine "ocp-${VIR_NET_OCT}" > /dev/null || echo -n "virsh net-undefine ocp-${VIR_NET_OCT} failed (ignoring) ... "
        ok
    fi
fi

if [ -d "${SETUP_DIR}" ]; then
    check_if_we_can_continue "Removing directory (rm -rf) $SETUP_DIR"
    echo -n "XXXX> Deleting (rm -rf) directory $SETUP_DIR: "
        rm -rf "$SETUP_DIR" || echo -n "Deleting directory failed (ignoring) ... "
    ok
fi

h_rec=$(cat /etc/hosts | grep -v "^#" | grep -q -s "${CLUSTER_NAME}\.${BASE_DOM}$" 2> /dev/null || true)
if [ -n "$h_rec" ]; then
    check_if_we_can_continue "Commenting entries in /etc/hosts for ${CLUSTER_NAME}.${BASE_DOM}"
    echo -n "XXXX> Commenting entries in /etc/hosts for ${CLUSTER_NAME}.${BASE_DOM}: "
        sed -i "s/\(.*\.${CLUSTER_NAME}\.${BASE_DOM}$\)/#\1/" "/etc/hosts" || echo -n "sed failed (ignoring) ... "
    ok
fi

if [ -f "${DNS_DIR}/${CLUSTER_NAME}.conf" ]; then
    check_if_we_can_continue "Removing file ${DNS_DIR}/${CLUSTER_NAME}.conf"
    echo -n "XXXX> Removing file ${DNS_DIR}/${CLUSTER_NAME}.conf: "
        rm -f "${DNS_DIR}/${CLUSTER_NAME}.conf" &> /dev/null || echo -n "removing file failed (ignoring) ... "
    ok
fi

if [ -f "/etc/hosts.${CLUSTER_NAME}" ]; then
    check_if_we_can_continue "Removing file /etc/hosts.${CLUSTER_NAME}"
    echo -n "XXXX> Removing file /etc/hosts.${CLUSTER_NAME}: "
        rm -f "/etc/hosts.${CLUSTER_NAME}" &> /dev/null || echo -n "removing file failed (ignoring) ... "
    ok
fi
