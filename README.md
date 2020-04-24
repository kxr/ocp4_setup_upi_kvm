# OpenShift 4 Automated Cluster Installation (UPI on KVM) Script

### Prerequistes:

- Internet connected physical host running a modern linux distribution
- Virtualization enabled and Libvirt/KVM setup
- DNS on the host managed by dnsmasq or NetworkManager/dnsmasq
- OpenShift 4 Pull secret

### Demo:

[![asciicast](https://asciinema.org/a/bw6Wja2vBLrAkpKHTV0yGeuzo.svg)](https://asciinema.org/a/bw6Wja2vBLrAkpKHTV0yGeuzo)

### Usage:
./ocp4_setup_upi_kvm.sh [OPTIONS]


| Option  |Description   |
| :------------ | :------------ |
|______________________________||
| -O, --ocp-version VERSION | You can set this to "latest", "stable" or a specific version like "4.1", "4.1.2", "4.1.latest", "4.1.stable" etc.<br>Default: stable |
| -R, --rhcos-version VERSION | You can set a specific RHCOS version to use. For example "4.1.0", "4.2.latest" etc.<br>By default the RHCOS version is matched from the OpenShift version. For example, if you selected 4.1.2  RHCOS 4.1/latest will be used |
| -p, --pull-secret FILE | Location of the pull secret file<br>Default: /root/pull-secret |
| -c, --cluster-name NAME | OpenShift 4 cluster name<br>Default: ocp4 |
| -d, --cluster-domain DOMAIN | OpenShift 4 cluster domain<br>Default: local |
| -m, --masters N | Number of masters to deploy<br>Default: 3 |
| -w, --worker N | Number of workers to deploy<br>Default: 2 |
| -n, --libvirt-network NETWORK | The libvirt network to use. Select this option if you want to use an existing libvirt network<br>The libvirt network should already exist. If you want the script to create a separate network for this installation see: -N, --libvirt-oct<br>Default: default |
| -N, --libvirt-oct OCTET | You can specify a 192.168.{OCTET}.0 subnet octet and this script will create a new libvirt network for the cluster<br>The network will be named ocp-{OCTET}. If the libvirt network ocp-{OCTET} already exists, the script will fail unless --libvirt-network-recreate is specified<br>Default: [not set] |
| -v, --vm-dir | The location where you want to store the VM Disks<br>Default: /var/lib/libvirt/images |
| -z, --dns-dir DIR | We expect the DNS on the host to be managed by dnsmasq. You can use NetworkMananger's built-in dnsmasq or use a separate dnsmasq running on the host. If you are running a separate dnsmasq on the host, set this to "/etc/dnsmasq.d"<br>Default: /etc/NetworkManager/dnsmasq.d |
| -s, --script-dir DIR | The location where we the script keeps all the files related to the installation<br>Default: /root/ocp4\_setup\_{CLUSTER_NAME} |
| -x, --cache-dir DIR | To avoid un-necessary downloads we download the OpenShift/RHCOS files to a cache directory and reuse the files if they exist<br>This way you only download a file once and reuse them for future installs<br>You can force the script to download a fresh copy by using -X, --fresh-download<br>Default: /root/ocp4_downloads |
| -X, --fresh-download | Set this if you want to force the script to download a fresh copy of the files instead of reusing the existing ones in cache dir<br>Default: [not set] |
| -k, --keep-bootstrap | Set this if you want to keep the bootstrap VM. By default bootstrap VM is removed once the bootstraping is finished<br>Default: [not set] |
| -y, --yes | Set this for the script to be non-interactive and continue with out asking for confirmation<br>Default: [not set] |
| --destroy | Set this if you want the script to destroy everything it has created<br>Use this option with the same options you used to install the cluster<br>Be carefull this deletes the VMs, DNS entries and the libvirt network (if created by the script)<br>Default: [not set] |


### Examples
    # Deploy OpenShift 4.3.12 cluster
    ./ocp4_setup_upi_kvm.sh --ocp-version 4.3.12
    ./ocp4_setup_upi_kvm.sh -O 4.3.12

    # Deploy OpenShift 4.3.12 cluster with RHCOS 4.3.0
    ./ocp4_setup_upi_kvm.sh --ocp-version 4.3.12 --rhcos-version 4.3.0
    ./ocp4_setup_upi_kvm.sh -O 4.3.12 -R 4.3.0

    # Deploy latest OpenShift version with pull secret from a custom location
    ./ocp4_setup_upi_kvm.sh --pull-secret /home/knaeem/Downloads/pull-secret --ocp-version latest
    ./ocp4_setup_upi_kvm.sh -p /home/knaeem/Downloads/pull-secret -O latest

    # Deploy OpenShift 4.2.latest with custom cluster name and domain
    ./ocp4_setup_upi_kvm.sh --cluster-name ocp43 --cluster-domain lab.test.com --ocp-version 4.2.latest
    ./ocp4_setup_upi_kvm.sh -c ocp43 -d lab.test.com -O 4.2.latest

    # Deploy OpenShift 4.2.stable on new libvirt network (192.168.155.0/24)
    ./ocp4_setup_upi_kvm.sh --ocp-version 4.2.stable --libvirt-oct 155
    ./ocp4_setup_upi_kvm.sh -O 4.2.stable -N 155

    # Destory the already installed cluster
    ./ocp4_setup_upi_kvm.sh --cluster-name ocp43 --cluster-domain lab.test.com --destroy
    ./ocp4_setup_upi_kvm.sh -c ocp43 -d lab.test.com --destroy
