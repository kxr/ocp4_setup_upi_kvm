#!/bin/bash
# https://github.com/kxr/ocp4_setup_upi_kvm

###############################################################################
# .expose_loadbalancer.sh
# This will expose the OpenShift cluster load balancer via firewall port
# forward rules. Before you can run this script, you must have already
# successfully installed your OpenShift cluster via the
# ocp4-setup-upi-kvm.sh script.
###############################################################################

set -e

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
    -m|--method)
    EXPOSE_METHOD="$2"
    shift
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

if [ "$SHOW_HELP" == "yes" ]; then
echo
echo "Usage: ${0} --method [ firewalld | haproxy ]"
echo
cat << EOF | column -L -t -s '|' -N OPTION,DESCRIPTION -W DESCRIPTION

-m, --method NAME|Select the method with which you want to expose this cluster.
|Valid options are "firewalld" and "haproxy"
|<REQUIRED>

EOF
exit
fi

check_if_we_can_continue() {
    if [ "$YES" != "yes" ]; then
        echo;
        test -n "$1" && echo "[NOTE] $1"
        echo -n "Press enter to continue"; read x;
    fi
}

# Checking if we are root
test "$(whoami)" = "root" || err "Not running as root"

# Check if we have the --method set
test -n "$EXPOSE_METHOD" || \
    err "Please set the expose method using --method" \
        "Run:  '${0} --help' for details"

# Check if we have the required variables from env file
test -n "$CLUSTER_NAME" -a -n "$BASE_DOM" -a -n "$SETUP_DIR" -a -n "$VIR_NET" || \
    err "Unable to find existing cluster info"


# --method firewalld
if [ "$EXPOSE_METHOD" == "firewalld" ]; then

    # Checking if ip_forward is enabled
    echo -n "====> Checking if ip_forward is enabled: "
    IP_FWD=$(cat /proc/sys/net/ipv4/ip_forward)
    test "$IP_FWD" = "1" || \
        err "IP forwarding not enabled." "/proc/sys/net/ipv4/ip_forward has $IP_FWD"; ok

    # If method is firewall, firewall should be active
    echo -n "====> Checking if firewalld is active: "
    systemctl -q is-active firewalld || err "firewalld is not running"; ok

    # Check that we have the necessary firewall utility
    echo -n "====> Checking firewall-cmd: "
    test "$(which firewall-cmd)" || err "You do not have firewall-cmd in your PATH"; ok

    # Determine the interface
    echo -n "====> Determining the libvirt interface: "
    VIR_INT=$(virsh net-info ${VIR_NET} | grep Bridge | awk '{print $2}' 2> /dev/null) && \
    test -n "$VIR_INT" || \
        err "Unable to find interface for libvirt network"; ok

    # Checking if we have existing port forwarding
    echo -n "====> Checking if we have existing port forwarding: "
    EXIS_FWD=$(firewall-cmd --list-forward-ports | grep "^port=80:proto=tcp:\|^port=443:proto=tcp:\|^port=6443:proto=tcp:") || true
    test -z "$EXIS_FWD" || \
        {
            echo "Error"
            echo
            echo "# Existing port forwarding found which is conflicting"
            echo "# Please delete these rules:"
            echo
            for x in ${EXIS_FWD}; do
                echo "firewall-cmd --remove-forward-port='$x'"
            done
            echo "firewall-cmd --runtime-to-permanent"
            err ""
        }
    ok

    echo 
    echo "#######################"
    echo "### FIREWALLD RULES ###"
    echo "#######################"
    echo
    echo "# This script will now try to add the following firewalld rules"
    echo "# firewall-cmd will not be run using --permanent, to avoid permanent lockdown"
    echo "# To make the rules permanent you can run 'firewall-cmd --runtime-to-permanent'"
    echo "# You can also press Ctrl+C now and run these commands manually if you want any customization"
    echo
    echo "firewall-cmd --add-forward-port=port=443:proto=tcp:toaddr=${LBIP}:toport=443"
    echo "firewall-cmd --add-forward-port=port=6443:proto=tcp:toaddr=${LBIP}:toport=6443"
    echo "firewall-cmd --add-forward-port=port=80:proto=tcp:toaddr=${LBIP}:toport=80"
    echo "firewall-cmd --direct --passthrough ipv4 -I FORWARD -i ${VIR_INT} -j ACCEPT"
    echo "firewall-cmd --direct --passthrough ipv4 -I FORWARD -o ${VIR_INT} -j ACCEPT"
    echo 
    check_if_we_can_continue

    echo -n "====> Adding forward-port rule port=443:proto=tcp:toaddr=${LBIP}:toport=443: "
    firewall-cmd --add-forward-port=port=443:proto=tcp:toaddr=${LBIP}:toport=443 || echo "Failed"

    echo -n "====> Adding forward-port rule port=6443:proto=tcp:toaddr=${LBIP}:toport=6443: "
    firewall-cmd --add-forward-port=port=6443:proto=tcp:toaddr=${LBIP}:toport=6443 || echo "Failed"

    echo -n "====> Adding forward-port rule port=80:proto=tcp:toaddr=${LBIP}:toport=80: "
    firewall-cmd --add-forward-port=port=80:proto=tcp:toaddr=${LBIP}:toport=80 || echo "Failed"

    echo -n "====> Adding passthrough forwarding -I FORWARD -i ${VIR_INT}: "
    firewall-cmd --direct --passthrough ipv4 -I FORWARD -i ${VIR_INT} -j ACCEPT || echo "Failed"

    echo -n "====> Adding passthrough forwarding -I FORWARD -o ${VIR_INT}: "
    firewall-cmd --direct --passthrough ipv4 -I FORWARD -o ${VIR_INT} -j ACCEPT || echo "Failed"


