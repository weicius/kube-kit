#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

if [[ "${#BASH_SOURCE[@]}" -ne 0 ]]; then
    __KUBE_KIT_DIR__=$(dirname "$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)")
    source "${__KUBE_KIT_DIR__}/library/logging.sh"
fi

readonly NUM_0_TO_255_REGEX="([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])"
readonly NUM_1_TO_32_REGEX="([1-9]|[1-2][0-9]|3[0-2])"
readonly NUM_16_TO_31_REGEX="(1[6-9]|2[0-9]|3[0-1])"
readonly NUM_16_TO_32_REGEX="(1[6-9]|2[0-9]|3[0-2])"
readonly NUM_0_TO_65535_REGEX="(6553[0-5]|655[0-2][0-9]|65[0-4][0-9]{2}|6[0-4][0-9]{3}|[1-5][0-9]{4}|[1-9][0-9]{1,3}|[0-9])"

# The complete regex which valid a IPV4 address:
# ^((([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]))$
readonly IPV4_REGEX="((${NUM_0_TO_255_REGEX}\.){3}${NUM_0_TO_255_REGEX})"
readonly IPV4_CIDR_REGEX="(${IPV4_REGEX}\/${NUM_1_TO_32_REGEX})"
readonly IPV4_PORT_REGEX="(${IPV4_REGEX}:${NUM_0_TO_65535_REGEX})"
readonly PRIVATE_IPV4_REGEX="((10|127)(\.${NUM_0_TO_255_REGEX}){3}|(172\.${NUM_16_TO_31_REGEX}|192\.168)(\.${NUM_0_TO_255_REGEX}){2})"
readonly PRIVATE_IPV4_CIDR_REGEX="(${PRIVATE_IPV4_REGEX}\/${NUM_16_TO_32_REGEX})"
readonly PRIVATE_IPV4_PORT_REGEX="(${PRIVATE_IPV4_REGEX}:${NUM_0_TO_65535_REGEX})"


# ipv4::cidr_prefix_to_netmask 20 => 255.255.240.0
function ipv4::cidr_prefix_to_netmask() {
    local prefix="${1}"
    local netmask=""

    for idx in $(seq 4); do
        if ((prefix >= 8)); then
            netmask+="255."
        elif ((prefix >= 0)); then
            netmask+="$((256 - 2 ** (8 - prefix)))."
        else
            netmask+="0."
        fi
        ((prefix -= 8))
    done

    echo -n "${netmask%.}"
}


function ipv4::bitwise_and() {
    local i1 i2 i3 i4
    local j1 j2 j3 j4
    IFS=. read -r i1 i2 i3 i4 <<< "${1}"
    IFS=. read -r j1 j2 j3 j4 <<< "${2}"
    printf "%d.%d.%d.%d" "$((i1 & j1))" "$((i2 & j2))" "$((i3 & j3))" "$((i4 & j4))"
}


# convert decimal number(0-255) to binary number(8 bit).
# ipv4::dec2bin 123 => 01111011
function ipv4::dec2bin() {
    local number="${1}"

    # matrix=({0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1}{0..1})
    local matrix=({0,1}{0,1}{0,1}{0,1}{0,1}{0,1}{0,1}{0,1})
    echo -n "${matrix[number]}"
}


# convert binary number(8 bit) to decimal number(0-255).
# ipv4::bin2dec 01111011 => 123
function ipv4::bin2dec() {
    echo -n "$((2#${1}))"
}


# convert ipv4 address to decimal.
# ipv4::ip2dec 192.168.138.111 => 3232270959
function ipv4::ip2dec() {
    local i1 i2 i3 i4
    IFS=. read -r i1 i2 i3 i4 <<< "${1}"
    # ip_bitwise=$(printf "%s%s%s%s" "$(ipv4::dec2bin ${i1})" "$(ipv4::dec2bin ${i2})" "$(ipv4::dec2bin ${i3})" "$(ipv4::dec2bin ${i4})")
    # echo -n "$(ipv4::bin2dec ${ip_bitwise})"
    echo -n "$((i1 * (2 ** 24) + i2 * (2 ** 16) + i3 * (2 ** 8) + i4))"
}


# convert decimal to ipv4 address.
# ipv4::dec2ip 3232270959 => 192.168.138.111
function ipv4::dec2ip() {
    local ip_dec="${1}"
    local ipaddr=""
    local factor=""

    for idx in $(seq 4); do
        # 2 ** 24, 2 ** 16, 2 ** 8, 2 ** 1
        factor="$((2 ** (8 * (4 - idx))))"
        ipaddr+="$((ip_dec / factor))."
        ((ip_dec %= factor))
    done

    echo -n "${ipaddr%.}"
}


