#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2164,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/init/certificate.sh"
cfssl_dir="${__KUBE_KIT_DIR__}/binaries/cfssl/${CFSSL_VERSION}"

LOG title "Generating certification files using cfssl tools ..."

for exe in cfssl cfssljson cfssl-certinfo; do
    origin_exe="${exe}_linux-amd64"
    if [[ -f "/usr/local/bin/${exe}" ]]; then
        continue
    elif [[ -f "${cfssl_dir}/${origin_exe}" ]]; then
        LOG info "Copying ${exe} binary file to /usr/local/bin/${exe} ..."
        cp -f "${cfssl_dir}/${origin_exe}" "/usr/local/bin/${exe}"
    else
        LOG info "Downloading ${exe} binary files from https://pkg.cfssl.org ..."
        curl -L "https://pkg.cfssl.org/R${CFSSL_VERSION}/${origin_exe}" \
             -o "/usr/local/bin/${exe}"
    fi
    chmod +x "/usr/local/bin/${exe}"
done

scp::execute_parallel -h "all" \
                      -s "/usr/local/bin/cfssl" \
                      -s "/usr/local/bin/cfssljson" \
                      -s "/usr/local/bin/cfssl-certinfo" \
                      -d "/usr/local/bin/"

[[ -d "${KUBE_CONFIG_DIR}" ]] && rm -rf "${KUBE_CONFIG_DIR}"
mkdir -p "${KUBE_PKI_DIR}"

