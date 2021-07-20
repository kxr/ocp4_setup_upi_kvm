#!/bin/bash

echo 
echo "#################################"
echo "### CREATING LOAD BALANCER VM ###"
echo "#################################"
echo


echo -n "====> Downloading Centos 7 cloud image: "; download get "$LB_IMG" "$LB_IMG_URL";

echo -n "====> Copying Image for Loadbalancer VM: "
cp "${CACHE_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" || \
    err "Copying '${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2' to '${VM_DIR}/${CLUSTER_NAME}-lb.qcow2' failed"; ok

echo "====> Setting up Loadbalancer VM: "
virt-customize -a "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --uninstall cloud-init --ssh-inject root:file:${SSH_PUB_KEY_FILE} --selinux-relabel --install haproxy --install bind-utils \
    --copy-in install_dir/bootstrap.ign:/opt/ --copy-in install_dir/master.ign:/opt/ --copy-in install_dir/worker.ign:/opt/ \
    --copy-in "${CACHE_DIR}/${IMAGE}":/opt/ --copy-in tmpws.service:/etc/systemd/system/ \
    --copy-in haproxy.cfg:/etc/haproxy/ \
    --run-command "systemctl daemon-reload" --run-command "systemctl enable tmpws.service" || \
    err "Setting up Loadbalancer VM image ${VM_DIR}/${CLUSTER_NAME}-lb.qcow2 failed"

echo -n "====> Creating Loadbalancer VM: "
virt-install --import --name ${CLUSTER_NAME}-lb --disk "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --memory ${LB_MEM} --cpu host --vcpus ${LB_CPU} --os-type linux --os-variant rhel7.0 --network network=${VIR_NET},model=virtio \
    --noreboot --noautoconsole > /dev/null || \
    err "Creating Loadbalancer VM from ${VM_DIR}/${CLUSTER_NAME}-lb.qcow2 failed"; ok

echo -n "====> Starting Loadbalancer VM "
virsh start ${CLUSTER_NAME}-lb > /dev/null || err "Starting Loadbalancer VM ${CLUSTER_NAME}-lb failed"; ok

echo -n "====> Waiting for Loadbalancer VM to obtain IP address: "
while true; do
    sleep 5
    LBIP=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
    test "$?" -eq "0" -a -n "$LBIP"  && { echo "$LBIP"; break; }
done
MAC=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $2}')

echo -n "====> Adding DHCP reservation for LB IP/MAC: "
virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$LBIP'/>" --live --config &> /dev/null || \
    err "Adding DHCP reservation for $LBIP/$MAC failed"; ok

echo -n "====> Adding LB hosts entry in /etc/hosts.${CLUSTER_NAME}: "
    echo "$LBIP lb.${CLUSTER_NAME}.${BASE_DOM}" \
    "api.${CLUSTER_NAME}.${BASE_DOM}" \
    "api-int.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts.${CLUSTER_NAME}; ok

systemctl $DNS_CMD $DNS_SVC || err "systemctl $DNS_CMD $DNS_SVC failed";

echo -n "====> Waiting for SSH access on LB VM: "
ssh-keygen -R lb.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
ssh-keygen -R ${LBIP}  &> /dev/null || true
while true; do
    sleep 1
    ssh -i sshkey -o StrictHostKeyChecking=no lb.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
    break
done
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" true || err "SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; ok

