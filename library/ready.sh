#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216


function ready::etcd_certs() {
    for etcd_node_ip in "${ETCD_NODE_IPS_ARRAY[@]}"; do
        if ! ssh::execute -h "${etcd_node_ip}" -- "[[ -d ${KUBE_PKI_DIR} ]]"; then
            LOG error "You have NOT configurated certs for etcd to use https!"
            LOG info "Please execute './kube-kit init cert' first!"
            return 1
        fi
    done
}


function ready::etcd_cluster() {
    for etcd_node_ip in "${ETCD_NODE_IPS_ARRAY[@]}"; do
        ssh::execute -h "${etcd_node_ip}" -- "
            if [[ ! -f /usr/bin/etcdctl ]]; then
                exit 1
            elif ! ${ETCDCTL} cluster-health &>/dev/null; then
                exit 2
            else
                exit 0
            fi
        " | true
        case "${PIPESTATUS[0]}" in
            0)
                continue
                ;;
            1)
                LOG error "The etcd cluster has not been deployed!"
                LOG info "Please execute './kube-kit deploy etcd' first!"
                return 1
                ;;
            2)
                LOG error "The etcd cluster is not in ready status!"
                LOG info "Please check etcd cluser first!"
                return 2
                ;;
        esac
    done
}


function ready::flanneld() {
    for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
        ssh::execute -h "${node_ip}" -- "
            if [[ ! -f /usr/local/bin/flanneld ]]; then
                exit 1
            elif ! systemctl is-active flanneld.service -q; then
                exit 2
            else
                exit 0
            fi
        " | true
        case "${PIPESTATUS[0]}" in
            1)
                LOG error "flanneld on ${node_ip} is not installed!"
                LOG info "Please execute './kube-kit deploy flannel' first!"
                return 1
                ;;
            2)
                LOG error "flanneld on ${node_ip} is not in ready status!"
                LOG info "Please check flanneld on ${node_ip}!"
                return 2
                ;;
        esac
    done
}


function ready::master_env() {
    if ! etcd_cluster_ready; then
         return 1
    fi

    for master_ip in "${KUBE_MASTER_IPS_ARRAY[@]}"; do
        ssh::execute -h "${master_ip}" -- "
            if [[ ! -f /usr/local/bin/kubectl ]]; then
                exit 1
            fi

            current_version=\$(kubectl version --client --short | awk '{print \$3}')
            if [[ \${current_version} != ${KUBE_VERSION} ]]; then
                exit 2
            elif [[ ! -d ${KUBE_PKI_DIR} ]]; then
                exit 3
            else
                exit 0
            fi
        " | true
        case "${PIPESTATUS[0]}" in
            0)
                continue
                ;;
            1)
                LOG error "There is NO binary files of kubernetes on '${master_ip}'!"
                LOG info "Please execute './kube-kit init env' first!"
                return 2
                ;;
            2)
                LOG error "The version of kubectl on '${master_ip}' is NOT equal to '${KUBE_VERSION}'!"
                LOG info "Please execute './kube-kit init env' first!"
                return 3
                ;;
            3)
                LOG error "There is NO certifications on '${master_ip}'!"
                LOG info "Please execute './kube-kit init cert' first!"
                return 4
                ;;
        esac
    done
}


function ready::node_env() {
    for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
        ssh::execute -h "${node_ip}" -- "
            if [[ ! -f /usr/local/bin/kubectl ]]; then
                exit 1
            elif ! systemctl is-active docker.service --quiet; then
                exit 2
            else
                exit 0
            fi
        " | true
        case "${PIPESTATUS[0]}" in
            0)
                continue
                ;;
            1)
                LOG error "There is NO binary files of kubernetes on '${node_ip}'!"
                LOG info "Please execute './kube-kit init env' first!"
                return 1
                ;;
            2)
                LOG error "Docker daemon is NOT ready on '${node_ip}'!"
                LOG info "Please execute './kube-kit deploy docker' first!"
                return 2
                ;;
        esac
    done
}


function ready::coredns() {
    if ! kubectl --namespace kube-system get deployment coredns &>/dev/null; then
        LOG error "You have NOT deployed coredns, please execute './kube-kit deploy coredns' first!"
        return 1
    elif ! kubectl --namespace kube-system get pods | grep -qE '^coredns[a-z0-9-]+\s+1/1\s+Running'; then
        LOG error "kubends is NOT in ready status!"
        return 2
    fi
}


function ready::heapster() {
    for deployment in heapster influxdb-grafana; do
        if ! kubectl --namespace kube-system get deployment ${deployment} &>/dev/null; then
            LOG error "You have NOT deployed heapster, please execute './kube-kit deploy heapster' first!"
            return 1
        fi

        [[ ${deployment} == heapster ]] && pod_num='4/4' || pod_num='2/2'
        if ! kubectl --namespace kube-system get pods | grep -qE "^${deployment}[a-z0-9-]+\s+${pod_num}\s+Running"; then
            LOG error "${deployment} is NOT in ready status!"
            return 2
        fi
    done
}
