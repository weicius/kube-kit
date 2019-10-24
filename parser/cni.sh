#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# *************** validate configurations of calico and flannel ****************
################################################################################

if [[ "${ENABLE_CNI_PLUGIN,,}" == "true" ]]; then
    if [[ "${KUBE_ALLOW_PRIVILEGED}" != "true" ]]; then
        LOG error "You have choosen to use CNI network plugin, so 'KUBE_ALLOW_PRIVILEGED' MUST be 'true'!"
        exit 131
    fi

    if [[ -n "${CALICO_NETWORK_GATEWAY}" ]]; then
        if ! [[ "${CALICO_NETWORK_GATEWAY}" =~ ^${IPV4_REGEX}$ ]]; then
            LOG error "CALICO_NETWORK_GATEWAY is configurated, but ${CALICO_NETWORK_GATEWAY}" \
                      "is NOT a valid ipv4 address!"
            exit 132
        elif util::element_in_array "${CALICO_NETWORK_GATEWAY}" "${KUBE_ALL_IPS_ARRAY[@]}"; then
            LOG error "CALICO_NETWORK_GATEWAY should NOT be within kubernetes cluster!"
            exit 133
        fi
    fi

    if [[ -z "${KUBE_KIT_CONTAINER_ID}" ]]; then
        ifcfg="/etc/sysconfig/network-scripts/ifcfg-${KUBE_KIT_NET_IFACE}"
        KUBE_KIT_GATEWAY=$(sed -nr 's|^GATEWAY\s*=\s*"?([0-9.]+)"?|\1|p' "${ifcfg}")
    else
        KUBE_KIT_GATEWAY=$(ip route | grep -oP "(?<=^default via )[0-9.]+(?= dev ${KUBE_KIT_NET_IFACE})")
    fi

    if [[ -z "${KUBE_KIT_GATEWAY}" && -z "${CALICO_NETWORK_GATEWAY}" ]]; then
        LOG error "Failed to get the gateway of the subnet of kubernetes cluster!" \
                  "You need to set the gateway of calico cluster (container network)" \
                  "via the variable CALICO_NETWORK_GATEWAY!"
        exit 134
    fi
else
    if [[ -n "${FLANNEL_NETWORK_GATEWAY}" ]]; then
        if ! [[ "${FLANNEL_NETWORK_GATEWAY}" =~ ^${IPV4_REGEX}$ ]]; then
            LOG error "FLANNEL_NETWORK_GATEWAY is configurated, but ${FLANNEL_NETWORK_GATEWAY}" \
                      "is NOT a valid ipv4 cidr address! "
            exit 135
        elif util::element_in_array "${FLANNEL_NETWORK_GATEWAY}" "${KUBE_ALL_IPS_ARRAY[@]}"; then
            LOG error "FLANNEL_NETWORK_GATEWAY should NOT be within kubernetes cluster!"
            exit 136
        fi
    fi
fi