# --method haproxy
elif [ "$EXPOSE_METHOD" == "haproxy" ]; then

    RANDSTRING=$(shuf -zer -n 4 {a..z} {0..9} | tr -d '\0')
    HAPROXY_CFG=/tmp/haproxy-${RANDSTRING}.cfg

cat <<EOF > ${HAPROXY_CFG}
    global
        log         127.0.0.1 local2
        chroot      /var/lib/haproxy
        pidfile     /var/run/haproxy.pid
        maxconn     4000
        user        haproxy
        group       haproxy
        daemon
        stats socket /var/lib/haproxy/stats
        ssl-default-bind-ciphers PROFILE=SYSTEM
        ssl-default-server-ciphers PROFILE=SYSTEM
    defaults
        log                     global
        option                  dontlognull
        option                  redispatch
        retries                 3
        timeout http-request    10s
        timeout queue           1m
        timeout connect         10s
        timeout client          1m
        timeout server          1m
        timeout http-keep-alive 10s
        timeout check           10s
        maxconn                 3000
    frontend fe-api
        bind *:6443
        mode tcp
        option tcplog
        tcp-request inspect-delay 10s
        tcp-request content accept if { req_ssl_hello_type 1 }
        use_backend ${CLUSTER_NAME}-api   if { req.ssl_sni -m end api.${CLUSTER_NAME}.${BASE_DOM} }
    frontend fe-https
        bind *:443
        mode tcp
        option tcplog
        tcp-request inspect-delay 10s
        tcp-request content accept if { req_ssl_hello_type 1 }
        use_backend ${CLUSTER_NAME}-https   if { req.ssl_sni -m end apps.${CLUSTER_NAME}.${BASE_DOM} }
    frontend fe-http
        bind *:80
        mode http
        option httplog
        use_backend ${CLUSTER_NAME}-http   if { hdr(host) -m end apps.${CLUSTER_NAME}.${BASE_DOM} }
    
    backend ${CLUSTER_NAME}-api
        balance source
        mode tcp
        option ssl-hello-chk
        server main lb.${CLUSTER_NAME}.${BASE_DOM}:6443
    backend ${CLUSTER_NAME}-https
        balance source
        mode tcp
        option ssl-hello-chk
        server main lb.${CLUSTER_NAME}.${BASE_DOM}:443
    backend ${CLUSTER_NAME}-http
        balance source
        mode http
        server main lb.${CLUSTER_NAME}.${BASE_DOM}:80
EOF

    echo
    echo "######################"
    echo "### HAPROXY CONFIG ###"
    echo "######################"
    echo
    echo "# haproxy configuration has been saved to: $HAPROXY_CFG Please review it before applying"
    echo "# To apply, simply move this config to haproxy. e.g:"
    echo 
    echo "      mv '$HAPROXY_CFG' '/etc/haproxy/haproxy.cfg'"
    echo 
    echo "# haproxy can be used to front multiple clusters. If that is the case,"
    echo "# you only need to merge the 'use_backend' lines and the 'backend' blocks from this confiugration in haproxy.cfg"
    echo
    echo "# You will also need to open the ports (80,443 and 6443) e.g:"
    echo
    echo "      firewall-cmd --add-service=http"
    echo "      firewall-cmd --add-service=https"
    echo "      firewall-cmd --add-port=6443/tcp"
    echo "      firewall-cmd --runtime-to-permanent"
    echo
    echo "# If SELinux is in Enforcing mode, you need to tell it to treat port 6443 as a webport, e.g:"
    echo
    echo "      semanage port -a -t http_port_t -p tcp 6443"
    echo
    echo


## TODO --method iptables
#elif [ "$EXPOSE_METHOD" == "iptables" ]; then
else
    err "Unkown method"
fi


echo
echo
echo "[NOTE]: When accessing this cluster from outside make sure that cluster FQDNs resolve from outside"
echo
echo "        For basic api/console access, the following /etc/hosts entry should work:"
echo
echo "        <IP-of-this-host> api.${CLUSTER_NAME}.${BASE_DOM} console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOM} oauth-openshift.apps.${CLUSTER_NAME}.${BASE_DOM}"
echo

exit 0
