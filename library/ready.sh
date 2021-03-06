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
    if ! ready::etcd_cluster; then
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
                LOG error "There is NO binary files of kubernetes on ${master_ip}!"
                LOG info "Please execute './kube-kit init env' first!"
                return 2
                ;;
            2)
                LOG error "The version of kubectl on ${master_ip} is NOT equal to ${KUBE_VERSION}!"
                LOG info "Please execute './kube-kit init env' first!"
                return 3
                ;;
            3)
                LOG error "There is NO certifications on ${master_ip}!"
                LOG info "Please execute './kube-kit init cert' first!"
                return 4
                ;;
        esac
    done
}


function ready::node_env() {
    for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
        ssh::execute -h "${node_ip}" -- "
            if ! systemctl is-active docker.service -q; then
                exit 1
            elif ! kubectl get cs &>/dev/null; then
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
                LOG error "Docker daemon is NOT ready on ${node_ip}!"
                LOG info "Please execute './kube-kit deploy docker' first!"
                return 1
                ;;
            2)
                LOG error "Components of kubernetes master are not ready!"
                LOG info "Please execute './kube-kit deploy master' first!"
                return 2
                ;;
        esac
    done
}


function ready::all_nodes() {
    ready_nodes=$(kubectl get node 2>/dev/null | grep -wc 'Ready')
    ((ready_nodes == KUBE_NODE_IPS_ARRAY_LEN))
}


function ready::heketi() {
    curl "${HEKETI_SERVER}/hello" &>/dev/null
}


function ready::harbor_ui() {
    ui_pod=$(kubectl --namespace=harbor-system get pods \
                     --selector=k8s-app=ui 2>/dev/null |\
                     grep -oP '^ui-\S+')
    kubectl --namespace=harbor-system logs "${ui_pod}" 2>/dev/null |\
            grep -q "http server Running on http://:8080"
}


function ready::docker_login_harbor() {
    docker login -u admin -p "${HARBOR_ADMIN_PASSWORD}" \
           "${HARBOR_REGISTRY}" 2>/dev/null
}
