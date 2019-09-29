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


function check::distro() {
    local os_release="/etc/os-release"
    local redhat_release="/etc/redhat-release"
    current_ip="$(util::current_host_ip)"

    source "${os_release}"
    msg="The distro of ${current_ip} is <${PRETTY_NAME}>"
    err_msg="Tips: kube-kit only supports CentOS-${CENTOS_VERSION}!"
    if ! grep -iEq '(centos|rhel)' "${os_release}"; then
        LOG error "${msg}; ${err_msg}"
        return 1
    fi

    distro_version=$(awk '{print $4}' "${redhat_release}")
    msg+="; and release version is <${distro_version}>"
    if [[ "${distro_version}" =~ ^${CENTOS_VERSION}$ ]]; then
        msg+="; and kernel version is <$(uname -r)>"
        LOG debug "${msg}"
    else
        LOG error "${msg}; ${err_msg}"
        return 2
    fi
}


function check::ceph_mon_osd() {
    local ceph_mons=(${1//,/ })
    local ceph_osds=(${2//,/ })
    current_ip="$(util::current_host_ip)"

    for ceph_mon in "${ceph_mons[@]}"; do
        ceph_mon_ip="${ceph_mon%%:*}"
        # check if current node can ping current ceph monitor.
        if ! util::can_ping "${ceph_mon_ip}"; then
            LOG error "${current_ip} can NOT ping ceph monitor ${ceph_mon_ip}!"
            return 1
        fi
        # check if current node can connect to current ceph monitor service.
        if ! curl "${ceph_mon}" &>/dev/null; then
            LOG error "${current_ip} can NOT connect to ceph monitor ${ceph_mon}!"
            return 2
        fi
    done

    for ceph_osd in "${ceph_osds[@]}"; do
        ceph_osd_ip="${ceph_osd%%:*}"
        # check if current node can ping current ceph osd.
        if ! util::can_ping "${ceph_osd_ip}"; then
            LOG error "${current_ip} can NOT ping ceph osd ${ceph_osd_ip}!"
            return 3
        fi
        # check if current node can connect to current ceph osd service.
        if ! curl "${ceph_osd}" &>/dev/null; then
            LOG error "${current_ip} can NOT connect to ceph osd ${ceph_osd}!"
            return 4
        fi
    done
}
