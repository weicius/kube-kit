#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207


function install_glusterfs() {
    current_ip="$(util::current_host_ip)"

    for dir in "${KUBE_SHARED_VOLUME_DIR}" \
               "${KUBE_SHARED_VOLUME_MNT_DIR}"; do
        [[ -d "${dir}" ]] || mkdir -p "${dir}"
    done

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
        if ! rpm -qa | grep -q centos-release-gluster; then
            yum install -y -q centos-release-gluster
        fi
    fi

    for pkg in glusterfs{,-{libs,server}}; do
        if ! rpm -qa | grep -q ${pkg}; then
            LOG debug "Installing ${pkg} on ${current_ip} ..."
            yum install -y -q ${pkg}
        fi
    done

    util::start_and_enable glusterd.service

    iptables -F && iptables -F -t nat
    iptables -X && iptables -X -t nat
}


function gluster_peer_probe() {
    for idx in $(seq ${KUBE_NODE_IPS_ARRAY_LEN}); do
        glusterfs_node="${GLUSTERFS_NODE_NAME_PREFIX}${idx}"
        gluster peer status | grep -q "${glusterfs_node}" && continue
        LOG debug "Adding ${glusterfs_node} into glusterfs cluster ..."
        gluster peer probe "${glusterfs_node}" >/dev/null
        util::sleep_random
    done
}


function init_shared_volume() {
    gluster volume info "${KUBE_SHARED_VOLUME_NAME}" &>/dev/null && return 0

    local -a replicas
    for idx in $(seq ${GLUSTERFS_REPLICAS}); do
        replicas+=("${GLUSTERFS_NODE_NAME_PREFIX}${idx}:${KUBE_SHARED_VOLUME_DIR}")
    done

    LOG info "Creating the shared volume ${KUBE_SHARED_VOLUME_NAME} ..."
    gluster volume create "${KUBE_SHARED_VOLUME_NAME}" \
            replica "${#replicas[@]}" \
            transport tcp "${replicas[@]}" \
            force

    LOG info "Starting the shared volume ${KUBE_SHARED_VOLUME_NAME} ..."
    gluster volume start "${KUBE_SHARED_VOLUME_NAME}"

    LOG info "Setting the capacity of ${KUBE_SHARED_VOLUME_NAME} to ${KUBE_SHARED_VOLUME_SIZE} ..."
    # ref: https://access.redhat.com/documentation/en-us/red_hat_gluster_storage/3.1/html/administration_guide/setting_limits
    gluster volume quota "${KUBE_SHARED_VOLUME_NAME}" enable
    gluster volume quota "${KUBE_SHARED_VOLUME_NAME}" limit-usage / "${KUBE_SHARED_VOLUME_SIZE}"
}


function mount_shared_volume() {
    idx=$(hostname | grep -oP "(?<=${KUBE_NODE_HOSTNAME_PREFIX})\d+")
    glusterfs_node="${GLUSTERFS_NODE_NAME_PREFIX}${idx}"

    mount | grep -q ${KUBE_SHARED_VOLUME_NAME} && return 0
    mount -t glusterfs \
          "${glusterfs_node}:${KUBE_SHARED_VOLUME_NAME}" \
          "${KUBE_SHARED_VOLUME_MNT_DIR}"
}
