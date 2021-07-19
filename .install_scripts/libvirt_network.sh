#!/bin/bash

echo 
echo "#######################"
echo "### LIBVIRT NETWORK ###"
echo "#######################"
echo

echo -n "====> Checking libvirt network: "
if [ -n "$VIR_NET_OCT" ]; then
    virsh net-uuid "ocp-${VIR_NET_OCT}" &> /dev/null && \
        {   export VIR_NET="ocp-${VIR_NET_OCT}"
            ok "re-using ocp-${VIR_NET_OCT}"
            unset VIR_NET_OCT
        } || \
        {
            ok "will create ocp-${VIR_NET_OCT} (192.168.${VIR_NET_OCT}.0/24)"
        }
elif [ -n "$VIR_NET" ]; then
    virsh net-uuid "${VIR_NET}" &> /dev/null || \
        err "${VIR_NET} doesn't exist"
    ok "using $VIR_NET"
else
    err "Sorry, unhandled situation. Exiting"
fi


if [ -n "$VIR_NET_OCT" ]; then
    echo -n "====> Creating a new libvirt network ocp-${VIR_NET_OCT}: "
    test -f /usr/share/libvirt/networks/default.xml || err "/usr/share/libvirt/networks/default.xml not found"
    /usr/bin/cp /usr/share/libvirt/networks/default.xml /tmp/new-net.xml > /dev/null || err "Network creation failed"
    sed -i "s/default/ocp-${VIR_NET_OCT}/" /tmp/new-net.xml
    sed -i "s/virbr0/ocp-${VIR_NET_OCT}/" /tmp/new-net.xml
    sed -i "s/122/${VIR_NET_OCT}/g" /tmp/new-net.xml
    virsh net-define /tmp/new-net.xml > /dev/null || err "virsh net-define /tmp/new-net.xml failed"
    virsh net-autostart ocp-${VIR_NET_OCT} > /dev/null || err "virsh net-autostart ocp-${VIR_NET_OCT} failed"
    virsh net-start ocp-${VIR_NET_OCT} > /dev/null || err "virsh net-start ocp-${VIR_NET_OCT} failed"
    systemctl restart libvirtd > /dev/null || err "systemctl restart libvirtd failed"
    echo "ocp-${VIR_NET_OCT} created"
    export VIR_NET="ocp-${VIR_NET_OCT}"
fi


export LIBVIRT_BRIDGE=$(virsh net-info ${VIR_NET} | grep "^Bridge:" | awk '{print $2}')
export LIBVIRT_GWIP=$(ip -f inet addr show ${LIBVIRT_BRIDGE} | awk '/inet / {print $2}' | cut -d '/' -f1)
