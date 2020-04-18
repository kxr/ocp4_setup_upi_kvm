#!/bin/bash
# This script automates the procedure described here:
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/
set -e
START_TS=$(date +%s)

err() {
    echo; echo;
    echo -e "\e[97m\e[101m[ERROR]\e[0m ${1}"; shift; echo;
    while [[ $# -gt 0 ]]; do echo "    $1"; shift; done
    echo; exit 1;
}

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

# Process Arguments
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -O|--ocp-version)
    OCP_VERSION="$2"
    shift
    shift
    ;;
    -R|--rhcos-version)
    RHCOS_VERSION="$2"
    shift
    shift
    ;;
    -m|--masters)
    N_MAST="$2"
    test "$N_MAST" -gt "0" &>/dev/null || err "Invalid masters: $N_MAST"
    sdhift
    shift
    ;;
    -w|--workers)
    N_WORK="$2"
    test "$N_MAST" -gt "0" &> /dev/null || err "Invalid workers: $N_MAST"
    shift
    shift
    ;;
    -p|--pull-secret)
    PULL_SEC_F="$2"
    shift
    shift
    ;;
    -n|--libvirt-network)
    VIR_NET="$2"
    shift
    shift
    ;;
    -N|--libvirt-oct)
    VIR_NET_OCT="$2"
    test "$VIR_NET_OCT" -gt "0" -a "$VIR_NET_OCT" -lt "255" || err "Invalid subnet octet $VIR_NET_OCT"
    shift
    shift
    ;;
    --libvirt-net-recreate)
    VIR_NET_RECREATE="yes"
    shift
    ;;
    -c|--cluster-name)
    CLUSTER_NAME="$2"
    shift
    shift
    ;;
    -d|--cluster-domain)
    BASE_DOM="$2"
    shift
    shift
    ;;
    -v|--vm-dir)
    VM_DIR="$2"
    shift
    shift
    ;;
    -z|--dns-dir)
    DNS_DIR="$2"
    shift
    shift
    ;;
    -s|--script-dir)
    SCRIPT_DIR="$2"
    shift
    shift
    ;;
    -x|--cache-dir)
    CACHE_DIR="$2"; mkdir -p "$CACHE_DIR"
    shift
    shift
    ;;
    -X|--fresh-download)
    FRESH_DOWN="yes"
    shift
    ;;
    -k|--keep-bootstrap)
    KEEP_BS="yes"
    shift
    ;;
    --destroy-installation)
    CLEANUP="yes"
    shift
    ;;
    -y|--yes)
    YES="yes"
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
test -z "$OCP_VERSION" && OCP_VERSION="stable"
test -z "$N_MAST" && N_MAST="3"
test -z "$N_WORK" && N_WORK="2"
test -z "$VIR_NET" -a -z "$VIR_NET_OCT" && VIR_NET="default"
test -n "$VIR_NET" -a -n "$VIR_NET_OCT" && err "Specify either -n or -N or -O" 
test -n "$VIR_NET" -a -n "$VIR_NET_RECREATE" && err "Cannot recreate existing network by name (use -N or -O)" 
test -z "$CLUSTER_NAME" && CLUSTER_NAME="ocp4"
test -z "$BASE_DOM" && BASE_DOM="local"
test -z "$DNS_DIR" && DNS_DIR="/etc/NetworkManager/dnsmasq.d"
test -z "$VM_DIR" && VM_DIR="/var/lib/libvirt/images"
test -z "$SCRIPT_DIR" && SCRIPT_DIR="/root/ocp4_setup_${CLUSTER_NAME}"
test -z "$CACHE_DIR" && CACHE_DIR="/root/ocp4_downloads" && mkdir -p "$CACHE_DIR"
test -z "$PULL_SEC_F" && PULL_SEC_F="/root/pull-secret"; PULL_SEC=$(cat "$PULL_SEC_F")

OCP_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
RHCOS_MIRROR="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos"

if [ "$SHOW_HELP" == "yes" ]; then
echo
echo "Usage: ${0} [OPTIONS]"
echo
cat << EOF | column -L -t -s '|' -N OPTION,DESCRIPTION -W DESCRIPTION

-O, --ocp-version VERSION|The OpenShift version to install.
|You can set this to "latest", "stable" or a specific version like "4.1", "4.1.2", "4.1.latest", "4.1.stable" etc.
|Default: stable

