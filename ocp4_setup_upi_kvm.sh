#!/bin/bash
set -e
# This script automates the procedure described here:
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/

# OpenShift Version
# e.g: If you want 4.1.2 set OCP_VER="4.1" and OCP_MINOR="2"
# e.g: If you want 4.2.latest set OCP_VER="4.2" and OCP_MINOR="latest"
# e.g: If you want 4.3.stable set OCP_VER="4.3" and OCP_MINOR="stable"
# You can also select RHCOS minor version if you want to deploy a specific one
# e.g: To use latest RHCOS for the OCP_VER you have selected, set RHCOS_MINOR="latest"
# e.g: To use RHCOS version 4.2.0, you should have set OCP_VER="4.2" and set RHCOS_MINOR="0"
OCP_VER="4.3"
OCP_MINOR="stable"
RHCOS_MINOR="latest"

# Number of Masters and Workers Nodes
N_MAST="3"
N_WORK="2"

# Libvirt network to use see `virsh net-list`
# Set this if you want to use exisitng libvirt network (also set VIR_NET_CREATE="no")
VIR_NET=""
# Set this to yes if you want this script to create a new libvirt network
VIR_NET_CREATE="yes"
# Pick a random subnet octet (192.168.XXX.0) for this network
# The network will be created by the name ocp-XXX
# Only used if VIR_NET_CREATE="yes"
VIR_NET_CREATE_OCT="133"

# If you are using NetworkManager’s embedded dnsmasq, set it to “/etc/NetworkManager/dnsmasq.d”.
# If you are using NetworkManager’s embedded dnsmasq, make sure dnsmasq in NetworkManager is enabled,
#   You can enable it by running:
#       # echo -e "[main]\ndns=dnsmasq" > /etc/NetworkManager/conf.d/nm-dns.conf
#       # systemctl restart NetworkManager
# If you are using a separate dnsmasq installed on the host set it to “/etc/dnsmasq.d”.
DNS_DIR="/etc/NetworkManager/dnsmasq.d"

# Cluster's base domain and name
BASE_DOM="local"
CLUSTER_NAME="ou4"


# Pull Secret
# Download the pull secret and provide the file here.
# The Pull secret can be downloaded from: https://cloud.redhat.com/openshift/install/metal/user-provisioned
PULL_SEC=$(cat /root/pull-secret)


# VM Storage Location
# In case if you want to store VMs to a non-default location,
# By default libvirt stores images in  /var/lib/libvirt/images
VM_DIR="/var/lib/libvirt/images"
#TODO:  free space check

# SCRIPT DIRECTORY
SCRIPT_DIR="/root/ocp4_setup_${CLUSTER_NAME}-${OCP_VER}.${OCP_MINOR}-$(date +%d%b%Y_%H%M)"

#############################################################################################

echo 
echo "### BASIC LIBVIRT CHECKS ###"
echo 

echo -n "==> Checking if we are root: "
    test "$(whoami)" == "root" || { echo "ERROR: Not running as root"; exit 1; }
    echo "ok"

echo "==> Checking if we have all the required binaries: "
    for x in virsh virt-install virt-customize systemctl dig wget
    #/usr/lib64/libvirt/connection-driver/libvirt_driver_network.so
    do
        builtin type -P $x &> /dev/null || { echo "ERROR: $x Not found"; exit 1; }
        echo "  $x: ok"
    done
echo -n "==> Checking if the pull-secret is there: "
    test -n "$PULL_SEC" || { echo "ERROR: Didn't get the pull-secret"; exit 1; }
    echo "ok"