# generate an array of all ips in an ip range:
# ipv4::ip_range_to_ip_array 1.1.1.1-1.1.1.4 => 1.1.1.1 1.1.1.2 1.1.1.3 1.1.1.4
function ipv4::ip_range_to_ip_array() {
    local start_ip end_ip
    IFS=\- read -r start_ip end_ip <<< "${1}"

    for ip in "${start_ip}" "${end_ip}"; do
        [[ "${ip}" =~ ^${IPV4_REGEX}$ ]] && continue
        LOG error "'${ip}' is NOT a valid ipv4 address!"
        return 1
    done

    local start_ip_dec end_ip_dec
    start_ip_dec=$(ipv4::ip2dec "${start_ip}")
    end_ip_dec=$(ipv4::ip2dec "${end_ip}")

    # 1.1.1.1-1.1.1.4 and 1.1.1.4-1.1.1.1 are the same.
    if [[ "${start_ip_dec}" -gt "${end_ip_dec}" ]]; then
        local tmp_ip="${start_ip}"
        local tmp_ip_dec="${start_ip_dec}"
        start_ip="${end_ip}"
        end_ip="${tmp_ip}"
        start_ip_dec="${end_ip_dec}"
        end_ip_dec="${tmp_ip_dec}"
    fi

    local -a ip_array
    for ((idx = 0; idx <= end_ip_dec - start_ip_dec; idx++)); do
        ip_array+=($(ipv4::dec2ip $((start_ip_dec + idx))))
    done

    echo -n "${ip_array[@]}"
}


# generate ip array from ip string, return ips or error messages.
# ipv4::ip_string_to_ip_array 10.20.30.1,10.20.30.11-10.20.30.15 =>
# 10.20.30.1 10.20.30.11 10.20.30.12 10.20.30.13 10.20.30.14 10.20.30.15
# ipv4::ip_string_to_ip_array 10.20.30.11-10.20.30.1515 (will fail) =>
# 10.20.30.11-10.20.30.1515 is neither a valid ipv4 address nor a valid ipv4 address range!
function ipv4::ip_string_to_ip_array() {
    local -a items=(${1//,/ })
    local -a ip_array

    for item in "${items[@]}"; do
        if [[ "${item}" =~ ^${IPV4_REGEX}$ ]]; then
            ip_array+=(${item})
        elif [[ "${item}" =~ ^${IPV4_REGEX}\-${IPV4_REGEX}$ ]]; then
            ip_array+=($(ipv4::ip_range_to_ip_array "${item}"))
        else
            LOG error "'${item}' is neither a valid ipv4 address" \
                      "nor a valid ipv4 address range!"
            return 1
        fi
    done

    # remove the duplicate ips of the array 'ip_array' and sort all ips.
    ip_array=($(tr " " "\n" <<< "${ip_array[@]}" |\
                sort -u -t '.' -k 1,1n -k 2,2n -k 3,3n -k 4,4n | tr "\n" " "))
    echo -n "${ip_array[@]}"
}


# ipv4::cidr_contains_ip 192.168.128.1/20 192.168.138.110 => return 0
# ipv4::cidr_contains_ip 192.168.128.1/20 192.168.118.110 => return 1
function ipv4::cidr_contains_ip() {
    IFS=\/ read -r netip prefix <<< "${1}"
    local ipaddr="${2}"

    netmask=$(ipv4::cidr_prefix_to_netmask "${prefix}")
    netip_mask=$(ipv4::bitwise_and "${netip}" "${netmask}")
    ipaddr_mask=$(ipv4::bitwise_and "${ipaddr}" "${netmask}")

    [[ "${netip_mask}" == "${ipaddr_mask}" ]]
}


# ipv4::cidrs_intersect 10.10.0.0/16 10.10.20.0/20 => return 0
# ipv4::cidrs_intersect 10.10.0.0/16 10.20.30.0/20 => return 1
function ipv4::cidrs_intersect() {
    IFS=\/ read -r netip1 prefix1 <<< "${1}"
    IFS=\/ read -r netip2 prefix2 <<< "${2}"

    prefix=$(python <<< "print min(${prefix1}, ${prefix2})")
    netmask=$(ipv4::cidr_prefix_to_netmask "${prefix}")
    netip1_mask=$(ipv4::bitwise_and "${netip1}" "${netmask}")
    netip2_mask=$(ipv4::bitwise_and "${netip2}" "${netmask}")

    [[ "${netip1_mask}" == "${netip2_mask}" ]]
}


# ipv4::two_ips_in_same_subnet 192.168.138.110 192.168.137.138 20 => return 0
# ipv4::two_ips_in_same_subnet 192.168.138.110 192.168.117.138 20 => return 1
function ipv4::two_ips_in_same_subnet() {
    local ip1="${1}"
    local ip2="${2}"

    netmask=$(ipv4::cidr_prefix_to_netmask "${3}")
    netip1_mask=$(ipv4::bitwise_and "${ip1}" "${netmask}")
    netip2_mask=$(ipv4::bitwise_and "${ip2}" "${netmask}")

    [[ "${netip1_mask}" == "${netip2_mask}" ]]
}
