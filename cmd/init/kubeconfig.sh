#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/init/certificate.sh"

# Kubernetes stores a variety of data including cluster state,
# application configurations, and secrets. Kubernetes supports
# the ability to encrypt cluster data at rest.
# ref:
# https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data
# https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#understanding-the-encryption-at-rest-configuration

LOG title "Generating the data encryption config and key ..."

cat > "${KUBE_CONFIG_DIR}/encryption-config.yaml" <<EOF
apiVersion: v1
kind: EncryptionConfig
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: $(head -c 32 /dev/urandom | base64)
  - identity: {}
EOF

######################################################################
####### Generate the kubeconfig file for Kubernetes components #######
######################################################################

for component in kube-controller-manager kube-scheduler kube-proxy; do
    kubeconfig="${KUBE_CONFIG_DIR}/${component}.kubeconfig"
    LOG info "Generating the kubeconfig file for ${component} ..."

    kubectl config set-cluster "${KUBE_CLUSTER_NAME}" \
            --embed-certs=true \
            --certificate-authority="${KUBE_PKI_DIR}/ca.pem" \
            --server="${KUBE_SECURE_APISERVER}" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config set-credentials "system:${component}" \
            --embed-certs=true \
            --client-certificate="${KUBE_PKI_DIR}/${component}.pem" \
            --client-key="${KUBE_PKI_DIR}/${component}-key.pem" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config set-context default \
            --cluster="${KUBE_CLUSTER_NAME}" \
            --user="system:${component}" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config use-context default --kubeconfig="${kubeconfig}"
done

##########################################################################
## Generate the kubeconfig file for Kubernetes admin user using kubectl ##
##########################################################################

admin_kubeconfig="${KUBE_CONFIG_DIR}/admin.kubeconfig"
LOG info "Generating the kubeconfig file for user admin ..."

kubectl config set-cluster "${KUBE_CLUSTER_NAME}" \
        --embed-certs=true \
        --certificate-authority="${KUBE_PKI_DIR}/ca.pem" \
        --server="${KUBE_SECURE_APISERVER}" \
        --kubeconfig="${admin_kubeconfig}"

util::sleep_random 0.5 1

kubectl config set-credentials admin \
        --embed-certs=true \
        --client-certificate="${KUBE_PKI_DIR}/admin.pem" \
        --client-key="${KUBE_PKI_DIR}/admin-key.pem" \
        --kubeconfig="${admin_kubeconfig}"

util::sleep_random 0.5 1

kubectl config set-context default \
        --cluster="${KUBE_CLUSTER_NAME}" \
        --user=admin \
        --kubeconfig="${admin_kubeconfig}"

util::sleep_random 0.5 1

kubectl config use-context default --kubeconfig="${admin_kubeconfig}"

######################################################################
######### Distribute the kubeconfig files to relevant hosts ##########
######################################################################

LOG info "Distributing the kubeconfig files to all masters ..."
scp::execute_parallel -h "master" \
                      -s "${admin_kubeconfig}" \
                      -s "${KUBE_CONFIG_DIR}/kube-controller-manager.kubeconfig" \
                      -s "${KUBE_CONFIG_DIR}/kube-scheduler.kubeconfig" \
                      -s "${KUBE_CONFIG_DIR}/encryption-config.yaml" \
                      -d "${KUBE_CONFIG_DIR}"

LOG info "Distributing the kubeconfig files to all nodes ..."
scp::execute_parallel -h "node" \
                      -s "${admin_kubeconfig}" \
                      -s "${KUBE_CONFIG_DIR}/kube-proxy.kubeconfig" \
                      -d "${KUBE_CONFIG_DIR}"

######################################################################
####### Generate the kubeconfig file for kubelet on each node ########
######################################################################

for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
    ssh::execute -h "${node_ip}" \
                 -s "${functions_file}" \
                 -- "generate_kubeconfig_for_kubelet"
done

######################################################################
######## Generate the kubeconfig file for kubectl on each node #######
######################################################################

for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
    ssh::execute -h "${k8s_ip}" \
                 -s "${functions_file}" \
                 -- "generate_kubeconfig_for_kubectl"
done

scp::execute -r \
             -h "${KUBE_ALL_IPS_ARRAY[0]}" \
             -s "/root/.kube/config" \
             -d "/root/.kube/config"