echo -n "==> Checking if we need to create a new libvirt network: "
    if [ "$VIR_NET_CREATE" == "yes" ]
    then
        echo -n "yes: "
        test "$VIR_NET_CREATE_OCT" -gt "0" -a "$VIR_NET_CREATE_OCT" -lt "255" || { echo "ERROR: Invalid subnet octet $VIR_NET_CREATE_OCT"; exit 1; }
        virsh net-uuid "ocp-${VIR_NET_CREATE_OCT}" &> /dev/null && {
            echo "ERROR: ocp-${VIR_NET_CREATE_OCT} already exists";
            echo "  You can delete this network by running:"
            echo "      # virsh net-destroy ocp-${VIR_NET_CREATE_OCT}"
            echo "      # virsh net-undefine ocp-${VIR_NET_CREATE_OCT}"
            exit 1; }
        echo "ok"
        echo "==> Creating new libvirt network ocp-${VIR_NET_CREATE_OCT} (192.168.${VIR_NET_CREATE_OCT}.0/24)"
        /usr/bin/cp /usr/share/libvirt/networks/default.xml /tmp/new-net.xml
        sed -i "s/default/ocp-${VIR_NET_CREATE_OCT}/" /tmp/new-net.xml
        sed -i "s/virbr0/ocp-${VIR_NET_CREATE_OCT}/" /tmp/new-net.xml
        sed -i "s/122/${VIR_NET_CREATE_OCT}/g" /tmp/new-net.xml
        virsh net-define /tmp/new-net.xml
        virsh net-autostart ocp-${VIR_NET_CREATE_OCT}
        virsh net-start ocp-${VIR_NET_CREATE_OCT}
        systemctl restart libvirtd
        VIR_NET="ocp-${VIR_NET_CREATE_OCT}"
    else
        echo "no"
    fi
echo -n "==> Checking if libvirt network $VIR_NET exists: "
    virsh net-uuid "$VIR_NET" &> /dev/null || { echo "ERROR: $VIR_NET Not found"; exit 1; }
    echo "ok"

HOST_NET=$(ip -4 a s $(virsh net-info $VIR_NET | awk '/Bridge:/{print $2}') | awk '/inet /{print $2}')
echo -n "==> HOST_NET=$HOST_NET "
    test -n $HOST_NET || { echo "   ERROR: HOST_NET was empty"; exit 1; }
    echo "ok"
HOST_IP=$(echo $HOST_NET | cut -d '/' -f1)
echo -n "==> HOST_IP=$HOST_IP "
    test -n $HOST_NET || { echo "   ERROR: HOST_IP was empty"; exit 1; }
    echo "ok"

echo -n "==> Checking if we have any existing leftover VMs: "
    existing=$(virsh list --all --name | grep -m1 "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap") || true
    test -z "$existing" || { echo "   ERROR: Found existing VM: $existing"; exit 1; }
    echo "ok"

echo -n "==> Checking for any existing leftover /etc/hosts records: "
    existing=$(cat /etc/hosts | grep -v "^#" | grep -w -m1 "${CLUSTER_NAME}\.${BASE_DOM}") || true
    test -z "$existing" || { echo "   ERROR: Found existing record in /etc/hosts: $existing. (You can comment these out)"; exit 1; }
    echo "ok"

echo -n "==> Checking if first entry in resolv.conf is pointing locally: "
   test "$(grep -m1 "^nameserver " /etc/resolv.conf | awk '{print $2}')" = "127.0.0.1" || { echo "ERROR: /etc/resolv.conf not pointing to 127.0.0.1"; exit 1; }
   echo "ok"

echo -n "==> Checking if DNS service (dnsmasq or NetworkManager) is active: "
    if [ "$DNS_DIR" -ef "/etc/NetworkManager/dnsmasq.d" ]
    then
        DNS_SVC="NetworkManager"
        DNS_CMD="reload"
    elif [ "$DNS_DIR" -ef "/etc/dnsmasq.d" ]
    then
        DNS_SVC="dnsmasq"
        DNS_CMD="restart"
    else
        echo "ERROR: Invalid DNS_DIR: $DNS_DIR, should be either /etc/dnsmasq.d or /etc/NetworkManager/dnsmasq.d"
        exit 1
    fi
    systemctl -q is-active $DNS_SVC || { echo "ERROR: DNS_DIR points to $DNS_DIR but $DNS_SVC is not active"; exit 1; }
    echo "ok"

echo 
echo "### OPENSHIFT/RHCOS VERSION AND CORRESPONDING FILES ###"
echo 

