#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# ******** validate KUBE_MASTER_VIP, KUBE_MASTER_IPS and KUBE_NODE_IPS *********
################################################################################

if [[ -n "${KUBE_MASTER_VIP}" && \
      ! ("${KUBE_MASTER_VIP}" =~ ^${IPV4_REGEX}$) ]]; then
    LOG error "KUBE_MASTER_VIP is configurated, but '${KUBE_MASTER_VIP}'" \
              "is NOT a valid ipv4 address!"
    exit 101
fi

declare -a KUBE_MASTER_IPS_ARRAY
declare -a KUBE_NODE_IPS_ARRAY
declare -a KUBE_ALL_IPS_ARRAY
declare -a KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY
declare -a KUBE_PURE_MASTER_IPS_ARRAY
declare -a KUBE_PURE_NODE_IPS_ARRAY

KUBE_MASTER_IPS_ARRAY=($(ipv4::ip_string_to_ip_array "${KUBE_MASTER_IPS}"))
KUBE_NODE_IPS_ARRAY=($(ipv4::ip_string_to_ip_array "${KUBE_NODE_IPS}"))

for master_ip in "${KUBE_MASTER_IPS_ARRAY[@]}"; do
    for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
        if [[ "${master_ip}" == "${node_ip}" ]]; then
            KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY+=("${master_ip}")
        fi
    done
done

for master_ip in "${KUBE_MASTER_IPS_ARRAY[@]}"; do
    if ! util::element_in_array "${master_ip}" "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY[@]}"; then
        KUBE_PURE_MASTER_IPS_ARRAY+=("${master_ip}")
    fi
done

for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
    if ! util::element_in_array "${node_ip}" "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY[@]}"; then
        KUBE_PURE_NODE_IPS_ARRAY+=("${node_ip}")
    fi
done

KUBE_MASTER_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_MASTER_IPS_ARRAY[@]}"))
KUBE_NODE_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_NODE_IPS_ARRAY[@]}"))
KUBE_ALL_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_MASTER_IPS_ARRAY[@]}" "${KUBE_NODE_IPS_ARRAY[@]}"))
KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY[@]}"))
KUBE_PURE_MASTER_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_PURE_MASTER_IPS_ARRAY[@]}"))
KUBE_PURE_NODE_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_PURE_NODE_IPS_ARRAY[@]}"))

KUBE_MASTER_IPS_ARRAY_LEN="${#KUBE_MASTER_IPS_ARRAY[@]}"
KUBE_NODE_IPS_ARRAY_LEN="${#KUBE_NODE_IPS_ARRAY[@]}"
KUBE_ALL_IPS_ARRAY_LEN="${#KUBE_ALL_IPS_ARRAY[@]}"
KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY_LEN="${#KUBE_BOTH_MASTER_AND_NODE_IPS_ARRAY[@]}"
KUBE_PURE_MASTER_IPS_ARRAY_LEN="${#KUBE_PURE_MASTER_IPS_ARRAY[@]}"
KUBE_PURE_NODE_IPS_ARRAY_LEN="${#KUBE_PURE_NODE_IPS_ARRAY[@]}"

if [[ "$((KUBE_MASTER_IPS_ARRAY_LEN % 2))" -eq 0 ]]; then
    LOG error "KUBE_MASTER_IPS must contain odd ipv4 addresses! e.g. 1, 3, 5 ..."
    exit 102
fi

# KUBE_CIPHERS_ARRAY is the array to map each ipaddr to its root password in etc/cipher.ini
array_defination=$(util::parse_ini "${__KUBE_KIT_DIR__}/etc/cipher.ini")
eval "declare -A KUBE_CIPHERS_ARRAY=${array_defination}"

# for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
#     if ! util::can_ping "${k8s_ip}"; then
#         LOG error "The host '${k8s_ip}' is NOT active now!"
#         exit 103
#     elif ! util::can_ssh "${k8s_ip}"; then
#         LOG error "The root password of '${k8s_ip}' is NOT correct!"
#         exit 104
#     fi
# done

################################################################################
# *********** fetch the network, cidr, ipv4 address of kube-kit host ***********
################################################################################