-R, --rhcos-version VERSION|You can set a specific RHCOS version to use. For example "4.1.0", "4.2.latest" etc.
|By default the RHCOS version is matched from the OpenShift version. For example, if you selected 4.1.2  RHCOS 4.1/latest will be used

-p, --pull-secret FILE|Location of the pull secret file
|Default: /root/pull-secret

-c, --cluster-name NAME|OpenShift 4 cluster name
|Default: ocp4

-d, --cluster-domain DOMAIN|OpenShift 4 cluster domain
|Default: local

-n, --libvirt-network NETWORK|The libvirt network to use. Select this option if you want to use an existing libvirt network.
|The libvirt network should already exist. If you want the script to create a separate network for this installation see: -N, --libvirt-oct
|Default: default

-N, --libvirt-oct OCTET|You can specify a 192.168.{OCTET}.0 subnet octet and this script will create a new libvirt network for the cluster
|The network will be named ocp-{OCTET}. If the libvirt network ocp-{OCTET} already exists, the script will fail unless --libvirt-network-recreate is specified
|Default: <not set>

--libvirt-network-recreate|Set this if you want the script to delete and recreate the ocp-{OCTET} network if it already exists
|Default: <not set>

-v, --vm-dir|The location where you want to store the VM Disks
|Default: /var/lib/libvirt/images

-z, --dns-dir DIR|We expect the DNS on the host to be managed by dnsmasq. You can use NetworkMananger's built-in dnsmasq or use a separate dnsmasq running on the host. If you are running a separate dnsmasq on the host, set this to "/etc/dnsmasq.d"
|Default: /etc/NetworkManager/dnsmasq.d

-s, --script-dir DIR|The location where we the script keeps all the files related to the installation
|Default: /root/ocp4_setup_{CLUSTER_NAME}

-x, --cache-dir DIR|To avoid un-necessary downloads we download the OpenShift/RHCOS files to a cache directory and reuse the files if they exist
|This way you only download a file once and reuse them for future installs
|You can force the script to download a fresh copy by using -X, --fresh-download
|Default: /root/ocp4_downloads

-X, --fresh-download|Set this if you want to force the script to download a fresh copy of the files instead of reusing the existing ones in cache dir
|Default: <not set>

-k, --keep-bootstrap|Set this if you want to keep the bootstrap VM. By default bootstrap VM is removed once the bootstraping is finished
|Default: <not set>

-y, --yes|Set this for the script to be non-interactive and continue with out asking for confirmation
|Default: <not set>

--destroy-installation|Set this if you want the script to destroy everything it has created.
|Use this option with the same options you used to install the cluster.
|Be carefull this deletes the VMs, DNS entries and the libvirt network (if created by the script)
|Default: <not set>
EOF
echo
echo "Examples:"
echo
echo "${0} --ocp-version 4.3.12"
echo 
echo "${0} --pull-secret /home/knaeem/Downloads/pull-secret --ocp-version latest"
echo 
echo "${0} --cluster-name ocp43 --cluster-domain lab.test.com --pull-secret /home/knaee/Downloads/pull-secret --ocp-version 4.2.latest"
echo
echo "${0} --cluster-name ocp43 --cluster-domain lab.test.com --destroy-installation"
echo
exit
fi

ok() {
    test -z "$1" && echo "ok" || echo "$1"
}
check_if_we_can_continue() {
    if [ "$YES" != "yes" ]; then
        echo;
        test -n "$1" && echo "[NOTE] $1"
        echo -n "Press enter to continue"; read x;
    fi
}

download() {
    if [ "$1" == "check" ]
    then
        test -f "${CACHE_DIR}/$2" && echo "(reusing cached file) " || \
            { curl -qs --head --fail "$3" &> /dev/null; echo; } || \
                err "$3 not reachable"
    elif [ "$1" == "get" -a -n "$2" ]
    then
        test "$FRESH_DOWN" = "yes" -a -f "${CACHE_DIR}/$2" && rm -f "${CACHE_DIR}/$2" || true
        test -f "${CACHE_DIR}/$2" && echo "(reusing cached file) " || \
            { echo; wget -q --show-progress "$3" -O "${CACHE_DIR}/$2"; }
    fi
}


