#!/bin/bash

echo 
echo "############################################"
echo "#### CREATE BOOTSTRAPING RHCOS/OCP NODES ###"
echo "############################################"
echo 

if [ -n "$RHCOS_LIVE" ]; then
    RHCOS_I_ARG="coreos.live.rootfs_url"
else
    RHCOS_I_ARG="coreos.inst.image_url"
fi

echo -n "====> Creating Boostrap VM: "
virt-install --name ${CLUSTER_NAME}-bootstrap \
  --disk "${VM_DIR}/${CLUSTER_NAME}-bootstrap.qcow2,size=50" --ram ${BTS_MEM} --cpu host --vcpus ${BTS_CPU} \
  --os-type linux --os-variant rhel7.0 \
  --network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda ${RHCOS_I_ARG}=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/bootstrap.ign" > /dev/null || err "Creating boostrap vm failed"; ok

for i in $(seq 1 ${N_MAST})
do
echo -n "====> Creating Master-${i} VM: "
virt-install --name ${CLUSTER_NAME}-master-${i} \
--disk "${VM_DIR}/${CLUSTER_NAME}-master-${i}.qcow2,size=50" --ram ${MAS_MEM} --cpu host --vcpus ${MAS_CPU} \
--os-type linux --os-variant rhel7.0 \
--network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
--location rhcos-install/ \
--extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda ${RHCOS_I_ARG}=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/master.ign" > /dev/null || err "Creating master-${i} vm failed "; ok
done

for i in $(seq 1 ${N_WORK})
do
echo -n "====> Creating Worker-${i} VM: "
  virt-install --name ${CLUSTER_NAME}-worker-${i} \
  --disk "${VM_DIR}/${CLUSTER_NAME}-worker-${i}.qcow2,size=50" --ram ${WOR_MEM} --cpu host --vcpus ${WOR_CPU} \
  --os-type linux --os-variant rhel7.0 \
  --network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda ${RHCOS_I_ARG}=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/worker.ign" > /dev/null || err "Creating worker-${i} vm failed "; ok
done

echo "====> Waiting for RHCOS Installation to finish: "
while rvms=$(virsh list --name | grep "${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" 2> /dev/null); do
    sleep 15
    echo "  --> VMs with pending installation: $(echo "$rvms" | tr '\n' ' ')"
done

echo -n "====> Marking ${CLUSTER_NAME}.${BASE_DOM} as local in dnsmasq: "
echo "local=/${CLUSTER_NAME}.${BASE_DOM}/" >> ${DNS_DIR}/${CLUSTER_NAME}.conf || err "Updating ${DNS_DIR}/${CLUSTER_NAME}.conf failed"; ok

echo -n "====> Starting Bootstrap VM: "
virsh start ${CLUSTER_NAME}-bootstrap > /dev/null || err "virsh start ${CLUSTER_NAME}-bootstrap failed"; ok

for i in $(seq 1 ${N_MAST})
do
    echo -n "====> Starting Master-${i} VM: "
    virsh start ${CLUSTER_NAME}-master-${i} > /dev/null || err "virsh start ${CLUSTER_NAME}-master-${i} failed"; ok
done

for i in $(seq 1 ${N_WORK})
do
    echo -n "====> Starting Worker-${i} VMs: "
    virsh start ${CLUSTER_NAME}-worker-${i} > /dev/null || err "virsh start ${CLUSTER_NAME}-worker-${i} failed"; ok
done

echo -n "====> Waiting for Bootstrap to obtain IP address: "
while true; do
    sleep 5
    BSIP=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
    test "$?" -eq "0" -a -n "$BSIP"  && { echo "$BSIP"; break; }
done
MAC=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $2}')

echo -n "  ==> Adding DHCP reservation: "
virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$BSIP'/>" --live --config > /dev/null || \
    err "Adding DHCP reservation failed"; ok

echo -n "  ==> Adding hosts entry in /etc/hosts.${CLUSTER_NAME}: "
echo "$BSIP bootstrap.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts.${CLUSTER_NAME} || err "failed"; ok

for i in $(seq 1 ${N_MAST}); do
    echo -n "====> Waiting for Master-$i to obtain IP address: "
        while true
        do
            sleep 5
            IP=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
            test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
        done
        MAC=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $2}')

    echo -n "  ==> Adding DHCP reservation: "
    virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config > /dev/null || \
    err "Adding DHCP reservation failed"; ok

    echo -n "  ==> Adding hosts entry in /etc/hosts.${CLUSTER_NAME}: "
    echo "$IP master-${i}.${CLUSTER_NAME}.${BASE_DOM}" \
         "etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts.${CLUSTER_NAME} || err "failed"; ok

    echo -n "  ==> Adding SRV record in dnsmasq: "
    echo "srv-host=_etcd-server-ssl._tcp.${CLUSTER_NAME}.${BASE_DOM},etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM},2380,0,10" >> ${DNS_DIR}/${CLUSTER_NAME}.conf || \
        err "failed"; ok
done

for i in $(seq 1 ${N_WORK}); do
    echo -n "====> Waiting for Worker-$i to obtain IP address: "
    while true
    do
        sleep 5
        IP=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
        test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
    done
    MAC=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $2}')

    echo -n "  ==> Adding DHCP reservation: "
    virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config > /dev/null || \
    err "Adding DHCP reservation failed"; ok

    echo -n "  ==> Adding hosts entry in /etc/hosts.${CLUSTER_NAME}: "
    echo "$IP worker-${i}.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts.${CLUSTER_NAME} || err "failed"; ok
done

echo -n '====> Adding wild-card (*.apps) dns record in dnsmasq: '
echo "address=/apps.${CLUSTER_NAME}.${BASE_DOM}/${LBIP}" >> ${DNS_DIR}/${CLUSTER_NAME}.conf || err "failed"; ok

echo -n "====> Resstarting libvirt and dnsmasq: "
systemctl restart libvirtd || err "systemctl restart libvirtd failed"
systemctl $DNS_CMD $DNS_SVC || err "systemctl $DNS_CMD $DNS_SVC"; ok


echo -n "====> Configuring haproxy in LB VM: "
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "semanage port -a -t http_port_t -p tcp 6443" || \
    err "semanage port -a -t http_port_t -p tcp 6443 failed" && echo -n "."
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "semanage port -a -t http_port_t -p tcp 22623" || \
    err "semanage port -a -t http_port_t -p tcp 22623 failed" && echo -n "."
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl start haproxy" || \
    err "systemctl start haproxy failed" && echo -n "."
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl -q enable haproxy" || \
    err "systemctl enable haproxy failed" && echo -n "."
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl -q is-active haproxy" || \
    err "haproxy not working as expected" && echo -n "."
ok


if [ "$AUTOSTART_VMS" == "yes" ]; then
    echo -n "====> Setting VMs to autostart: "
    for vm in $(virsh list --all --name --no-autostart | grep "^${CLUSTER_NAME}-"); do
        virsh autostart "${vm}" &> /dev/null
        echo -n "."
    done
    ok
fi


echo -n "====> Waiting for SSH access on Boostrap VM: "
ssh-keygen -R bootstrap.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
ssh-keygen -R $BSIP  &> /dev/null || true
while true; do
    sleep 1
    ssh -i sshkey -o StrictHostKeyChecking=no core@bootstrap.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
    break
done
ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" true || err "SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; ok