# OCP CLIENT AND INSTALL FILES
OCP_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
if [ "$OCP_MINOR" == "latest" -o "$OCP_MINOR" == "stable" ]
then
    urldir="${OCP_MINOR}-${OCP_VER}"
else
    urldir="${OCP_VER}.${OCP_MINOR}"
fi
CLIENT=$(curl -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "client-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
echo -n "==> OPENSHIFT CLIENT=$CLIENT "
    test -n $CLIENT || { echo "   ERROR: Client for OpenShift version $urldir not found"; exit 1; }
    echo "ok"
CLIENT_URL="${OCP_MIRROR}/${urldir}/${CLIENT}"
echo -n "==> Checking if Client URL is downloadable: " 
    curl -qs --head --fail "$CLIENT_URL" &> /dev/null || { echo "ERROR: $CLIENT_URL not reachable"; exit 1; }
    echo "ok"
INSTALLER=$(curl -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "install-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
echo -n "==> OPENSHIFT INSTALLER=$INSTALLER "
    test -n $INSTALLER || { echo "   ERROR: Installer for OpenShift version $urldir not found"; exit 1; }
    echo "ok"
INSTALLER_URL="${OCP_MIRROR}/${urldir}/${INSTALLER}"
echo -n "==> Checking if Installer URL is downloadable: " 
    curl -qs --head --fail "$INSTALLER_URL" &> /dev/null || { echo "ERROR: $INSTALLER_URL not reachable"; exit 1; }
    echo "ok"

# RHCOS KERNEL, INITRAMFS AND IMAGE FILES
RHCOS_MIRROR="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${OCP_VER}"
if [ "$RHCOS_MINOR" == "latest" ]
then
    urldir="$RHCOS_MINOR"
else
    urldir="${OCP_VER}.${RHCOS_MINOR}"
fi
KERNEL=$(curl -qs ${RHCOS_MIRROR}/${urldir}/ | grep -m1 "installer-kernel" | sed 's/.*href="\(rhcos-.*\)">rhcos.*/\1/')
echo -n "==> RHCOS KERNEL=$KERNEL "
    test -n $KERNEL || { echo "   ERROR: Kernel for RHCOS version $urldir not found"; exit 1; }
    echo "ok"
KERNEL_URL="$RHCOS_MIRROR/${urldir}/${KERNEL}"
echo -n "==> Checking if Kernel URL is downloadable: " 
    curl -qs --head --fail "$KERNEL_URL" &> /dev/null || { echo "ERROR: $KERNEL_URL not reachable"; exit 1; }
    echo "ok"
INITRAMFS=$(curl -qs ${RHCOS_MIRROR}/${urldir}/ | grep -m1 "installer-initramfs" | sed 's/.*href="\(rhcos-.*\)">rhcos.*/\1/')
echo -n "==> RHCOS INITRAMFS=$INITRAMFS "
    test -n $INITRAMFS || { echo "   ERROR: Initramfs for RHCOS version $urldir not found"; exit 1; }
    echo "ok"
INITRAMFS_URL="$RHCOS_MIRROR/${urldir}/${INITRAMFS}"
echo -n "==> Checking if Initramfs URL is downloadable: " 
    curl -qs --head --fail "$INITRAMFS_URL" &> /dev/null || { echo "ERROR: $INITRAMFS_URL not reachable"; exit 1; }
    echo "ok"
IMAGE=$(curl -qs ${RHCOS_MIRROR}/${urldir}/ | grep -m1 "metal" | sed 's/.*href="\(rhcos-.*.raw.gz\)".*/\1/')
echo -n "==> RHCOS IMAGE=$IMAGE "
    test -n $IMAGE || { echo "   ERROR: Image for RHCOS version $urldir not found"; exit 1; }
    echo "ok"
IMAGE_URL="$RHCOS_MIRROR/${urldir}/${IMAGE}"
echo -n "==> Checking if Image URL is downloadable: " 
    curl -qs --head --fail "$IMAGE_URL" &> /dev/null || { echo "ERROR: $IMAGE_URL not reachable"; exit 1; }
    echo "ok"


echo; echo; echo;
echo -n "All Good! Shall we proceed installing OpenShift 4 ?"
read userinput


echo
echo "### DOWNLOAD AND PREPARE OPENSHIFT 4 INSTALLATION ###"
echo 

echo -n "==> Creating and using directory $SCRIPT_DIR: "
    test -d "$SCRIPT_DIR" && { echo "ERROR Directory $SCRIPT_DIR already exists"; exit 1; }
    mkdir -p $SCRIPT_DIR && cd $SCRIPT_DIR || { echo "ERROR using $SCRIPT_DIR"; exit 1; }
    echo "ok"

ssh-keygen -f sshkey -q -N ""
SSH_KEY="sshkey.pub"

wget -q --show-progress "$IMAGE_URL"
wget -q --show-progress "$CLIENT_URL"
tar -xf "$CLIENT" && rm -f README.md "$CLIENT"
wget -q --show-progress "$INSTALLER_URL"
tar -xf "$INSTALLER" && rm -f rm -f README.md "$INSTALLER"

mkdir rhcos-install
wget -q --show-progress "$KERNEL_URL" -O rhcos-install/vmlinuz
wget -q --show-progress "$INITRAMFS_URL" -O rhcos-install/initramfs.img
cat <<EOF > rhcos-install/.treeinfo
[general]
arch = x86_64
family = Red Hat CoreOS
platforms = x86_64
version = ${OCP_VER}
[images-x86_64]
initrd = initramfs.img
kernel = vmlinuz
EOF


mkdir install_dir
cat <<EOF > install_dir/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOM}
compute:
- hyperthreading: Disabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Disabled
  name: master
  replicas: ${N_MAST}
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '${PULL_SEC}'
sshKey: '$(cat $SSH_KEY)'
EOF

./openshift-install create ignition-configs --dir=./install_dir

WS_PORT="1234"
cat <<EOF > tmpws.service
[Unit]
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt
ExecStart=/usr/bin/python -m SimpleHTTPServer ${WS_PORT}
[Install]
WantedBy=default.target
EOF



echo "
global
  log 127.0.0.1 local2
  chroot /var/lib/haproxy
  pidfile /var/run/haproxy.pid
  maxconn 4000
  user haproxy
  group haproxy
  daemon
  stats socket /var/lib/haproxy/stats

defaults
  mode tcp
  log global
  option tcplog
  option dontlognull
  option redispatch
  retries 3
  timeout queue 1m
  timeout connect 10s
  timeout client 1m
  timeout server 1m
  timeout check 10s
  maxconn 3000
# 6443 points to control plan
frontend ${CLUSTER_NAME}-api *:6443
  default_backend master-api
backend master-api
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOM}:6443 check" > haproxy.cfg
for i in $(seq 1 ${N_MAST})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOM}:6443 check" >> haproxy.cfg
done
echo "