if [ "$CLEANUP" == "yes" ]; then

    for vm in $(virsh list --all --name | grep "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap"); do
        check_if_we_can_continue "Deleting VM $vm"
        echo -n "XXXX> Deleting VM $vm: "
        virsh destroy "$vm" > /dev/null || err "virsh destroy $vm failed";
        virsh undefine "$vm" --remove-all-storage > /dev/null || err "virsh destroy $vm --remove-all-storage failed";
        ok
    done

    if [ -n "$VIR_NET_OCT" ]; then
        check_if_we_can_continue "Deleting libvirt network ocp-${VIR_NET_OCT}"
        echo -n "XXXX> Deleting libvirt network ocp-${VIR_NET_OCT}: "
        virsh net-destroy "ocp-${VIR_NET_OCT}" > /dev/null || err "virsh net-destroy ocp-${VIR_NET_OCT} failed"
        virsh net-undefine "ocp-${VIR_NET_OCT}" > /dev/null || err "virsh net-undefine ocp-${VIR_NET_OCT} failed"
        ok
    fi

    if [ -d "$SCRIPT_DIR" ]; then
        check_if_we_can_continue "Removing directory (rm -rf) $SCRIPT_DIR"
        echo -n "XXXX> Deleting (rm -rf) directory $SCRIPT_DIR: "
        rm -rf "$SCRIPT_DIR"
        ok
    fi

    cat /etc/hosts | grep -v "^#" | grep -q -s "${CLUSTER_NAME}\.${BASE_DOM}$" > /dev/null
    if [ "$?" == "0" ]; then
        check_if_we_can_continue "Commenting entries in /etc/hosts for ${CLUSTER_NAME}.${BASE_DOM}"
        echo -n "XXXX> Commenting entries in /etc/hosts for ${CLUSTER_NAME}.${BASE_DOM}: "
        sed -i "s/\(.*\.${CLUSTER_NAME}\.${BASE_DOM}$\)/#\1/" "/etc/hosts" || err "sed failed"
        ok
    fi

    if [ -f "${DNS_DIR}/${CLUSTER_NAME}.conf" ]; then
        check_if_we_can_continue "Removing file ${DNS_DIR}/${CLUSTER_NAME}.conf"
        echo -n "XXXX> Removing file ${DNS_DIR}/${CLUSTER_NAME}.conf: "
        rm -f "${DNS_DIR}/${CLUSTER_NAME}.conf" &> /dev/null || true 
        ok
    fi

    exit
fi



echo 
echo "##########################################"
echo "### OPENSHIFT/RHCOS VERSION/URL CHECK  ###"
echo "##########################################"
echo

# OCP4 INSTALL AND CLIENT FILES

if [ "$OCP_VERSION" == "latest" -o "$OCP_VERSION" == "stable" ]; then
    urldir="$OCP_VERSION"
else
    test "$(echo $OCP_VERSION | cut -d '.' -f1)" = "4" || err "Invalid OpenShift version $OCP_VERSION"
    OCP_VER=$(echo "$OCP_VERSION" | cut -d '.' -f1-2)
    OCP_MINOR=$(echo "$OCP_VERSION" | cut -d '.' -f3)
    test -z "$OCP_MINOR" && OCP_MINOR="stable"
    if [ "$OCP_MINOR" == "latest" -o "$OCP_MINOR" == "stable" ]
    then
        urldir="${OCP_MINOR}-${OCP_VER}"
    else
        urldir="${OCP_VER}.${OCP_MINOR}"
    fi
