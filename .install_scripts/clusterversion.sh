#!/bin/bash

echo 
echo "#################################"
echo "#### OPENSHIFT CLUSTERVERSION ###"
echo "#################################"
echo 

echo "====> Waiting for clusterversion: "
ingress_patched=0
imgreg_patched=0
output_delay=0
nodes_total=$(( $N_MAST + $N_WORK ))
nodes_ready=0
while true
do
    cv_prog_msg=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Progressing")].message}' 2> /dev/null) || continue
    cv_avail=$(./oc get clusterversion -o jsonpath='{.items[*].status.conditions[?(.type=="Available")].status}' 2> /dev/null) || continue
    nodes_ready=$(./oc get nodes | grep 'Ready' | wc -l)

    if [ "$imgreg_patched" == "0" ]; then
        ./oc get configs.imageregistry.operator.openshift.io cluster &> /dev/null && \
       {
            sleep 30
            echo -n '  --> Patching image registry to use EmptyDir: ';
            ./oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}' 2> /dev/null && \
                imgreg_patched=1 || true
            sleep 30
            test "$imgreg_patched" -eq "1" && ./oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState": "Managed"}}' &> /dev/null || true
        } || true        
    fi

    if [ "$ingress_patched" == "0" ]; then
        ./oc get -n openshift-ingress-operator ingresscontroller default &> /dev/null && \
        {
            sleep 30
            echo -n '  --> Patching ingress controller to run router pods on master nodes: ';
            ./oc patch ingresscontroller default -n openshift-ingress-operator \
                --type merge \
                --patch '{
                    "spec":{
                        "replicas": '"${N_MAST}"',
                        "nodePlacement":{
                            "nodeSelector":{
                                "matchLabels":{
                                    "node-role.kubernetes.io/master":""
                                }
                            },
                            "tolerations":[{
                                "effect": "NoSchedule",
                                "operator": "Exists"
                            }]
                        }
                    }
                }' 2> /dev/null && ingress_patched=1 || true
        } || true
    fi

    for csr in $(./oc get csr 2> /dev/null | grep -w 'Pending' | awk '{print $1}'); do
        echo -n '  --> Approving CSR: ';
        ./oc adm certificate approve "$csr" 2> /dev/null || true
        output_delay=0
    done

    if [ "$output_delay" -gt 8 ]; then
        if [ "$cv_avail" == "True" ]; then
            echo "  --> Waiting for all nodes to ready. $nodes_ready/$nodes_total are ready."
        else
            echo -n "  --> ${cv_prog_msg:0:70}"; test -n "${cv_prog_msg:71}" && echo " ..." || echo
        fi
        output_delay=0
    fi

    test "$cv_avail" = "True" && test "$nodes_ready" -ge "$nodes_total" && break
    output_delay=$(( output_delay + 1 ))
    sleep 15
done

export END_TS=$(date +%s)
export TIME_TAKEN="$(( ($END_TS - $START_TS) / 60 ))"

echo 
echo "######################################################"
echo "#### OPENSHIFT 4 INSTALLATION FINISHED SUCCESSFULLY###"
echo "######################################################"
echo "          time taken = $TIME_TAKEN minutes"
echo 

./openshift-install --dir=install_dir wait-for install-complete