# 22623 points to control plane
frontend ${CLUSTER_NAME}-mapi *:22623
  default_backend master-mapi
backend master-mapi
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOM}:22623 check" >> haproxy.cfg
for i in $(seq 1 ${N_MAST})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOM}:22623 check" >> haproxy.cfg
done
echo "
# 80 points to worker nodes
frontend ${CLUSTER_NAME}-http *:80
  default_backend ingress-http
backend ingress-http
  balance source" >> haproxy.cfg
for i in $(seq 1 ${N_WORK})
do
    echo "  server worker-${i} worker-${i}.${CLUSTER_NAME}.${BASE_DOM}:80 check" >> haproxy.cfg
done
echo "
# 443 points to worker nodes
frontend ${CLUSTER_NAME}-https *:443
  default_backend infra-https
backend infra-https
  balance source" >> haproxy.cfg
for i in $(seq 1 ${N_WORK})
do
    echo "  server worker-${i} worker-${i}.${CLUSTER_NAME}.${BASE_DOM}:443 check" >> haproxy.cfg
done



echo 
echo "### LOAD BALANCER VM ###"
echo 

LB_IMG_URL="https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
if [ -s "${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" ]
then
    echo "==> Reusing existing Image on disk: ${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2"
else
    echo -n "==> Checking if CentOS-7-x86_64-GenericCloud.qcow2 is downloadable: "
        curl -qs --head --fail "$LB_IMG_URL" &> /dev/null || { echo "ERROR: $LB_IMG_URL not reachable"; exit 1; }
        echo "ok"
    
    echo -n "==> Downloading CentOS-7-x86_64-GenericCloud.qcow2 for LB VM "
        wget "$LB_IMG_URL" -O "${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2"
        test "$?" -eq "0" || { echo "ERROR: Downloading $LB_IMG_URL to ${VM_DIR}/ failed"; exit 1; }
        echo "ok"