fi
echo -n "====> Looking up OCP4 client for release $urldir: "
CLIENT=$(curl --fail -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "client-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
    test -n "$CLIENT" || err "No client found in ${OCP_MIRROR}/${urldir}/"; ok "$CLIENT"
CLIENT_URL="${OCP_MIRROR}/${urldir}/${CLIENT}"
echo -n "====> Checking if Client URL is downloadable: "; download check "$CLIENT" "$CLIENT_URL";

echo -n "====> Looking up OCP4 installer for release $urldir: "
INSTALLER=$(curl --fail -qs "${OCP_MIRROR}/${urldir}/" | grep  -m1 "install-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
    test -n "$INSTALLER" || err "No installer found in ${OCP_MIRROR}/${urldir}/"; ok "$INSTALLER"
INSTALLER_URL="${OCP_MIRROR}/${urldir}/${INSTALLER}"
echo -n "====> Checking if Installer URL is downloadable: ";  download check "$INSTALLER" "$INSTALLER_URL";

# RHCOS KERNEL, INITRAMFS AND IMAGE FILES

if [ -z "$RHCOS_VERSION" ]; then
    RHCOS_VER=$(echo "${INSTALLER##*-}" | cut -d '.' -f1-2 )
    RHCOS_MINOR="latest"
else
    RHCOS_VER=$(echo "$RHCOS_VERSION" | cut -d '.' -f1-2)
    RHCOS_MINOR=$(echo "$RHCOS_VERSION" | cut -d '.' -f3)
    test -z "$RHCOS_MINOR" && RHCOS_MINOR="latest"
fi

if [ "$RHCOS_MINOR" == "latest" ]
then
    urldir="$RHCOS_MINOR"
else
    urldir="${RHCOS_VER}.${RHCOS_MINOR}"
fi

echo -n "====> Looking up RHCOS kernel for release $RHCOS_VER/$urldir: "
KERNEL=$(curl --fail -qs "${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/" | grep -m1 "installer-kernel" | sed 's/.*href="\(rhcos-.*\)">rhcos.*/\1/')
    test -n "$KERNEL" || err "No kernel found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$KERNEL"
KERNEL_URL="${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/${KERNEL}"
echo -n "====> Checking if Kernel URL is downloadable: "; download check "$KERNEL" "$KERNEL_URL";

echo -n "====> Looking up RHCOS initramfs for release $RHCOS_VER/$urldir: "
INITRAMFS=$(curl --fail -qs ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/ | grep -m1 "installer-initramfs" | sed 's/.*href="\(rhcos-.*\)">rhcos.*/\1/')
    test -n "$INITRAMFS" || err "No initramfs found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$INITRAMFS"
INITRAMFS_URL="$RHCOS_MIRROR/${RHCOS_VER}/${urldir}/${INITRAMFS}"
echo -n "====> Checking if Initramfs URL is downloadable: "; download check "$INITRAMFS" "$INITRAMFS_URL";

echo -n "====> Looking up RHCOS image for release $RHCOS_VER/$urldir: "
IMAGE=$(curl --fail -qs ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/ | grep -m1 "metal" | sed 's/.*href="\(rhcos-.*.raw.gz\)".*/\1/')
    test -n "$IMAGE" || err "No image found in ${RHCOS_MIRROR}/${RHCOS_VER}/${urldir}/"; ok "$IMAGE"
IMAGE_URL="$RHCOS_MIRROR/${RHCOS_VER}/${urldir}/${IMAGE}"
echo -n "====> Checking if Image URL is downloadable: "; download check "$IMAGE" "$IMAGE_URL";

# CENTOS CLOUD IMAGE
LB_IMG_URL="https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
LB_IMG="${LB_IMG_URL##*/}"
echo -n "====> Checking if Centos cloud image URL is downloadable: "; download check "$LB_IMG" "$IMAGE_URL";


echo
echo
echo "      Red Hat OpenShit Version = $(echo "${INSTALLER##*-}" | cut -d '.' -f1-3 )"
echo
echo "        Red Hat CoreOS Version = $(echo "${IMAGE}" | cut -d '-' -f2 )"

check_if_we_can_continue

echo 
echo "###################################" 
echo "### PRELIMINARY / SANITY CHECKS ###"
echo "###################################"
echo 


echo -n "====> Checking if we have all the dependencies: "
for x in virsh virt-install virt-customize systemctl dig wget
do
    builtin type -P $x &> /dev/null || err "executable $x not found"
done
for f in "/usr/lib64/libvirt/connection-driver/libvirt_driver_network.so" \
         "/usr/share/libvirt/networks/default.xml"
do
    test -e "$f" &> /dev/null || err "file $f not found"
done
ok

echo -n "====> Checking if libvirt is running: "
    systemctl -q is-active libvirtd || err "libvirtd is not running"; ok

echo -n "====> Checking libvirt network: "
if [ -n "$VIR_NET_OCT" -a "$VIR_NET_RECREATE" != "yes" ]; then
    virsh net-uuid "ocp-${VIR_NET_OCT}" &> /dev/null && \
        err "libvirt network ocp-${VIR_NET_OCT} already exists" "You can delete this network by running:" \
            "   # virsh net-destroy ocp-${VIR_NET_OCT}" \
            "   # virsh net-undefine ocp-${VIR_NET_OCT}" \
            "" \
            "Or, you can use -O $VIR_NET_OCT to force recreation" \
            "" \
            "If you want to reuse this network specify -n $VIR_NET_OCT"
    ok
elif [ -n "$VIR_NET" ]; then
    virsh net-uuid "${VIR_NET}" &> /dev/null || \
        err "${VIR_NET} doesn't exist"
    ok "using $VIR_NET"
elif [ "$VIR_NET_RECREATE" == "yes" -a -n "$VIR_NET_OCT"  ]; then
    ok "ok, will be deleting and recreating ocp-${VIR_NET_OCT}"
else
    err "Sorry, unhandled situation. Exiting"
fi

echo -n "====> Checking if we have any existing leftover VMs: "
existing=$(virsh list --all --name | grep -m1 "${CLUSTER_NAME}-lb\|${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap") || true
test -z "$existing" || err "Found existing VM: $existing"
ok

echo -n "====> Checking for any existing leftover /etc/hosts records: "
existing=$(cat /etc/hosts | grep -v "^#" | grep -w -m1 "${CLUSTER_NAME}\.${BASE_DOM}") || true
test -z "$existing" || err "Found existing record in /etc/hosts: $existing" "(You can comment these out)"
ok

echo -n "====> Checking if first entry in resolv.conf is pointing locally: "
test "$(grep -m1 "^nameserver " /etc/resolv.conf | awk '{print $2}')" = "127.0.0.1" || \
    err "First entry in /etc/resolv.conf not pointing to 127.0.0.1"
ok

echo -n "====> Checking if DNS service (dnsmasq or NetworkManager) is active: "
if [ "$DNS_DIR" -ef "/etc/NetworkManager/dnsmasq.d" ]
then
    DNS_SVC="NetworkManager"; DNS_CMD="reload";
elif [ "$DNS_DIR" -ef "/etc/dnsmasq.d" ]
then
    DNS_SVC="dnsmasq"; DNS_CMD="restart";
else
    err "DNS_DIR (-z|--dns-dir), should be either /etc/dnsmasq.d or /etc/NetworkManager/dnsmasq.d"
fi
systemctl -q is-active $DNS_SVC || err "DNS_DIR points to $DNS_DIR but $DNS_SVC is not active"
ok

echo 
echo "#####################################################"
echo "### DOWNLOAD AND PREPARE OPENSHIFT 4 INSTALLATION ###"
echo "#####################################################"
echo

if [ -n "$VIR_NET" ]; then
    virsh net-uuid "${VIR_NET}" &> /dev/null || \
        err "${VIR_NET} doesn't exist"
elif [ -n "$VIR_NET_OCT" ]; then
    if [ "$VIR_NET_RECREATE" == "yes" ]; then
        virsh net-uuid "ocp-${VIR_NET_OCT}" &> /dev/null
        if [ "$?" == "0" ]; then
            check_if_we_can_continue "We will be deleting and recreating libvirt network ocp-${VIR_NET_OCT}"
            echo -n "====> Deleting libvirt network ocp-${VIR_NET_OCT}"
            virsh net-destroy "ocp-${VIR_NET_OCT}" || \
                err "virsh net-destroy ocp-${VIR_NET_OCT} failed"
            virsh net-undefine "ocp-${VIR_NET_OCT}" || \
                err "virsh net-undefine ocp-${VIR_NET_OCT} failed"
            ok
        fi
    fi
    echo -n "====> Creating libvirt network ocp-${VIR_NET_OCT}"
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
else
    err "Sorry, unhandled situation. Exiting"
fi


echo -n "====> Creating and using directory $SCRIPT_DIR: "
test -d "$SCRIPT_DIR" && err "Directory $SCRIPT_DIR already exists"
mkdir -p $SCRIPT_DIR && cd $SCRIPT_DIR || err "using $SCRIPT_DIR failed"
ok

echo -n "====> Generating SSH key to be injected in all VMs: "
ssh-keygen -f sshkey -q -N "" || err "ssh-keygen failed"
SSH_KEY="sshkey.pub"; ok

echo -n "====> Downloading OCP Client: "; download get "$CLIENT" "$CLIENT_URL";
echo -n "====> Downloading OCP Installer: "; download get "$INSTALLER" "$INSTALLER_URL";
tar -xf "${CACHE_DIR}/${CLIENT}" && rm -f README.md
tar -xf "${CACHE_DIR}/${INSTALLER}" && rm -f rm -f README.md

echo -n "====> Downloading RHCOS Image: "; download get "$IMAGE" "$IMAGE_URL";
echo -n "====> Downloading RHCOS Kernel: "; download get "$KERNEL" "$KERNEL_URL";
echo -n "====> Downloading RHCOS Initramfs: "; download get "$INITRAMFS" "$INITRAMFS_URL";

mkdir rhcos-install
cp "${CACHE_DIR}/${KERNEL}" "rhcos-install/vmlinuz"
cp "${CACHE_DIR}/${INITRAMFS}" "rhcos-install/initramfs.img"
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


echo "====> Creating ignition configs: "
./openshift-install create ignition-configs --dir=./install_dir || \
    err "./openshift-install create ignition-configs --dir=./install_dir failed"

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
echo "#################################"
echo "### CREATING LOAD BALANCER VM ###"
echo "#################################"
echo


echo -n "====> Downloading Centos 7 cloud image: "; download get "$LB_IMG" "$IMAGE_URL";

echo -n "====> Copying Image for Loadbalancer VM: "
cp "${CACHE_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" || \
    err "Copying '${VM_DIR}/CentOS-7-x86_64-GenericCloud.qcow2' to '${VM_DIR}/${CLUSTER_NAME}-lb.qcow2' failed"; ok

echo "====> Setting up Loadbalancer VM: "
virt-customize -a "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --uninstall cloud-init --ssh-inject root:file:$SSH_KEY --selinux-relabel --install haproxy --install bind-utils \
    --copy-in install_dir/bootstrap.ign:/opt/ --copy-in install_dir/master.ign:/opt/ --copy-in install_dir/worker.ign:/opt/ \
    --copy-in "${CACHE_DIR}/${IMAGE}":/opt/ --copy-in tmpws.service:/etc/systemd/system \
    --copy-in haproxy.cfg:/etc/haproxy/ \
    --run-command "systemctl daemon-reload" --run-command "systemctl enable tmpws.service" || \
    err "Setting up Loadbalancer VM image ${VM_DIR}/${CLUSTER_NAME}-lb.qcow2 failed"

echo -n "====> Creating Loadbalancer VM: "
virt-install --import --name ${CLUSTER_NAME}-lb --disk "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --memory 1024 --cpu host --vcpus 1 --os-type linux --os-variant rhel7-unknown --network network=${VIR_NET},model=virtio \
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

echo -n "====> Adding /etc/hosts entry for LB IP: "
    echo "$LBIP lb.${CLUSTER_NAME}.${BASE_DOM}" \
    "api.${CLUSTER_NAME}.${BASE_DOM}" \
    "api-int.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts; ok

echo -n "====> Waiting for SSH access on LB VM: "
ssh-keygen -R lb.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
ssh-keygen -R $LBIP  &> /dev/null || true
while true; do
    sleep 1
    ssh -i sshkey -o StrictHostKeyChecking=no lb.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
    break
done
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" true || err "SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; ok



echo 
echo "##################"
echo "#### DNS CHECK ###"
echo "##################"
echo 

echo -n "====> Adding test records in /etc/hosts: "
echo "1.2.3.4 xxxtestxxx.${BASE_DOM}" >> /etc/hosts
systemctl restart libvirtd || err "systemctl restart libvirtd"; ok
sleep 5

echo -n "====> Testing DNS forward record from LB: "
fwd_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig +short 'xxxtestxxx.${BASE_DOM}' 2> /dev/null")
test "$?" -eq "0" -a "$fwd_dig" = "1.2.3.4" || err "Testing DNS forward record failed ($fwd_dig)"; ok

echo -n "====> Testing DNS reverse record from LB: "
rev_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig +short -x '1.2.3.4' 2> /dev/null")
test "$?" -eq "0" -a "$rev_dig" = "xxxtestxxx.${BASE_DOM}." || err "Testing DNS reverse record failed ($rev_dig)"; ok

echo -n "====> Adding test SRV record in dnsmasq: "
echo "srv-host=xxxtestxxx.${BASE_DOM},yyyayyy.${BASE_DOM},2380,0,10" > ${DNS_DIR}/xxxtestxxx.conf
systemctl $DNS_CMD $DNS_SVC || err "systemctl $DNS_CMD $DNS_SVC failed"; ok

echo -n "====> Testing SRV record from LB: "
srv_dig=$(ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "dig srv +short 'xxxtestxxx.${BASE_DOM}' 2> /dev/null" | grep -q -s "yyyayyy.${BASE_DOM}") || \
    err "ERROR: Testing SRV record failed"; ok

echo -n "====> Cleaning up: "
sed -i "/1.2.3.4 xxxtestxxx.${BASE_DOM}/d" /etc/hosts || err "sed failed"
rm -f ${DNS_DIR}/xxxtestxxx.conf || err "rm failed"
systemctl $DNS_CMD $DNS_SVC || err "systemctl $DNS_CMD $DNS_SVC failed"; ok


echo 
echo "############################################"
echo "#### CREATE BOOTSTRAPING RHCOS/OCP NODES ###"
echo "############################################"
echo 


echo -n "====> Creating Boostrap VM: "
virt-install --name ${CLUSTER_NAME}-bootstrap \
  --disk "${VM_DIR}/${CLUSTER_NAME}-bootstrap.qcow2,size=50" --ram 16000 --cpu host --vcpus 4 \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/bootstrap.ign" > /dev/null || err "Creating boostrap vm failed"; ok

for i in $(seq 1 ${N_MAST})
do
echo -n "====> Creating Master-${i} VM: "
virt-install --name ${CLUSTER_NAME}-master-${i} \
--disk "${VM_DIR}/${CLUSTER_NAME}-master-${i}.qcow2,size=50" --ram 16000 --cpu host --vcpus 4 \
--os-type linux --os-variant rhel7-unknown \
--network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
--location rhcos-install/ \
--extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/master.ign" > /dev/null || err "Creating master-${i} vm failed "; ok
done

for i in $(seq 1 ${N_WORK})
do
echo -n "====> Creating Worker-${i} VM: "
  virt-install --name ${CLUSTER_NAME}-worker-${i} \
  --disk "${VM_DIR}/${CLUSTER_NAME}-worker-${i}.qcow2,size=50" --ram 8192 --cpu host --vcpus 4 \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIR_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/worker.ign" > /dev/null || err "Creating worker-${i} vm failed "; ok
done

echo "====> Waiting for RHCOS Installation to finish: "
while rvms=$(virsh list --name | grep "${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" 2> /dev/null); do
    sleep 15
    echo "  --> VMs with pending installation: $(echo "$rvms" | tr '\n' ' ')"
done

echo -n "====> Marking ${CLUSTER_NAME}.${BASE_DOM} as local domain in dnsmasq: "
echo "local=/${CLUSTER_NAME}.${BASE_DOM}/" > ${DNS_DIR}/${CLUSTER_NAME}.conf || err "failed"; ok

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
    IP=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
    test "$?" -eq "0" -a -n "$IP"  && { echo "$IP"; break; }
done
MAC=$(virsh domifaddr "${CLUSTER_NAME}-bootstrap" | grep ipv4 | head -n1 | awk '{print $2}')

echo -n "  ==> Adding DHCP reservation: "
virsh net-update ${VIR_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$IP'/>" --live --config > /dev/null || \
    err "Adding DHCP reservation failed"; ok

echo -n "  ==> Adding /etc/hosts entry: "
echo "$IP bootstrap.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts || err "failed"; ok


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

    echo -n "  ==> Adding /etc/hosts entry: "
    echo "$IP master-${i}.${CLUSTER_NAME}.${BASE_DOM}" \
         "etcd-$((i-1)).${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts || err "failed"; ok

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

    echo -n "  ==> Adding /etc/hosts entry: "
    echo "$IP worker-${i}.${CLUSTER_NAME}.${BASE_DOM}" >> /etc/hosts || err "failed"; ok
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



echo -n "====> Waiting for SSH access on Boostrap VM: "
ssh-keygen -R bootstrap.${CLUSTER_NAME}.${BASE_DOM} &> /dev/null || true
while true; do
    sleep 1
    ssh -i sshkey -o StrictHostKeyChecking=no core@bootstrap.${CLUSTER_NAME}.${BASE_DOM} true &> /dev/null || continue
    break
done
ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" true || err "SSH to lb.${CLUSTER_NAME}.${BASE_DOM} failed"; ok

export KUBECONFIG="install_dir/auth/kubeconfig"

echo "====> Waiting for Boostraping to finish: "
a_dones=()
a_conts=()
a_images=()
a_nodes=()
s_api="Down"
btk_started=0
no_output_counter=0
while true; do
    output_flag=0
    if [ "${s_api}" == "Down" ]; then
        ./oc get --raw / &> /dev/null && \
            { echo "  ==> Kubernetes API is Up"; s_api="Up"; output_flag=1; } || true
    else
        nodes=($(./oc get nodes | grep -v "^NAME" | awk '{print $1 "_" $2}' 2> /dev/null )) || true
        for n in ${nodes[@]}; do
            if [[ ! " ${a_nodes[@]} " =~ " ${n} " ]]; then
                echo "  --> Node $(echo $n | tr '_' ' ')"
                output_flag=1
                a_nodes+=( "${n}" )
            fi
        done
    fi
    images=($(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo podman images | grep -v '^REPOSITORY' | awk '{print \$1 \"-\" \$3}'" 2> /dev/null )) || true
    for i in ${images[@]}; do
        if [[ ! " ${a_images[@]} " =~ " ${i} " ]]; then
            echo "  --> Image Downloaded: ${i}"
            output_flag=1
            a_images+=( "${i}" )
        fi
    done
    dones=($(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "ls /opt/openshift/*.done 2> /dev/null" 2> /dev/null )) || true
    for d in ${dones[@]}; do
        if [[ ! " ${a_dones[@]} " =~ " ${d} " ]]; then
            echo "  --> Phase Completed: $(echo $d | sed 's/.*\/\(.*\)\.done/\1/')"
            output_flag=1
            a_dones+=( "${d}" )
        fi
    done
    conts=($(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo crictl ps -a | grep -v '^CONTAINER' | rev | awk '{print \$4 \"_\" \$2 \"_\" \$3}' | rev" 2> /dev/null)) || true
    for c in ${conts[@]}; do
        if [[ ! " ${a_conts[@]} " =~ " ${c} " ]]; then
            echo "  --> Container: $(echo $c | tr '_' ' ')"
            output_flag=1
            a_conts+=( "${c}" )
        fi
    done

    btk_stat=$(ssh -i sshkey "core@bootstrap.${CLUSTER_NAME}.${BASE_DOM}" "sudo systemctl is-active bootkube.service" 2> /dev/null) || true
    test "$btk_stat" = "active" -a "$btk_started" = "0" && btk_started=1 || true

    test "$output_flag" = "0" && no_output_counter=$(( $no_output_counter + 1 )) || no_output_counter=0

    test "$no_output_counter" -gt "8" && \
        { echo "  --> (bootkube.service is ${btk_stat}, Kube API is ${s_api})"; no_output_counter=0; }

    test "$btk_started" = "1" -a "$btk_stat" = "inactive" -a "$s_api" = "Down" && \
        { echo '[Warning] Some thing went wrong. Bootkube service wasnt able to bring up Kube API'; }
        
    test "$btk_stat" = "inactive" -a "$s_api" = "Up" && break

    sleep 15
    
done


./openshift-install --dir=install_dir wait-for bootstrap-complete


echo -n "====> Removing Boostrap VM: "
if [ -z "$KEEP_BS" ]; then
    virsh destroy ${CLUSTER_NAME}-bootstrap > /dev/null || err "virsh destroy ${CLUSTER_NAME}-bootstrap failed"
    virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage > /dev/null || err "virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage"; ok
else
    ok "skipping"
fi

echo -n "====> Removing Bootstrap from haproxy: "
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" \
    "sed -i '/bootstrap\.${CLUSTER_NAME}\.${BASE_DOM}/d' /etc/haproxy/haproxy.cfg" || err "failed"
ssh -i sshkey "lb.${CLUSTER_NAME}.${BASE_DOM}" "systemctl restart haproxy" || err "failed"; ok

echo -n "====> Waiting for configs.imageregistry: "
while true
do
    sleep 5
    ./oc get configs.imageregistry.operator.openshift.io cluster &> /dev/null && break || continue
done; ok

echo -n "====> Patching imageregistry to use emptyDir for storage: "
./oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}' || \
    err "Failed to patch configs.imageregistry.operator.openshift.io cluster";

echo "====> Waiting for clusterversion: "
while true
do
    sleep 30
    cv_prog_msg=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Progressing")].message}') || continue
    cv_avail=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Available")].status}') || continue
    echo "  $cv_prog_msg"
    test "$cv_avail" = "True" && break
done

END_TS=$(date +%s)
TIME_TAKEN="$(( ($END_TS - $START_TS) / 60 ))"

echo 
echo "######################################################"
echo "#### OPENSHIFT 4 INSTALLATION FINISHED SUCCESSFULLY###"
echo "######################################################"
echo "          time taken = $TIME_TAKEN minutes"
echo 

./openshift-install --dir=install_dir wait-for install-complete
