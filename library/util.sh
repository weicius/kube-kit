#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1083,SC1090,SC2034,SC2206,SC2207

# note: this function returns an array's defination.
# e.g. ret_str="$(util::parse_ini /path/to/ini/file)"
# ret_str's content (including the single quotes) is
# '([10.10.10.11]="r00tnode1" [10.10.10.22]="r00tnode2" [10.10.10.33]="r00tnode3" )'
# you can use "${ret_str}" to re-declare your new array via the "eval" command:
# eval "declare -A new_array=${ret_str}"
# now, you can use the new_array as normal :)
function util::parse_ini() {
    local ini_file="${1}"

    if [[ ! -f "${ini_file}" ]]; then
        LOG error "The ini file '${ini_file}' doesn't exist!"
        return 1
    fi

    local -a ips
    for line in $(grep -vE '(^#|^;|^$)' "${ini_file}" | grep '^\[.*\]'); do
        group_ips=($(ipv4::ip_string_to_ip_array "${line:1:-1}"))
        for ip in "${group_ips[@]}"; do
            if util::element_in_array "${ip}" "${ips[@]}"; then
                LOG error "The ip address '${ip}' is duplicated!"
                return 2
            elif ! util::can_ping "${ip}"; then
                LOG error "Can't ping this ip address: '${ip}'!"
                return 3
            fi
            ips+=(${ip})
        done
    done

    local -A ret
    while read -r line; do
        # exclude lines that are blank or comments.
        if [[ "${line}" =~ (^#|^;|^$) ]]; then
            continue
        elif [[ "${line}" =~ ^\[.*\]$ ]]; then
            group_ips=($(ipv4::ip_string_to_ip_array "${line:1:-1}"))
        else
            for ip in "${group_ips[@]}"; do
                if [[ "${ret[${ip}]}" =~ ${line} ]]; then
                    LOG error "The value '${line}' for '${ip}' is duplicated!" \
                              "tips: if a value is the prefix of other values" \
                              "(e.g. two values '/dev/sdb' and '/dev/sdb1')," \
                              "you should put the shortest one (i.e. /dev/sdb)" \
                              "before the others which use it as prefix."
                    return 4
                fi
                ret[${ip}]+="${line} "
            done
        fi
    done < "${ini_file}"

    for ip in "${ips[@]}"; do
        if [[ -z "${ret[${ip}]}" ]]; then
            LOG error "The value for '${ip}' in '${ini_file}' is empty!"
            return 5
        fi
        # remove the tailing blank.
        ret[${ip}]="${ret[${ip}]% }"
    done

    # echo -n "${ret_str#*=}"
    declare -p ret | sed -r 's/[^=]+=(.*)/\1/'
}


# util::calling_stacks prints the calling stacks with function's name,
# filename and the line number of the last caller.
function util::calling_stacks() {
    local start="${1:-1}"
    local stack=""
    local stack_size="${#FUNCNAME[@]}"

    # NOTE: stack #0 is the util::calling_stacks itself, we should
    # start with at least 1 to skip the calling_stack function itself.
    for ((stack_idx = start; stack_idx < stack_size; stack_idx++)); do
        local func="${FUNCNAME[${stack_idx}]}"
        local script="${BASH_SOURCE[${stack_idx}]}"
        local lineno="${BASH_LINENO[$((stack_idx-1))]}"

        # this means this function is executed on a remote host.
        if [[ -z "${script}" ]]; then
            local lines=0
            for srcfile in "${SCRIPTS[@]}"; do
                line="${SCRIPTS_LINES[${srcfile}]}"
                ((lines += line))
                ((lines <= lineno)) && continue
                remote_host="$(util::current_host_ip)"
                script="${srcfile} (executed on ${remote_host})"
                lineno=$((lineno + line - lines))
                break
            done
        elif [[ "${script}" =~ ^\. ]]; then
            src_dir=$(cd "$(dirname ${script})" && pwd)
            src_filename="${script##*/}"
            script="${src_dir}/${src_filename}"
        fi

        stack+="    at: ${func} ${script} +${lineno}\n"
    done

    echo -e "${stack}"
}


# util::get_global_envs returns the definitions of some environmet variables or
# array which are defined by kube-kit (actually defined in etc/*.sh or parser/*.sh)
# whose name start with any prefix configurated in etc/env.prefix
function util::get_global_envs() {
    declare_env_prefix="^declare [-aAi]+ (${KUBE_ENV_PREFIX_REGEX})[A-Z0-9_]*="
    declare -p | grep -P "${declare_env_prefix}" | tee "${KUBE_KIT_ENV_FILE}"
    # NOTE: if this function is executed on a remote host, it also returns the
    # definitions of all the library functions (defined in library/*.sh)
    if [[ -z "${__KUBE_KIT_DIR__}" ]]; then
        declare -f | sed -nr "/^(${KUBE_LIB_FUNCTION_REGEX}) \(\)/,/^\}$/p"
    fi
}


function util::element_in_array() {
    for ele in "${@:2}"; do
        if [[ "${ele}" == "$1" ]]; then
            return 0
        fi
    done

    return 1
}


function util::last_idx_in_array() {
    local ele="${1}"
    local arr=(${@:2})
    local ans=-1

    for idx in "${!arr[@]}"; do
        [[ "${arr[idx]}" == "${ele}" ]] && ans="${idx}"
    done

    echo -n "${ans}"
}


function util::sort_uniq_array() {
    local -a old_array=(${@})
    local -a new_array
    local -a sort_options
    local ele_all_ips=true

    for ele in "${old_array[@]}"; do
        [[ "${ele}" =~ ^${IPV4_REGEX}$ ]] || ele_all_ips=false
    done

    if [[ "${ele_all_ips}" == true ]]; then
        # if all elements in an array are ipv4 addresses, then sort
        # them according to each dot-seperated part of ip address.
        # 1,1n equals 1.1,1.0n (using all chars in the first field)
        sort_options=("-t" "." "-k" "1,1n" "-k" "2,2n" "-k" "3,3n" "-k" "4,4n")
    fi

    new_array=($(tr " " "\n" <<< "${old_array[@]}" | sort -u "${sort_options[@]}"))
    echo -n "${new_array[@]}"
}


function util::random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-16}" | head -n "${2:-1}"
}


function util::file_ends_with_newline() {
    [[ $(tail -c 1 "${1}" | wc -l) -gt 0 ]]
}


# library script means this file contains only function/variable definitions
function util::file_is_library_script() {
    # NOTE: KUBE_FUNCTION_DEF_REGEX is defined in parser/init.sh
    ! sed -r "/${KUBE_FUNCTION_DEF_REGEX}/,/^\}$/d" "${1}" | grep -vPq '^($|\s*(#|[a-zA-Z0-9_]+=).*)'
}


function util::timeout() {
    timeout --foreground -s SIGKILL -k 10s "${1}" "${@:2}"
}


function util::can_ping() {
    ping -c 4 -W 1 -i 0.05 "${1}" &>/dev/null
}


function util::can_ssh() {
    local host="${1}"
    util::timeout 10s \
        sshpass -p "${KUBE_CIPHERS_ARRAY[${host}]}" \
        ssh "root@${host}" "${OPENSSH_OPTIONS[@]}" -p "${SSHD_PORT}" \
        ls &>/dev/null
}


function util::sleep_random() {
    local min_seconds="${1:-1}"
    local max_seconds="${2:-2}"

    local min_msec max_msec tmp_msec
    min_msec=$(python -c "print(int(${min_seconds} * 1000))")
    max_msec=$(python -c "print(int(${max_seconds} * 1000))")

    if [[ "${max_msec}" -lt "${min_msec}" ]]; then
        tmp_msec="${min_msec}"
        min_msec="${max_msec}"
        max_msec="${tmp_msec}"
    fi

    local total_msec
    total_msec=$((min_msec + RANDOM % (max_msec - min_msec)))
    sleep "$(printf '%d.%03d' $((total_msec / 1000)) $((total_msec % 1000)))s"
}


function util::show_time() {
    local timer_show=""
    local total_ns="${1}"
    local delta_us="$((total_ns / 1000))"
    local us="$((delta_us % 1000))"
    local ms="$((delta_us / 1000 % 1000))"
    local s="$((delta_us / 1000000 % 60))"
    local m="$((delta_us / 60000000 % 60))"
    local h="$((delta_us / 3600000000))"

    # Goal: always show around 3 digits of time.
    if ((h > 0)); then
        timer_show="${h}h${m}m${s}s"
    elif ((m > 0)); then
        timer_show="${m}m${s}s"
    elif ((s >= 10)); then
        timer_show="${s}.$((ms / 100))s"
    elif ((s > 0)); then
        timer_show="${s}.$(printf %03d ${ms})s"
    elif ((ms >= 100)); then
        timer_show="${ms}ms"
    elif ((ms > 0)); then
        timer_show="${ms}.$((us / 100))ms"
    else
        timer_show="${us}us"
    fi

    echo -n "${timer_show}"
}


# this function returns the ip address which is in the kubernetes cluster.
function util::current_host_ip() {
    for ip in $(hostname -I); do
        if [[ "${KUBE_MASTER_IPS_ARRAY_LEN}" -gt 1 && \
              "${ip}" == "${KUBE_MASTER_VIP}" ]]; then
            continue
        elif ipv4::two_ips_in_same_subnet "${ip}" "${KUBE_KIT_HOST_IP}" \
                                          "${KUBE_KIT_HOST_CIDR}"; then
            echo -n "${ip}"
            return 0
        fi
    done

    LOG error "failed to get ipaddr of current host in the kubernetes cluster!"
    return 1
}


function util::start_and_enable() {
    local service="${1%.service}.service"

    if ! systemctl list-unit-files | grep -q "${service}"; then
        LOG warn "The service ${service} doesn't exist, can't start it, do nothing!"
        return 0
    fi

    systemctl daemon-reload
    if ! systemctl is-enabled "${service}" &>/dev/null; then
        systemctl enable "${service}" &>/dev/null
    fi

    if systemctl is-active "${service}" &>/dev/null; then
        systemctl stop "${service}" &>/dev/null && sleep 2s
    fi

    for _ in $(seq 3); do
        systemctl start "${service}"
        systemctl is-active "${service}" &>/dev/null && return 0
    done

    LOG error "Failed to (re)start ${service}, please check it yourself!"
    return 1
}


function util::stop_and_disable() {
    local service="${1%.service}.service"

    if ! systemctl list-unit-files | grep -q "${service}"; then
        LOG warn "The service ${service} doesn't exist, can't stop it, do nothing!"
        return 0
    fi

    if systemctl is-enabled "${service}" &>/dev/null; then
        systemctl disable "${service}" &>/dev/null
    fi

    if systemctl is-active "${service}" &>/dev/null; then
        systemctl kill -s SIGKILL -f "${service}" || true
    fi
}


function util::get_ipaddr_can_ping_gateway() {
    local gateway="${1}"
    local ipaddr=""
    local iface=""

    for netdev in /sys/class/net/*; do
        # skip all the virtual network devices.
        [[ $(readlink "${netdev}") =~ virtual ]] && continue
        phynic=$(basename "${netdev}")
        if ping -I "${phynic}" -c 4 -W 1 -i 0.05 "${gateway}" &>/dev/null; then
            # find the interface which can ping the gateway.
            iface="${phynic}"
            break
        fi
    done

    if [[ -n "${iface}" ]]; then
        ipaddr="$(ip addr show ${iface} | grep -oP '(?<=inet )[0-9.]+(?=/\d+)')"
    fi

    echo -n "${ipaddr}"
}


function util::get_mapper_file() {
    local vg_name="${1}"
    local lv_name="${2}"

    local real_block real_mapper_file
    # find the real block special file which the lv is.
    real_block=$(readlink -e "/dev/${vg_name}/${lv_name}")
    for mapper_file in /dev/mapper/*; do
        [[ ! -L "${mapper_file}" ]] && continue
        if [[ "${real_block}" == "$(readlink -e ${mapper_file})" ]]; then
            real_mapper_file="${mapper_file}"
            break
        fi
    done

    # in case the lv_name doesn't exist in the /dev/vg_name
    if [[ -z "${real_mapper_file}" ]]; then
        # if vg_name and lv_name contains dash (-), the mapper
        # name will use multiple dash to replace the one dash.
        # e.g. vg_name="aa--bb", lv_name="cc--dd"
        # we should search mapper file using the regex: aa-+bb-+cc-+dd
        mapper_name_regex=$(sed -r 's|-+|-+|g' <<< "${vg_name}-${lv_name}")
        # in case the lv_name is LV Pool with metadata and data.
        real_mapper_file=$(find /dev/mapper/ -type l |\
            grep -oP "${mapper_name_regex}" | uniq)
    fi

    echo -n "${real_mapper_file}"
}


function util::romove_contents() {
    local directory="${1}"
    [[ -z "${directory}" ]] && return 0

    rpm -qa | grep -q psmisc || yum install -y -q psmisc
    # if the directory is not used right now, just exit.
    fuser -a "${directory}" &>/dev/null || return 0

    LOG warn "Killing processes which are accessing ${directory} by force ..."
    fuser -sk "${directory}"
    rm -rf ${directory:-/tmp}/*
}


function util::force_umount() {
    local device="${1}"

    mount_point=$(mount | grep "${device}" | awk '{print $3}')
    util::romove_contents "${mount_point}"

    LOG warn "Umounting the device ${device} from ${mount_point} by force ..."
    sed -i "\|${device}|d" /etc/fstab
    umount -f "${device}"
}


function util::device_size_in_gb() {
    # calculate the total size of device.
    # $(parted -s "${device}" unit GiB print | grep -oP '(?<=${device}: )[0-9.]+(?=GiB)')
    # $(($(blockdev --getsize64 "${device}") / 1024 ** 3))
    echo -n $(($(lsblk -bdn -o SIZE "${1}") / 1024 ** 3))
}


function util::get_cpu_type() {
    local cpu_info_file="/proc/cpuinfo"
    # e.g. Intel(R) Core(TM) i7-6700K CPU @ 4.00GHz
    local intel_core_cpu_regex="Intel\([a-z]+\) Core\([a-z]+\) (.*)\s+CPU @ [0-9.]+GHz"
    # e.g. Intel(R) Xeon(R) CPU E5-2620 v4 @ 2.10GHz
    local intel_xeon_cpu_regex="Intel\([a-z]+\) Xeon\([a-z]+\) CPU\s+(.*) @ [0-9.]+GHz"
    local hypervisor=""
    local cpu_type=""

    # Notes: 'lscpu' command maybe does NOT output the informations of cpu flags.
    # just set 'cpu_type' to 'hypervisorName-virtual-machine' if the host is a VM.
    if grep -iq '^flags.*hypervisor.*' "${cpu_info_file}"; then
        hypervisor=$(dmesg | grep -oP '(?<=Hypervisor detected: ).*')
        echo -n "${hypervisor,,}-virtual-machine"
        return 0
    fi

    # NOTE: only support to detect two Intel serials: Core or Xeon
    intel_cpu_serial=$(lscpu | sed -nr 's|.*\)\s+([a-z]+)\(.*|\L\1|ip')
    cpu_type="intel-${intel_cpu_serial}"
    if [[ "${intel_cpu_serial}" =~ ^(core|xeon)$ ]]; then
        # intel_cpu_regex_varname="intel_${intel_cpu_serial}_cpu_regex"
        # intel_cpu_regex="${!intel_cpu_regex_varname}"
        intel_cpu_regex="$(eval echo \${intel_${intel_cpu_serial}_cpu_regex})"
        cpu_version=$(lscpu | sed -nr "s|^Model name:\s+${intel_cpu_regex}|\1|ip")
        # trim the leading and trailing whitespace and translate whitespace to dash.
        cpu_version="$(awk '{$1=$1};1' <<< ${cpu_version} | sed 's| |-|g')"
    fi

    [[ -n "${cpu_version}" ]] && cpu_type+="-${cpu_version}"
    echo -n "${cpu_type,,}"
}


function util::get_gpu_type() {
    local gpu_type="nogpus"
    if ls /dev/nvidia* &>/dev/null; then
        gpu_type=$(nvidia-smi -L |\
            sed -nr 's|^GPU [0-9]+: ([^(]+) \(UUID.*|nvidia-\L\1|p' | uniq)
    fi

    echo -n "${gpu_type// /-}"
}


function util::get_cpu_details() {
    lscpu | sed -nr 's|^Model name:\s+([^\s].*)|\1|p'
}


function util::get_gpu_details() {
    nvidia-smi -L 2>/dev/null | grep -oP '(?<=\d: ).*(?= \()' | uniq
}


function util::get_glusterfs_node_name() {
    peer_nodes="($(gluster peer status |& grep -oP '(?<=^Hostname: ).*' | paste -sd '|'))"
    awk "/${GLUSTERFS_NODE_NAME_PREFIX}/{print \$2}" /etc/hosts | grep -vP "${peer_nodes}"
}


function util::get_glusterfs_node_ip() {
    if [[ -n "${GLUSTERFS_NETWORK_GATEWAY}" ]]; then
        util::get_ipaddr_can_ping_gateway "${GLUSTERFS_NETWORK_GATEWAY}"
    else
        util::current_host_ip
    fi
}