fi

echo -n "==> Copying Image for Loadbalancer VM: "
    cp -a "${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" || \
    { echo "ERROR: Copying '${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2' to '${VM_DIR}/${CLUSTER_NAME}-lb.qcow2' failed"; exit 1; }
    echo "ok"
echo "==> Setting up Loadbalancer VM: "
    # virt-customize -a "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" --uninstall cloud-init --ssh-inject root:file:$SSH_KEY --selinux-relabel --install haproxy --install bind-utils || \
    virt-customize -a "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
        --uninstall cloud-init --ssh-inject root:file:$SSH_KEY --selinux-relabel --install haproxy --install bind-utils \
        --copy-in install_dir/bootstrap.ign:/opt/ --copy-in install_dir/master.ign:/opt/ --copy-in install_dir/worker.ign:/opt/ \
        --copy-in "$IMAGE":/opt/ --copy-in tmpws.service:/etc/systemd/system \
        --copy-in haproxy.cfg:/etc/haproxy/ \
        --run-command "systemctl daemon-reload" --run-command "systemctl enable tmpws.service" || \
    { echo "ERROR: Setting up Loadbalancer VM image ${VM_DIR}/${CLUSTER_NAME}-lb.qcow2 failed"; exit 1; }
    echo "ok"
echo "==> Creating Loadbalancer VM: "
    virt-install --import --name ${CLUSTER_NAME}-lb --disk "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" --memory 1024 --cpu host --vcpus 1 --os-type linux --os-variant rhel7-unknown --network network=${VIR_NET},model=virtio --noreboot --noautoconsole || \
    { echo "ERROR: Creating Loadbalancer VM from ${VM_DIR}/${CLUSTER_NAME}-lb.qcow2 failed"; exit 1; }
echo "==> Starting Loadbalancer VM "
    virsh start ${CLUSTER_NAME}-lb || { echo "ERROR: Starting Loadbalancer VM ${CLUSTER_NAME}-lb failed"; exit 1; }
    echo "ok"
echo -n "==> Waiting for Loadbalancer VM to obtain IP address: "
    while true
    do
        sleep 5
        LBIP=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
        test "$?" -eq "0" -a -n "$LBIP"  && { echo "$LBIP"; break; }
    done
    MAC=$(virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $2}')

echo -n "==> Adding DHCP reservation for LB IP/MAC: "
    virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$LBIP'/>" --live --config &> /dev/null || \
    { echo "ERROR: Adding DHCP reservation for $LBIP/$MAC failed"; exit 1; }
    echo "ok"

echo -n "==> Adding /etc/hosts entry for LB IP: "
    echo "$LBIP lb.${CLUSTER_NAME}.${BASE_DOM}" \
    "api.${CLUSTER_NAME}.${BASE_DOM}" \
    "api-int.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
    echo ok

echo -n "==> Waiting for SSH access on LB VM: "
    ssh-keygen -R lb.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
    ssh-keygen -R $LBIP  &> /dev/null || true
    while true
    do
        sleep 1
        ssh -i sshkey -o StrictHostKeyChecking=no lb.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
        break
    done
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" true || { echo "ERROR: SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; exit 1; }
    echo "ok"

echo
echo "#### DNS CHECK ###"
echo

