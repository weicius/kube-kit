#!/usr/bin/env bash
# vim: nu:noai:ts=4

local_hosts_file="/tmp/hosts"

if [[ -z "${KUBE_MASTER_HOSTNAME_PREFIX}" || -z "${KUBE_NODE_HOSTNAME_PREFIX}" ]]; then
    LOG error "KUBE_MASTER_HOSTNAME_PREFIX or KUBE_NODE_HOSTNAME_PREFIX is empty!"
    exit 1
fi

cat > "${local_hosts_file}" <<EOF
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1       localhost localhost.localdomain localhost6 localhost6.localdomain6

${KUBE_MASTER_VIP} ${KUBE_MASTER_HOSTNAME_PREFIX%-}
EOF

for idx in "${!KUBE_MASTER_IPS_ARRAY[@]}"; do
    k8s_master_ip="${KUBE_MASTER_IPS_ARRAY[${idx}]}"
    k8s_master_name="${KUBE_MASTER_HOSTNAME_PREFIX}$((idx + 1))"

	cat >> "${local_hosts_file}" <<-EOF
	${k8s_master_ip} ${k8s_master_name}
	EOF

    ssh::execute -h "${k8s_master_ip}" -- "
        hostnamectl set-hostname ${k8s_master_name}
    "
done

for idx in "${!KUBE_NODE_IPS_ARRAY[@]}"; do
    k8s_node_ip="${KUBE_NODE_IPS_ARRAY[${idx}]}"
    k8s_node_name="${KUBE_NODE_HOSTNAME_PREFIX}$((idx + 1))"

	cat >> "${local_hosts_file}" <<-EOF
	${k8s_node_ip} ${k8s_node_name}
	EOF

    ssh::execute -h "${k8s_node_ip}" -- "
        hostnamectl set-hostname ${k8s_node_name}
    "
done

if [[ "${ENABLE_GLUSTERFS}" == "true" ]]; then
    for idx in "${!KUBE_NODE_IPS_ARRAY[@]}"; do
        k8s_node_ip="${KUBE_NODE_IPS_ARRAY[${idx}]}"
        # use the ip address for kubernetes cluster by default.
        glusterfs_node_ip="${k8s_node_ip}"
        glusterfs_node_name="${GLUSTERFS_NODE_NAME_PREFIX}$((idx + 1))"

        # get the ip address on the host to access GLUSTERFS_NETWORK_GATEWAY.
        if [[ -n "${GLUSTERFS_NETWORK_GATEWAY}" ]]; then
            glusterfs_node_ip=$(ssh::execute -h "${k8s_node_ip}" \
                                             -- "util::get_glusterfs_node_ip")
            if [[ -z "${glusterfs_node_ip}" ]]; then
                LOG error "Failed to get the ip address on host ${k8s_node_ip}" \
                          "to access ${GLUSTERFS_NETWORK_GATEWAY}!"
                exit 2
            fi
        fi

		cat >> "${local_hosts_file}" <<-EOF
		${glusterfs_node_ip} ${glusterfs_node_name}
		EOF
    done
fi

scp::execute_parallel -h "all" \
                      -s "${local_hosts_file}" \
                      -d "/etc/hosts"