# ip addr show | sed -nr 's|^[0-9]+:\s+([^@]*):.*|\1|p' | grep -vP '(lo|docker)'
for iface in $(ip addr show | grep -oP '(?<=\d:\s)[^\s@]+(?=:)' | grep -vP '(lo|docker)'); do
    ip addr show "${iface}" | grep -wq inet || continue
    # ip addr show "${iface}" | sed -nr 's|\s+inet\s+([0-9./]+)\s+brd.*|\1|p'
    ipaddr_prefix=$(ip addr show "${iface}" | grep -oP '(?<=inet\s)[0-9./]+(?=\sbrd)')
    [[ -z "${ipaddr_prefix}" ]] && continue
    # e.g. ipaddr_prefix: 192.168.138.111/20
    IFS=\/ read -r ipaddr prefix <<< "${ipaddr_prefix}"
    if ipv4::two_ips_in_same_subnet "${ipaddr}" "${KUBE_MASTER_IPS_ARRAY[0]}" "${prefix}"; then
        # e.g. eth0, 192.168.138.111, 20 and 255.255.240.0
        KUBE_KIT_NET_IFACE="${iface}"
        KUBE_KIT_NET_IPADDR="${ipaddr}"
        KUBE_KIT_NET_PREFIX="${prefix}"
        KUBE_KIT_NETMASK="$(ipv4::cidr_prefix_to_netmask ${prefix})"
        break
    fi
done

if [[ -z "${KUBE_KIT_NET_IPADDR}" || -z "${KUBE_KIT_NET_PREFIX}" ]]; then
    LOG error "Current host has NO ipaddr which is in the same subnet with kubernetes cluster!"
    exit 105
fi

# e.g. 192.168.128.0, 192.168.128.0/20 and 192.168.128.1
KUBE_KIT_NETWORK=$(ipv4::bitwise_and "${KUBE_KIT_NET_IPADDR}" "${KUBE_KIT_NETMASK}")
KUBE_KIT_SUBNET="${KUBE_KIT_NETWORK}/${KUBE_KIT_NET_PREFIX}"

# ensure all ips in KUBE_MASTER_IPS, KUBE_NODE_IPS and KUBE_MASTER_VIP are in the same subnet.
for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}" "${KUBE_MASTER_VIP}"; do
    if ! ipv4::two_ips_in_same_subnet "${k8s_ip}" \
        "${KUBE_KIT_NET_IPADDR}" "${KUBE_KIT_NET_PREFIX}"; then
        LOG error "The ip '${k8s_ip}' is NOT in the subnet ${KUBE_KIT_SUBNET}!"
        exit 106
    fi
done

################################################################################
# ****** validate KUBE_PODS_SUBNET, KUBE_SERVICES_SUBNET and relevant ips ******
################################################################################

if [[ ! ("${KUBE_PODS_SUBNET}" =~ ^${PRIVATE_IPV4_CIDR_REGEX}$) ]]; then
    LOG error "KUBE_PODS_SUBNET '${KUBE_PODS_SUBNET}'" \
              "is NOT a valid private ipv4 cidr address!"
    exit 107
elif [[ ! ("${KUBE_SERVICES_SUBNET}" =~ ^${PRIVATE_IPV4_CIDR_REGEX}$) ]]; then
    LOG error "KUBE_SERVICES_SUBNET '${KUBE_SERVICES_SUBNET}'" \
              "is NOT a valid private ipv4 cidr address!"
    exit 108
elif ipv4::cidrs_intersect "${KUBE_PODS_SUBNET}" "${KUBE_SERVICES_SUBNET}"; then
    LOG error "KUBE_PODS_SUBNET '${KUBE_PODS_SUBNET}' and" \
              "KUBE_SERVICES_SUBNET '${KUBE_SERVICES_SUBNET}' intersect!"
    exit 109
elif ipv4::cidrs_intersect "${KUBE_PODS_SUBNET}" "${KUBE_KIT_SUBNET}"; then
    LOG error "KUBE_PODS_SUBNET '${KUBE_PODS_SUBNET}' and" \
              "the subnet of Kubernetes cluster '${KUBE_KIT_SUBNET}' intersect!"
    exit 110
elif ipv4::cidrs_intersect "${KUBE_SERVICES_SUBNET}" "${KUBE_KIT_SUBNET}"; then
    LOG error "KUBE_SERVICES_SUBNET '${KUBE_SERVICES_SUBNET}' and" \
              "the subnet of Kubernetes cluster '${KUBE_KIT_SUBNET}' intersect!"
    exit 111
elif [[ ! ("${KUBE_KUBERNETES_SVC_IP}" =~ ^${PRIVATE_IPV4_REGEX}$) ]]; then
    LOG error "KUBE_KUBERNETES_SVC_IP '${KUBE_KUBERNETES_SVC_IP}'" \
              "is NOT a valid private ipv4 address!"
    exit 112
