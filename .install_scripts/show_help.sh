#!/bin/bash
echo COLS=$COLUMNS
cat <<EOF | fmt -s -w ${COLS}

Usage: ${0} [OPTIONS]

Options:

-O, --ocp-version VERSION
    The OpenShift version to install.
    You can set this to "latest", "stable" or a specific version like "4.1", "4.1.2", "4.1.latest", "4.1.stable" etc.
    Default: ${OCP_VERSION}

-R, --rhcos-version VERSION
    The Red Hat CoreOS (RHCOS) Version to use.
    You can set a specific RHCOS version to use. For example "4.1.0", "4.2.latest" etc. By default the RHCOS version is matched from the OpenShift version. For example, if you selected 4.1.2  RHCOS 4.1/latest will be used.
    Default: ${RHCOS_VERSION}

-p, --pull-secret FILE
    Location of the pull secret file.
    You can download your pull secret from https://cloud.redhat.com/openshift/install/pull-secret.
    Default: ${PULL_SEC_F}

-c, --cluster-name NAME
    OpenShift 4 cluster name.
    This will be used to populate .metadata.name in the install-config.yaml file that will be used to install the cluster.
    Default: ${CLUSTER_NAME}

-d, --cluster-domain DOMAIN
    OpenShift 4 cluster base domain.
    This will be used to populate .baseDomain in the install-config.yaml file that will be used to install the cluster.
    Default: ${BASE_DOM}

-m, --masters N
    Number of master nodes to deploy.
    Default: ${N_MAST}

-w, --workers N
    Number of master nodes to deploy.
    Default: ${N_WORK}

--master-cpu N(vCPU)
    Number of vCPU cores to be used for master nodes/VMs.
    Default: ${MAS_CPU}

--master-mem SIZE(MB)
    Memory/RAM size (in MB) to be used for master nodes/VMs.
    Default: ${MAS_MEM}

--worker-cpu N(vCPU)
    Number of vCPU cores to be used for worker nodes/VMs.
    Default: ${WOR_CPU}

--worker-mem SIZE(MB)
    Memory/RAM size (in MB) to be used for worker nodes/VMs.
    Default: ${WOR_MEM}

--bootstrap-cpu N(vCPU)
    Number of vCPU cores to be used for bootstrap node/VM.
    Default: ${BTS_CPU}

--bootstrap-mem SIZE(MB)
    Memory/RAM size (in MB) to be used for bootstrap node/VM.
    Default: ${BTS_MEM}

--lb-cpu N(vCPU)
    Number of vCPU cores to be used for load-balancer VM.
    Default: ${LB_CPU}

--lb-mem SIZE(MB)
    Memory/RAM size (in MB) to be used for load-balancer VM.
    Default: ${LB_MEM}

-n, --libvirt-network NETWORK
    The libvirt network to use.
    Select this option if you want to use an existing libvirt network.
    The libvirt network should already exist. If you want the script to create a separate network for this installation see: -N, --libvirt-oct
    Default: ${DEF_LIBVIRT_NET}

-N, --libvirt-oct OCTET
    Subnet octet for a new libvirt network.
    Using this option, you can specify a 192.168.{OCTET}.0/24 subnet octet and this script will create a new libvirt network for the cluster.
    The libvirt network will be named ocp-{OCTET}. If the libvirt network ocp-{OCTET} already exists, it will be re-used.
    Default: ${VIR_NET_OCT}

-v, --vm-dir DIR
    The location where VM Disks will be stored.
    Default: ${VM_DIR}

-z, --dns-dir DIR
    Configuration directory of dnsmasq (dnsmasq.d)
    We expect the DNS on the host to be managed by dnsmasq. You can use NetworkMananger's built-in dnsmasq or use a separate dnsmasq running on the host.
    If you are using NetworkMananger's built-in dnsmasq, set this to "/etc/NetworkManager/dnsmasq.d"
    If you are running a separate dnsmasq on the host, set this to "/etc/dnsmasq.d"
    See https://github.com/kxr/ocp4_setup_upi_kvm/wiki/Setting-Up-DNS for more details.
    Default: ${DNS_DIR}

-s, --setup-dir DIR
    Path to the setup directory.
    This is the location where the script keeps all the files related to a single cluster installation. A separate setup directory is created for each cluster installed.
    Default: /root/ocp4_setup_{CLUSTER_NAME}

-x, --cache-dir DIR
    Path to cache directory.
    To avoid un-necessary downloads the script downloads the OpenShift/RHCOS files to a cache directory and reuse the files for future installs.
    You can force the script to download a fresh copy by using -X, --fresh-download.
    Default: ${CACHE_DIR}

--ssh-pub-key-file FILE
    Path to ssh public key file.
    This key will be injected in all VMs (cluster nodes and Load balancer)
    By default a new ssh key pair is generated in setup directory.
    Default: ${SSH_PUB_KEY_FILE}

-X, --fresh-download
    Flag to force download OpenShift/RHCOS files even if they exist in the cache directory.
    Default: $(test "${FRESH_DOWN}" = "yes" && echo "<set>" || echo "<not set>")

-k, --keep-bootstrap
    Flag to keep the bootstrap VM after the bootstrapping is completed.
    Set this if you want to keep the bootstrap VM post cluster installation. By default the script removes the bootstrap VM once the bootstraping is finished
    Default: $(test "${KEEP_BS}" = "yes" && echo "<set>" || echo "<not set>")

--autostart-vms
    Flag to set the cluster VMs to auto-start on reboot.
    Default: $(test "${AUTOSTART_VMS}" = "yes" && echo "<set>" || echo "<not set>")

-y, --yes
    Flag to assume yes/continue to all questions/checks.
    Set this for the script to be non-interactive and continue with out asking for confirmation
    Default: $(test "${YES}" = "yes" && echo "<set>" || echo "<not set>")

--destroy
    Flat to un-install/destroy the cluster.
    Set this if you want the script to destroy everything it created.
    Use this option with the same options you used to install the cluster.
    Be carefull this deletes the setup directory, VMs, DNS entries and also the libvirt network (if created by the script using -N)
    Default: $(test "${DESTROY}" = "yes" && echo "<set>" || echo "<not set>")

Note: The default values for all these options can be changed in the .defaults.sh file.

Examples:

# Deploy OpenShift 4.3.12 cluster
./ocp4_setup_upi_kvm.sh --ocp-version 4.3.12

# Deploy OpenShift 4.3.12 cluster with RHCOS 4.3.0
./ocp4_setup_upi_kvm.sh --ocp-version 4.3.12 --rhcos-version 4.3.0

# Deploy latest OpenShift version with pull secret from a custom location
./ocp4_setup_upi_kvm.sh --pull-secret /home/knaeem/Downloads/pull-secret --ocp-version latest

# Deploy OpenShift 4.2.latest with custom cluster name and domain
./ocp4_setup_upi_kvm.sh --cluster-name ocp43 --cluster-domain lab.test.com --ocp-version 4.2.latest

# Deploy OpenShift 4.2.stable on new libvirt network (192.168.155.0/24)
./ocp4_setup_upi_kvm.sh --ocp-version 4.2.stable --libvirt-oct 155

# Destory the already installed cluster
./ocp4_setup_upi_kvm.sh --cluster-name ocp43 --cluster-domain lab.test.com --destroy

EOF
