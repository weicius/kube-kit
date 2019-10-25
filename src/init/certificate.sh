#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2164,SC2206,SC2207

# Kubernetes uses a special-purpose authorization mode called Node Authorizer, that specifically
# authorizes API requests made by Kubelets. In order to be authorized by the Node Authorizer,
# Kubelets must use a credential that identifies them as being in the system:nodes group,
# with a username of system:node:<nodeName>.
# So, we create a certificate for each Kubernetes node that meets the Node Authorizer requirements.

function generate_certs_for_kubelet() {
    current_ip="$(util::current_host_ip)"
    hostname="$(hostname)"

    cd "${KUBE_PKI_DIR}"
	cat > kubelet-${hostname}.json <<-EOF
	{
	    "CN": "system:node:${hostname}",
	    "hosts": [
	        "${hostname}",
	        "${current_ip}"
	    ],
	    "key": {
	        "algo": "rsa",
	        "size": ${KUBE_PKI_KEY_BITS}
	    },
	    "names": [
	        {
	            "C": "${KUBE_PKI_COUNTRY}",
	            "ST": "${KUBE_PKI_STATE}",
	            "L": "${KUBE_PKI_LOCALITY}",
	            "O": "system:nodes",
	            "OU": "Kubernetes"
	        }
	    ]
	}
	EOF

    LOG info "Generating the client certificate and private key file for kubelet on ${current_ip} ..."
    cfssl gencert \
          -ca=ca.pem \
          -ca-key=ca-key.pem \
          -config=ca-config.json \
          -profile=kubernetes \
          kubelet-${hostname}.json | cfssljson -bare kubelet-${hostname}
}


# When generating kubeconfig files for Kubelets, the client certificate matching the Kubelet's
# node name must be used. This will ensure Kubelets are properly authorized by the Kubernetes
# Node Authorizer (ref: https://kubernetes.io/docs/admin/authorization/node/).

function generate_kubeconfig_for_kubelet() {
    current_ip="$(util::current_host_ip)"
    hostname="$(hostname)"
    kubeconfig="${KUBE_CONFIG_DIR%/}/kubelet-${hostname}.kubeconfig"

    LOG info "Generating the kubeconfig file for kubelet on ${current_ip} ..."

    kubectl config set-cluster "${KUBE_CLUSTER_NAME}" \
            --embed-certs=true \
            --certificate-authority="${KUBE_PKI_DIR%/}/ca.pem" \
            --server="${KUBE_SECURE_APISERVER}" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config set-credentials "system:node:${hostname}" \
            --embed-certs=true \
            --client-certificate="${KUBE_PKI_DIR%/}/kubelet-${hostname}.pem" \
            --client-key="${KUBE_PKI_DIR%/}/kubelet-${hostname}-key.pem" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config set-context default \
            --cluster="${KUBE_CLUSTER_NAME}" \
            --user="system:node:${hostname}" \
            --kubeconfig="${kubeconfig}"

    util::sleep_random 0.5 1

    kubectl config use-context default --kubeconfig="${kubeconfig}"
}


function generate_kubeconfig_for_kubectl() {
    current_ip="$(util::current_host_ip)"

    rm -rf /root/.kube

    LOG info "Generating the kubeconfig file for kubectl on ${current_ip} ..."

    kubectl config set-cluster "${KUBE_CLUSTER_NAME}" \
            --embed-certs=true \
            --certificate-authority="${KUBE_PKI_DIR%/}/ca.pem" \
            --server="${KUBE_SECURE_APISERVER}"

    util::sleep_random 0.5 1

    kubectl config set-credentials admin \
            --embed-certs=true \
            --client-certificate="${KUBE_PKI_DIR%/}/admin.pem" \
            --client-key="${KUBE_PKI_DIR%/}/admin-key.pem"

    util::sleep_random 0.5 1

    kubectl config set-context "${KUBE_CLUSTER_NAME}" \
            --cluster="${KUBE_CLUSTER_NAME}" \
            --user=admin

    util::sleep_random 0.5 1

    kubectl config use-context "${KUBE_CLUSTER_NAME}"
}
