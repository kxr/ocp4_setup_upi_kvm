#!/bin/bash

echo 
echo "####################################" 
echo "### DEPENDENCIES & SANITY CHECKS ###"
echo "####################################"
echo 


echo -n "====> Checking if we have all the dependencies: "
for x in virsh virt-install virt-customize systemctl dig wget
do
    builtin type -P $x &> /dev/null || err "executable $x not found"
done
test -n "$(find /usr -type f -name libvirt_driver_network.so 2> /dev/null)" || \
	err "libvirt_driver_network.so not found"
ok

echo -n "====> Checking if the script/working directory already exists: "
test -d "${SETUP_DIR}" && \
    err "Directory ${SETUP_DIR} already exists" \
        "" \
        "You can use --destroy to remove your existing installation" \
        "You can also use --setup-dir to specify a different directory for this installation"
ok

echo -n "====> Checking for pull-secret (${PULL_SEC_F}): "
test -f "${PULL_SEC_F}" \
    && export PULL_SEC=$(cat ${PULL_SEC_F}) \
    || err "Pull secret not found." \
           "Please specify the pull secret file using -p or --pull-secret"
ok

echo -n "====> Checking if libvirt is running or enabled: "
    systemctl -q is-active libvirtd || systemctl -q is-enabled libvirtd || err "libvirtd is not running nor enabled"
ok

echo -n "====> Checking if we have any existing leftover VMs: "
existing=$(virsh list --all --name | grep -m1 "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap") || true
test -z "$existing" || err "Found existing VM: $existing"
ok

echo -n "====> Checking if DNS service (dnsmasq or NetworkManager) is active: "
test -d "/etc/NetworkManager/dnsmasq.d" -o -d "/etc/dnsmasq.d" || err "No dnsmasq found"
if [ "${DNS_DIR}" == "/etc/NetworkManager/dnsmasq.d" ]
then
    test -d "/etc/NetworkManager/dnsmasq.d" || err "/etc/NetworkManager/dnsmasq.d not found"
    DNS_SVC="NetworkManager"; DNS_CMD="reload";
elif [ "${DNS_DIR}" == "/etc/dnsmasq.d" ]
then
    test -d "/etc/dnsmasq.d" || err "/etc/dnsmasq.d not found"
    DNS_SVC="dnsmasq"; DNS_CMD="restart";
else
    err "DNS_DIR (-z|--dns-dir), should be either /etc/dnsmasq.d or /etc/NetworkManager/dnsmasq.d"
fi
systemctl -q is-active $DNS_SVC || err "DNS_DIR points to $DNS_DIR but $DNS_SVC is not active"
ok "${DNS_SVC}"

if [ "${DNS_SVC}" == "NetworkManager" ]; then
    echo -n "====> Checking if dnsmasq is enabled in NetworkManager: "
    find /etc/NetworkManager/ -name *.conf -exec cat {} \; | grep -v "^#" | grep dnsmasq &> /dev/null \
    	|| err "DNS Directory is set to NetworkManager but dnsmasq is not enabled in NetworkManager" \
                             "See: https://github.com/kxr/ocp4_setup_upi_kvm/wiki/Setting-Up-DNS"
    ok
fi

echo -n "====> Testing dnsmasq reload (systemctl ${DNS_CMD} ${DNS_SVC}): "
systemctl $DNS_CMD $DNS_SVC || err "systemctl ${DNS_CMD} ${DNS_SVC} failed"
ok

echo -n "====> Testing libvirtd restart (systemctl restart libvirtd): "
systemctl restart libvirtd || err "systemctl restart libvirtd failed"
ok

echo -n "====> Checking for any leftover dnsmasq config: "
test -f "${DNS_DIR}/${CLUSTER_NAME}.conf" && err "Existing dnsmasq config file found: ${DNS_DIR}/${CLUSTER_NAME}.conf"
ok

echo -n "====> Checking for any leftover hosts file: "
test -f "/etc/hosts.${CLUSTER_NAME}" && err "Existing hosts file found: /etc/hosts.${CLUSTER_NAME}"
ok

echo -n "====> Checking for any leftover/conflicting dns records: "
for h in api api-int bootstrap master-1 master-2 master-3 etcd-0 etcd-1 etcd-2 worker-1 worker-2 test.apps; do
    res=$(dig +short "${h}.${CLUSTER_NAME}.${BASE_DOM}" @127.0.0.1) || err "Failed dig @127.0.0.1"
    test -z "${res}" || err "Found existing dns record for ${h}.${CLUSTER_NAME}.${BASE_DOM}: ${res}"
done
existing=$(cat /etc/hosts | grep -v "^#" | grep -w -m1 "${CLUSTER_NAME}\.${BASE_DOM}") || true
test -z "$existing" || err "Found existing /etc/hosts records" "$existing"
ok