elif ! ipv4::cidr_contains_ip "${KUBE_SERVICES_SUBNET}" "${KUBE_KUBERNETES_SVC_IP}"; then
    LOG error "KUBE_KUBERNETES_SVC_IP '${KUBE_KUBERNETES_SVC_IP}'" \
              "is NOT in KUBE_SERVICES_SUBNET '${KUBE_SERVICES_SUBNET}'!"
    exit 113
elif [[ ! ("${KUBE_DNS_SVC_IP}" =~ ^${PRIVATE_IPV4_REGEX}$) ]]; then
    LOG error "KUBE_DNS_SVC_IP '${KUBE_DNS_SVC_IP}'" \
              "is NOT a valid private ipv4 address!"
    exit 114
elif ! ipv4::cidr_contains_ip "${KUBE_SERVICES_SUBNET}" "${KUBE_DNS_SVC_IP}"; then
    LOG error "KUBE_DNS_SVC_IP '${KUBE_DNS_SVC_IP}'" \
              "is NOT in KUBE_SERVICES_SUBNET '${KUBE_SERVICES_SUBNET}'!"
    exit 115
elif [[ "${KUBE_DNS_SVC_IP}" == "${KUBE_KUBERNETES_SVC_IP}" ]]; then
    LOG error "KUBE_DNS_SVC_IP and KUBE_KUBERNETES_SVC_IP can NOT be the same!"
    exit 116
fi

################################################################################
# ******** validate HA mode of kubernetes masters and relevant settings ********
################################################################################

if [[ "${KUBE_MASTER_IPS_ARRAY_LEN}" -gt 1 ]]; then
    if [[ -z "${KUBE_MASTER_VIP}" || -z "${KUBE_VIP_SECURE_PORT}" ]]; then
        LOG error "In HA mode, KUBE_MASTER_VIP and KUBE_VIP_SECURE_PORT are required!"
        exit 117
    elif [[ "${KUBE_VIP_SECURE_PORT}" -eq "${KUBE_APISERVER_SECURE_PORT}" ]]; then
        LOG error "In HA mode, KUBE_VIP_SECURE_PORT and KUBE_APISERVER_SECURE_PORT can NOT be the same!"
        exit 118
    fi
else
    # in non-HA mode, there is only ONE master, and we set it to KUBE_MASTER_VIP by force.
    # because we can use KUBE_MASTER_VIP to specify the host of kube-apiserver no matter using HA or not.
    KUBE_MASTER_VIP="${KUBE_MASTER_IPS_ARRAY[0]}"
    sed -i -r "s|^(KUBE_MASTER_VIP=).*|\1\"${KUBE_MASTER_VIP}\"|" "${__KUBE_KIT_DIR__}/etc/kube-kit.env"

    # in non-HA mode, set KUBE_VIP_SECURE_PORT to KUBE_APISERVER_SECURE_PORT by force.
    # because we can use KUBE_VIP_SECURE_PORT to specify the port of kube-apiserver no matter using HA or not.
    KUBE_VIP_SECURE_PORT="${KUBE_APISERVER_SECURE_PORT}"
    sed -i -r "s|^(KUBE_VIP_SECURE_PORT=).*|\1\"${KUBE_VIP_SECURE_PORT}\"|" "${__KUBE_KIT_DIR__}/etc/port.env"
fi

KUBE_SECURE_APISERVER="https://${KUBE_MASTER_VIP}:${KUBE_VIP_SECURE_PORT}"
KUBE_SECURE_API_ALLOWED_ALL_IPS_ARRAY=($(util::sort_uniq_array "${KUBE_MASTER_VIP}" "${KUBE_ALL_IPS_ARRAY[@]}"))

HARBOR_HOST="${KUBE_MASTER_VIP}"
HARBOR_REGISTRY="${HARBOR_HOST}:${KUBE_HARBOR_PORT}"
HARBOR_CLI=$(cat <<-EOF | sed -r 's/\s+/ /g'
	docker run --rm \
	           -e HARBOR_USERNAME=admin \
	           -e HARBOR_PASSWORD=${HARBOR_ADMIN_PASSWORD} \
	           -e HARBOR_PROJECT=1 \
	           -e HARBOR_URL=${HARBOR_REGISTRY} \
	           vmware/harbor-cli:${HARBOR_VERSION} \
	           harbor
	EOF
)

sed -i -r "s|^(HARBOR_REGISTRY).*|\1=\"${HARBOR_REGISTRY}\"|" "${__KUBE_KIT_DIR__}/etc/image.env"
