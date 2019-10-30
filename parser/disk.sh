#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# *********** validate disks configurations for docker and glusterfs ***********
################################################################################

disk_device_regex="/dev/[a-z]{3}([0-9]+)?"
# KUBE_DISKS_ARRAY is the array to map each ipaddr to its disks for docker in etc/disk.ini
disk_ini="${__KUBE_KIT_DIR__}/etc/disk.ini"
array_defination=$(util::parse_ini "${disk_ini}")
eval "declare -A KUBE_DISKS_ARRAY=${array_defination}"

for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
    if [[ "${ENABLE_MASTER_STANDALONE_DEVICE,,}" != "true" ]]; then
        util::element_in_array "${k8s_ip}" "${KUBE_MASTER_IPS_ARRAY[@]}" && continue
    fi

    if [[ "${ENABLE_NODE_STANDALONE_DEVICE,,}" != "true" ]]; then
        util::element_in_array "${k8s_ip}" "${KUBE_NODE_IPS_ARRAY[@]}" && continue
    fi

    disks=(${KUBE_DISKS_ARRAY[${k8s_ip}]})
    if [[ "${#disks}" -eq 0 ]]; then
        LOG error "The disk for the host '${k8s_ip}' in ${disk_ini} is empty!"
        exit 141
    fi

    for disk in "${disks[@]}"; do
        [[ "${disk}" =~ ^${disk_device_regex}$ ]] && continue
        LOG error "The disk '${disk}' for '${k8s_ip}' is NOT valid disk device!" \
                  "Tips: the regex of disk device is '^${disk_device_regex}$'"
        exit 142
    done
done

if [[ "${ENABLE_GLUSTERFS,,}" == "true" ]]; then
    # HEKETI_DISKS_ARRAY is an array to map each ipaddr to its disks in etc/heketi.ini
    array_defination=$(util::parse_ini "${__KUBE_KIT_DIR__}/etc/heketi.ini")
    eval "declare -A HEKETI_DISKS_ARRAY=${array_defination}"

    # HEKETI_NODE_IPS_ARRAY is an array to keep all heketi node ips.
    declare -a HEKETI_NODE_IPS_ARRAY=(${!HEKETI_DISKS_ARRAY[@]})

    # NOTE: heketi_node_ip is in the kubernetes cluster subnet.
    for heketi_node_ip in "${HEKETI_NODE_IPS_ARRAY[@]}"; do
        if ! util::element_in_array "${heketi_node_ip}" "${KUBE_ALL_IPS_ARRAY[@]}"; then
            LOG error "The ipv4 address ${heketi_node_ip} for heketi is NOT in" \
                      "the kubernetes subnet ${KUBE_KIT_SUBNET}!"
            exit 143
        fi
    done

    heketi_nodes_num="${#HEKETI_DISKS_ARRAY[@]}"
    # for most situations, set the replicas of glusterfs volume to 3 is OK.
    GLUSTERFS_REPLICAS=3

    if [[ "${heketi_nodes_num}" -lt 2 ]]; then
        LOG error "You must offer at least 2 nodes for glusterfs cluster!"
        exit 144
    elif [[ "${heketi_nodes_num}" -eq 2 ]]; then
        GLUSTERFS_REPLICAS=2
    fi

    GLUSTERFS_DEFAULT_SC="glusterfs-replicate-${GLUSTERFS_REPLICAS}"
    GLUSTERFS_VOLUME_TYPE="replicate:${GLUSTERFS_REPLICAS}"
    HEKETI_SERVER="http://${KUBE_MASTER_VIP}:${KUBE_VIP_HEKETI_PORT}"
    HEKETI_CLI="${__KUBE_KIT_DIR__}/binaries/heketi/heketi-cli -s ${HEKETI_SERVER}"

    if [[ -n "${GLUSTERFS_NETWORK_GATEWAY}" ]]; then
        if ! [[ "${GLUSTERFS_NETWORK_GATEWAY}" =~ ^${IPV4_REGEX}$ ]]; then
            LOG error "GLUSTERFS_NETWORK_GATEWAY is configurated, but" \
                      "${GLUSTERFS_NETWORK_GATEWAY} is NOT a valid ipv4 address! "
            exit 145
        elif util::element_in_array "${GLUSTERFS_NETWORK_GATEWAY}" "${KUBE_ALL_IPS_ARRAY[@]}"; then
            LOG error "GLUSTERFS_NETWORK_GATEWAY should NOT be within kubernetes cluster!"
            exit 146
        fi
    fi
fi