# ref:
# https://github.com/kubernetes-incubator/apiserver-builder-alpha/blob/master/docs/concepts/auth.md
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md
# NOTE: these two functions should be executed only ONCE locally.
function generate_ca_certificates() {
    cd "${KUBE_PKI_DIR}"
	cat > ca-config.json <<-EOF
	{
	    "signing": {
	        "default": {
	            "expiry": "${KUBE_PKI_EXPIRY}"
	        },
	        "profiles": {
	            "kubernetes": {
	                "usages": [
	                    "signing",
	                    "key encipherment",
	                    "server auth",
	                    "client auth"
	                ],
	                "expiry": "${KUBE_PKI_EXPIRY}"
	            }
	        }
	    }
	}
	EOF

	cat > ca-csr.json <<-EOF
	{
	    "CN": "kubernetes",
	    "key": {
	        "algo": "rsa",
	        "size": 4096
	    },
	    "names": [
	        {
	            "C": "${KUBE_PKI_COUNTRY}",
	            "ST": "${KUBE_PKI_STATE}",
	            "L": "${KUBE_PKI_LOCALITY}",
	            "O": "Kubernetes",
	            "OU": "CA"
	        }
	    ]
	}
	EOF

    LOG info "Generating the certificate and private key file for CA ..."
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

# Very important notes!!
# kube-apiserver will fetch CN (common_name) from the cert as the UserName of the request.
# kube-apiserver will fetch O (organization) from the cert as the ClusterRole of the request.
#
# ref: https://kubernetes.io/docs/reference/access-authn-authz/rbac/#core-component-roles
# kube-apiserver use the RBAC authorization to control the access to kubernetes resources,
# for each kubernetes core component (kube-controller-manager, kube-scheduler, kube-proxy,
# kubelet), kube-apiserver creates built-in ClusterRole and User, and a ClusterRoleBinding
# to bind the ClusterRole and User to control the access.
# so, the CN (common_name) must be the same with the name of built-in UserName, and the
# O (organization) must be the same with the name of built-in ClusterRole of this component.
#
# Component                ClusterRoleBinding              ClusterRole (O)                 User (CN)
# kube-controller-manager  system:kube-controller-manager  system:kube-controller-manager  system:kube-controller-manager
# kube-scheduler           system:kube-scheduler           system:kube-scheduler           system:kube-scheduler
# kube-proxy               system:node-proxier             system:node-proxier             system:kube-proxy
# kubelet-<nodeName>       system:nodes                    system:nodes                    system:node:<nodeName>
function generate_ssl_certificates() {
    if [[ "$#" -ne 3 ]]; then
        LOG error "$0 requires 3 arguments for service, common_name and organization"
        return 1
    fi

    local service="${1}"
    local common_name="${2}"
    local organization="${3}"
    local csr_file="${service}-csr.json"

    cd "${KUBE_PKI_DIR}"
	cat > "${csr_file}" <<-EOF
	{
	    "CN": "${common_name}",
	    "key": {
	        "algo": "rsa",
	        "size": 4096
	    },
	    "hosts": [
	        "${KUBE_KUBERNETES_SVC_IP}",
	        "${KUBE_DNS_SVC_IP}",
	        "127.0.0.1",
	        "kubernetes",
	        "kubernetes.default",
	        "kubernetes.default.svc",
	    ],
	    "names": [
	        {
	            "C": "${KUBE_PKI_COUNTRY}",
	            "ST": "${KUBE_PKI_STATE}",
	            "L": "${KUBE_PKI_LOCALITY}",
	            "O": "${organization}",
	            "OU": "Kubernetes"
	        }
	    ]
	}
	EOF

    # add all the ips of kube-master, kube-node and others with which user what to call k8s apis.
    for k8s_ip in "${KUBE_SECURE_API_ALLOWED_ALL_IPS_ARRAY[@]}"; do
        sed -i "/127.0.0.1/i\        \"${k8s_ip}\"," "${csr_file}"
    done

    # add all the hostnames of kube-node.
    for idx in $(seq ${KUBE_NODE_IPS_ARRAY_LEN} |tac); do
        sed -i "/127.0.0.1/a\        \"${KUBE_NODE_HOSTNAME_PREFIX}${idx}\"," "${csr_file}"
    done

    # add all the hostnames of kube-master.
    for idx in $(seq ${KUBE_MASTER_IPS_ARRAY_LEN} |tac); do
        sed -i "/127.0.0.1/a\        \"${KUBE_MASTER_HOSTNAME_PREFIX}${idx}\"," "${csr_file}"
    done

    local sub_domain_array=(${KUBE_DNS_DOMAIN//./ })
    # add all domains of services in this k8s cluster.
    local sub_domain_array_len=${#sub_domain_array[@]}
    for ((r_idx=${sub_domain_array_len}-1; r_idx>=0; r_idx--)); do
        sub_domain="kubernetes.default.svc"
        for ((sub_idx=0; sub_idx<=r_idx; sub_idx++)); do
            sub_domain+=".${sub_domain_array[${sub_idx}]}"
        done
        comma_or_null=$([[ ${r_idx} -eq ${sub_domain_array_len}-1 ]] && echo -n "" || echo -n ",")
        sed -i "/\"kubernetes.default.svc\",/a\        \"${sub_domain}\"${comma_or_null}" "${csr_file}"
    done

    LOG info "Generating the client certificate and private key file for ${service} ..."
    cfssl gencert \
          -ca=ca.pem \
          -ca-key=ca-key.pem \
          -config=ca-config.json \
          -profile=kubernetes \
          "${csr_file}" | cfssljson -bare "${service}"
}

######################################################################
########### Generate Certificates for Certificate Authority ##########
######################################################################

generate_ca_certificates

######################################################################
##### Generate TLS Certificates for Kubernetes-Releated Services #####
######################################################################

for svc in etcd docker; do
    generate_ssl_certificates "${svc}" "${svc}" "${svc}"
done

for svc in kube-{apiserver,controller-manager,scheduler}; do
    # NOTE: kube-apiserver doesn't need to use system:kube-apiserver as CN
    # and system:kube-apiserver as organization, just to unify the forms.
    generate_ssl_certificates "${svc}" "system:${svc}" "system:${svc}"
done

# NOTE: kube-proxy is different from other kubernetes components.
generate_ssl_certificates kube-proxy system:kube-proxy system:node-proxier

# generate the admin client certificate and private key.
# ref: https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles
generate_ssl_certificates admin admin system:masters

# the kube-controller-manager leverages a key pair to generate and sign service
# account tokens as describe in the managing service accounts documentation.
generate_ssl_certificates service-account service-accounts kubernetes

######################################################################
######## Distribute all the TLS Certificates to All the Hosts ########
######################################################################

function distribute_certs() {
    for current_ip in $(hostname -I); do
        if [[ "${HOST}" == "${current_ip}" ]]; then
            # jump over the current node.
            return 0
        fi
    done

    ssh::execute -h "${HOST}" -- "
        rm -rf ${KUBE_CONFIG_DIR}
        mkdir -p ${KUBE_CONFIG_DIR}
    "

    scp::execute -h "${HOST}" \
                 -s "${KUBE_PKI_DIR}" \
                 -d "${KUBE_CONFIG_DIR}"
}

LOG info "Distributing all the TLS certificates to all machines ..."
local::execute_parallel -h all -f distribute_certs -p 5

######################################################################
######## Generate the kubelet client certificate for each node #######
######################################################################

for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
    ssh::execute -h "${node_ip}" \
                 -s "${functions_file}" \
                 -- "generate_certs_for_kubelet"
done
