#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

source "${__KUBE_KIT_DIR__}/library/partition.sh"

if [[ "${ENABLE_MASTER_STANDALONE_DEVICE,,}" == "true" ]]; then
    # if some hosts act as both master and node in kubernetes cluster
    if [[ "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY_LEN}" -gt 0 ]]; then
        role_name="pure-master"
        kube_master_ips="${KUBE_PURE_MASTER_IPS_ARRAY[*]}"
    else
        role_name="master"
        kube_master_ips="${KUBE_MASTER_IPS_ARRAY[*]}"
    fi

    if [[ -n "${kube_master_ips}" ]]; then
        LOG debug "Hosts will be partitioned as ${role_name}: ${kube_master_ips}"
        disk::partition \
            "${role_name}" \
            "${kube_master_ips// /,}" \
            "${KUBE_MASTER_STANDALONE_VG}" \
            "${KUBE_MASTER_DOCKER_LV},${KUBE_ETCD_LV},${KUBE_MASTER_LOG_LV}" \
            "${KUBE_MASTER_DOCKER_LV_RATIO},${KUBE_ETCD_LV_RATIO},${KUBE_MASTER_LOG_LV_RATIO}" \
            "${DOCKER_WORKDIR},${ETCD_WORKDIR},${KUBE_LOGS_DIR}"
    fi
fi

if [[ "${ENABLE_MASTER_STANDALONE_DEVICE,,}" == "true" && \
      "${ENABLE_NODE_STANDALONE_DEVICE,,}" == "true" && \
      "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY_LEN}" -gt 0 ]]; then
    master_docker_lv_ratio=$(python <<< "print(${KUBE_MASTER_DOCKER_LV_RATIO} * 0.75)")
    etcd_lv_ratio=$(python <<< "print(${KUBE_ETCD_LV_RATIO} * 0.75)")
    master_log_lv_ratio=$(python <<< "print(${KUBE_MASTER_LOG_LV_RATIO} * 0.75)")

    total_ratio=$(python <<< "print(${master_docker_lv_ratio} + ${etcd_lv_ratio} + ${master_log_lv_ratio})")
    master_kubelet_lv_ratio=$(python <<< "print((1 - ${total_ratio}) * 0.9)")

    role_name="master-node"
    kube_both_master_and_node_ips="${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY[*]}"
    LOG debug "Hosts will be partitioned as ${role_name}: ${kube_both_master_and_node_ips}"
    disk::partition \
        "${role_name}" \
        "${kube_both_master_and_node_ips// /,}" \
        "${KUBE_MASTER_STANDALONE_VG}" \
        "${KUBE_MASTER_DOCKER_LV},${KUBE_ETCD_LV},${KUBE_MASTER_LOG_LV},${KUBE_KUBELET_LV}" \
        "${master_docker_lv_ratio},${etcd_lv_ratio},${master_log_lv_ratio},${master_kubelet_lv_ratio}" \
        "${DOCKER_WORKDIR},${ETCD_WORKDIR},${KUBE_LOGS_DIR},${KUBELET_WORKDIR}"
fi

if [[ "${ENABLE_NODE_STANDALONE_DEVICE,,}" == "true" ]]; then
    # if some hosts act as both master and node in kubernetes cluster
    if [[ "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY_LEN}" -gt 0 ]]; then
        role_name="pure-node"
        kube_node_ips="${KUBE_PURE_NODE_IPS_ARRAY[*]}"
    else
        role_name="node"
        kube_node_ips="${KUBE_NODE_IPS_ARRAY[*]}"
    fi

    if [[ -n "${kube_node_ips}" ]]; then
        LOG debug "Hosts will be partitioned as ${role_name}: ${kube_node_ips}"
        disk::partition \
            "${role_name}" \
            "${kube_node_ips// /,}" \
            "${KUBE_NODE_STANDALONE_VG}" \
            "${KUBE_NODE_DOCKER_LV},${KUBE_KUBELET_LV},${KUBE_NODE_LOG_LV}" \
            "${KUBE_NODE_DOCKER_LV_RATIO},${KUBE_KUBELET_LV_RATIO},${KUBE_NODE_LOG_LV_RATIO}" \
            "${DOCKER_WORKDIR},${KUBELET_WORKDIR},${KUBE_LOGS_DIR}"
    fi
fi