echo -n "==> Testing DNS forward and reverse record: "
    echo "1.2.3.4 xxxtestxxx.${BASE_DOM}" >> /etc/hosts && \
    systemctl restart libvirtd && \
    sleep 5 && \
    fwd_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig +short 'xxxtestxxx.${BASE_DOM}' 2> /dev/null")
    test "$?" -eq "0" -a "$fwd_dig" = "1.2.3.4" || { echo "ERROR: Testing DNS forward record failed ($fwd_dig)"; exit 1; }
    echo -n "forward: ok "
    rev_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig +short -x '1.2.3.4' 2> /dev/null")
    test "$?" -eq "0" -a "$rev_dig" = "xxxtestxxx.${BASE_DOM}." || { echo "ERROR: Testing DNS reverse record failed ($rev_dig)"; exit 1; }
    echo "reverse: ok"
echo -n "==> Testing srv record in dnsmasq: "
    echo "srv-host=xxxtestxxx.${BASE_DOM},yyyayyy.${BASE_DOM},2380,0,10" > ${DNS_DIR}/xxxtestxxx.conf
    systemctl $DNS_CMD $DNS_SVC 
    srv_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig srv +short 'xxxtestxxx.${BASE_DOM}' 2> /dev/null" | grep -q -s "yyyayyy.${BASE_DOM}")
    test "$?" -eq "0" || { echo "ERROR: Testing DNS reverse record failed"; exit 1; }
    echo "ok"
echo -n "==> Cleaning up: "
    sed -i "/1.2.3.4 xxxtestxxx.${BASE_DOM}/d" /etc/hosts
    rm -f ${DNS_DIR}/xxxtestxxx.conf
    systemctl $DNS_CMD $DNS_SVC
    echo "ok"

echo "==> Creating Boostrap VM: "
virt-install --name ${CLUSTER_NAME}-bootstrap \
  --disk "${VM_DIR}/${CLUSTER_NAME}-bootstrap.qcow2,size=50" --ram 16000 --cpu host --vcpus 4 \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIR_NET} --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/bootstrap.ign"

for i in $(seq 1 ${N_MAST})
do
echo "==> Creating Master-${i} VM: "
virt-install --name ${CLUSTER_NAME}-master-${i} \
--disk "${VM_DIR}/${CLUSTER_NAME}-master-${i}.qcow2,size=50" --ram 16000 --cpu host --vcpus 4 \
--os-type linux --os-variant rhel7-unknown \
--network network=${VIR_NET} --noreboot --noautoconsole \
--location rhcos-install/ \
--extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/master.ign"
done

for i in $(seq 1 ${N_WORK})
do
echo "==> Creating Worker-${i} VM: "
  virt-install --name ${CLUSTER_NAME}-worker-${i} \
  --disk "${VM_DIR}/${CLUSTER_NAME}-worker-${i}.qcow2,size=50" --ram 8192 --cpu host --vcpus 4 \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIR_NET} --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/worker.ign"
done

echo "==> Waiting for RHCOS Installation to finish on bootstrap, master and worker nodes: "
while rvms=$(virsh list --name | grep "${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" 2> /dev/null)
do
    sleep 15
    echo "  Following VMs are still running: $(echo $rvms | tr '\n' ' ')"
done
echo "ok"

echo "local=/${CLUSTER_NAME}.${BASE_DOM}/" > ${DNS_DIR}/${CLUSTER_NAME}.conf

echo "==> Starting Bootstrap VM: "
    virsh start ${CLUSTER_NAME}-bootstrap
for i in $(seq 1 ${N_MAST})
do
    echo "==> Starting Master-{$i} VM: "
    virsh start ${CLUSTER_NAME}-master-${i}
done
for i in $(seq 1 ${N_WORK})
do
    echo "==> Starting Worker-${i} VMs: "
    virsh start ${CLUSTER_NAME}-worker-${i}
done

echo -n "==> Waiting for Bootstrap to obtain IP address: "
    while true
    do
        sleep 5
        IP=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
        test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
    done
    MAC=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $2}')
virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
echo "$IP bootstrap.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts

for i in $(seq 1 ${N_MAST})
do
    echo -n "==> Waiting for Master-$i to obtain IP address: "
        while true
        do
            sleep 5
            IP=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
            test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
        done
        MAC=$(virsh domifaddr "${CLUSTER_NAME}-master-${i}" | grep ipv4 | head -n1 | awk '{print $2}')
  virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
  echo "$IP master-${i}.${CLUSTER_NAME}.${BASE_DOM}" \
  "etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
  echo "srv-host=_etcd-server-ssl._tcp.${CLUSTER_NAME}.${BASE_DOM},etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM},2380,0,10" >> ${DNS_DIR}/${CLUSTER_NAME}.conf
