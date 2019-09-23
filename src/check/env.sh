#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


function check::networks() {
    current_ip="$(util::current_host_ip)"
    local -A gatewaymaps=(
        ["calico"]="${CALICO_NETWORK_GATEWAY}"
        ["flannel"]="${FLANNEL_NETWORK_GATEWAY}"
        ["glusterfs"]="${GLUSTERFS_NETWORK_GATEWAY}"
    )

    for component in "${!gatewaymaps[@]}"; do
        gateway="${gatewaymaps[${component}]}"
        [[ -z "${gateway}" ]] && continue
        LOG debug "Checking if the host ${current_ip} can ping the" \
                  "gateway ${gateway} of ${component} subnet ..."
        if ! util::can_ping "${gateway}"; then
            LOG error "The host ${current_ip} can NOT ping ${gateway}!"
            return 1
        fi
    done
}


function check::the_disk() {
    local disk="${1}"
    current_ip="$(util::current_host_ip)"

    # ensure the lvm2 package exists before using pvs command.
    rpm -qa | grep -q lvm2 || yum install lvm2 -y -q

    if ! lsblk "${disk}" &>/dev/null; then
        LOG error "The disk ${disk} on ${current_ip} does NOT exist!"
        return 1
    elif lsblk "${disk}" | grep -qP ' /(boot|home)?$'; then
        LOG error "The disk ${disk} on ${current_ip} has been used by CentOS itself!"
        return 2
    elif mount | grep -q "${disk}"; then
        LOG warn "The disk ${disk} on ${current_ip} has been mounted, will umount it!"
    elif pvs | grep -Eq "${disk}[0-9]?"; then
        LOG warn "The disk ${disk} on ${current_ip} has been used as a pv, will wipe it!"
    fi
}


function check::k8s_disks() {
    current_ip="$(util::current_host_ip)"
    check::the_disk "${KUBE_DISKS_ARRAY[${current_ip}]}"
}


function check::heketi_disks() {
    local heketi_node_ip=""
    current_ip="$(util::current_host_ip)"

    for ipaddr in $(hostname -I); do
        if util::element_in_array "${ipaddr}" "${HEKETI_NODE_IPS_ARRAY[@]}"; then
            heketi_node_ip="${ipaddr}"
            break
        fi
    done

    [[ -z "${heketi_node_ip}" ]] && return 0

    heketi_disks=(${HEKETI_DISKS_ARRAY[${heketi_node_ip}]})
    for heketi_disk in "${heketi_disks[@]}"; do
        LOG debug "Checking the device ${heketi_disk} for heketi on ${current_ip} ..."
        check::the_disk "${heketi_disk}"
    done
}
