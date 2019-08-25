#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


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