done

for i in $(seq 1 ${N_WORK})
do
    echo -n "==> Waiting for Worker-$i to obtain IP address: "
        while true
        do
            sleep 5
            IP=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
            test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
        done
        MAC=$(virsh domifaddr "${CLUSTER_NAME}-worker-${i}" | grep ipv4 | head -n1 | awk '{print $2}')
   virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config
   echo "$IP worker-${i}.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts
done

echo "address=/apps.${CLUSTER_NAME}.${BASE_DOM}/${LBIP}" >> ${DNS_DIR}/${CLUSTER_NAME}.conf

systemctl restart libvirtd
systemctl $DNS_CMD $DNS_SVC

echo -n "==> Configuring haproxy in LB VM: "
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "semanage port -a -t http_port_t -p tcp 6443" || \
    { echo "ERROR: semanage port -a -t http_port_t -p tcp 6443 failed"; exit 1; } && echo -n "."
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "semanage port -a -t http_port_t -p tcp 22623" || \
    { echo "ERROR: semanage port -a -t http_port_t -p tcp 22623 failed"; exit 1; } && echo -n "."
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl start haproxy" || \
    { echo "ERROR: systemctl start haproxy failed"; exit 1; } && echo -n "."
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl -q enable haproxy" || \
    { echo "ERROR: systemctl enable haproxy failed"; exit 1; } && echo -n "."
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl -q is-active haproxy" || \
    { echo "ERROR: haproxy not working as expected"; exit 1; } && echo -n "."
    echo "ok"



echo -n "==> Waiting for SSH access on Boostrap VM: "
    ssh-keygen -R bootstrap.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
    while true
    do
        sleep 1
        ssh -i sshkey -o StrictHostKeyChecking=no core@bootstrap.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
        break
    done
    ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" true || { echo "ERROR: SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; exit 1; }
    echo "ok"

export KUBECONFIG="install_dir/auth/kubeconfig"

echo "==> Waiting for Boostraping to finish: "
    while true
    do
        sleep 30
        api_stat=$(./oc get --raw / &> /dev/null && echo "UP" || echo "DOWN")
        sys_load=$(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "w | sed 's/.*load average: \(.*\), .*,.*/\1/;t;d'")
        pod_imgs=$(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo podman images | grep -v '^REPOSITORY' | wc -l")
        cri_cont=$(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo crictl ps | grep -v '^CONTAINER' | wc -l")
        btk_stat=$(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo systemctl is-active bootkube.service") || break
        echo "Load = $sys_load, Images = $pod_imgs, Containers = $cri_cont, BootKube = $btk_stat, API=$api_stat"
    done
    echo "ok"

echo "==> Removing Boostrap VM: "
    virsh destroy ${CLUSTER_NAME}-bootstrap
    virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage

echo "==> Removing Bootstrap from haproxy: "
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "sed -i '/bootstrap\.${CLUSTER_NAME}\.${BASE_DOM}/d' /etc/haproxy/haproxy.cfg"
    ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl restart haproxy"

echo -n "==> Waiting for configs.imageregistry: "
    while true
    do
        sleep 5
        ./oc get configs.imageregistry.operator.openshift.io cluster &> /dev/null && break || continue
    done
    echo "ok"

echo -n "==> Patching imageregistry to use emptyDir for storage: "
    ./oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}' || \
    { echo "ERROR: Failed to patch configs.imageregistry.operator.openshift.io cluster" exit 1; }

echo "==> Waiting for clusterversion: "
    while true
    do
        sleep 30
        cv_prog_msg=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Progressing")].message}') || continue
        cv_avail=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Available")].status}') || continue
        echo "  $cv_prog_msg"
        test "$cv_avail" = "True" && break
    done

./openshift-install --dir=install_dir wait-for install-complete
