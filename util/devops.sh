#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2120,SC2206,SC2207
set -o errexit
set +o pipefail

CMD_NAME="${0##*/}"
CMD_ARGS="${*}"
SSHD_PORT="22"
MAX_PARALLEL="50"
TIMEOUT="300"
LOG_FILE="/var/log/kube-devops.log"
START_TIME_NS="$(date +%s%N)"
OPENSSH_OPTIONS=$(cat <<-EOF | sed -r 's/\s+/ /g'
	-o LogLevel=error \
	-o PasswordAuthentication=no \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null
	EOF
)

################################################################################
####################### definitions of library functions #######################
################################################################################

function LOG() {
    local level=""
    local texts=""

    while true; do
        [[ $# -eq 0 ]] && break
        if [[ "${1,,}" =~ ^(info|debug|warn|error)$ ]]; then
            level="${1}"
        else
            texts+="${1} "
        fi
        shift
    done

    case "${level,,}" in
        info)
            # print 'green' text.
            color_code="\033[0;32m"
            ;;
        debug)
            # print 'blue' text.
            color_code="\033[0;34m"
            ;;
        warn)
            # print 'orange' text.
            color_code="\033[0;33m"
            ;;
        error)
            # print 'red' text.
            color_code="\033[0;31m"
            ;;
        *)
            # print debug by default.
            level="debug"
            color_code="\033[0;34m"
            ;;
    esac

    echo -e "${color_code}[$(hostname)] $(date +'%Y-%m-%d %H:%M:%S') [${level^^}] ${texts}\033[0m"
}


function util::usage() {
    local exit_code="${1:-0}"
    local cmd_name_len="${#CMD_NAME}"

    cat <<-EOF

	${CMD_NAME} is a command to execute a function in this script
	or raw commands on the remote host(s) serially or parallelly.

	Usage of this command:
	    ${CMD_NAME} -h|--hosts host1 host2 ... hostn \\
	    $(printf "%-${cmd_name_len}s") [-p|--parallel [2, ${MAX_PARALLEL}]] \\
	    $(printf "%-${cmd_name_len}s") [-f|--function func_name] \\
	    $(printf "%-${cmd_name_len}s") [-t|--timeout seconds] \\
	    $(printf "%-${cmd_name_len}s") [-P|--port int] \\
	    $(printf "%-${cmd_name_len}s") [-r|--raw-cmds] \\
	    $(printf "%-${cmd_name_len}s") -- "options_and_parameters_for_func_OR_raw_cmds"

	Options:
	    -h, --hosts    *string  Ipv4 address/hostname (>=1) of remote hosts
	                            Or use defined groups: master, node and all
	    -p, --parallel     int  Execute function or raw commands parallelly
	                            With the parallel degree (default: ${MAX_PARALLEL})
	    -f, --function  string  The function name to be executed on remote
	    -t, --timeout      int  Force to exit this script if the timeout
	    -P, --port         int  The port of sshd on all the target hosts
	                            (default is \${SSHD_PORT}: ${SSHD_PORT})
	    -r, --raw-cmds          Provide raw commands instead of a function
	    -?, --help              Print this help messages

	Notes:
	    1. You MUST provide '-f' OR '-r', but can NOT provide both of them!
	    2. Raw commands MUST be surrounded by a pair of quotation marks("")
	    3. Parallel degree should NOT be less than 2 or greater than ${MAX_PARALLEL}!

	Examples:
	    # execute the built-in function 'util::show_time' on all the hosts parallelly.
	    ${CMD_NAME} -h all \\
	    $(printf "%-${cmd_name_len}s") -p 10 \\
	    $(printf "%-${cmd_name_len}s") -f util::show_time \\
	    $(printf "%-${cmd_name_len}s") -- options and parameters for func: -a 1 -b 2 -c

	    # execute raw commands on k8s-node1 ~ k8s-node3 serially.
	    ${CMD_NAME} -h k8s-node{1..3} \\
	    $(printf "%-${cmd_name_len}s") -r \\
	    $(printf "%-${cmd_name_len}s") -- "date +'%Y-%m-%d %H:%M:%S'"

	    # define your own function in current shell.
	    function func_test {
	        echo "\$(hostname) => \$(date +'%Y-%m-%d %H:%M:%S')"
	        # blabla...
	    }

	    # export your function as an environment variable.
	    export -f func_test

	    # now, execute your local function on all the hosts parallelly.
	    ${CMD_NAME} -h all -p -f func_test

	EOF

    exit "${exit_code}"
}


function util::show_time() {
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

    printf "${timer_show}"
}


function util::summarize() {
    local exit_code="${1:-0}"
    stop_time_ns="$(date +%s%N)"
    total_time="$(util::show_time $((stop_time_ns - START_TIME_NS)))"

    if [[ "${exit_code}" -eq 0 ]]; then
        LOG info "${CMD_NAME} completed successfully using total time: ${total_time}"
    else
        LOG error "Failed to execute ${CMD_NAME} (with the exit code: ${exit_code})" \
                  "using total time: ${total_time}"
    fi

    exit "${exit_code}"
}


function util::random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-16}" | head -n "${2:-1}"
}


function util::can_ping() {
    ping -c 4 -W 1 -i 0.05 "${1}" &>/dev/null
}


function util::can_ssh() {
    local host="${1}"
    local port="${2:-${SSHD_PORT}}"

    timeout --foreground \
            -s SIGKILL \
            -k 10s 30s bash -c -- \
            "ssh root@${host} -p ${port} ${OPENSSH_OPTIONS} ls" \
            &>/dev/null
}


function ssh::execute() {
    local host=""
    local port="${SSHD_PORT}"
    local func=""
    local timeout="${TIMEOUT}"
    local raw_cmds="false"

    while true; do
        case "${1}" in
            -h|--host)
                host="${2}"
                shift 2
                ;;
            -p|--port)
                port="${2}"
                shift 2
                ;;
            -f|--function)
                func="${2}"
                shift 2
                ;;
            -t|--timeout)
                timeout="${2}"
                shift 2
                ;;
            -r|--raw-cmds)
                raw_cmds="true"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ "${raw_cmds}" == "true" ]]; then
        timeout --foreground -k 10s "${timeout}s" \
                ssh "root@${host}" ${OPENSSH_OPTIONS} -p "${port}" -qt -- "${@}"
    else
        timeout --foreground -k 10s "${timeout}s" \
                ssh "root@${host}" ${OPENSSH_OPTIONS} -p "${port}" -qt -- <<-EOF
				# or 'typeset -f'
				$(declare -f); ${func} ${@}
				EOF
    fi
}

################################################################################
################ built-in devops functions provided by kube-kit ################
################################################################################

function show_time() {
    LOG debug "$(date +'%Y-%m-%d %H:%M:%S') [$*]"
}


function all_k8s_services() {
    local services=(
        kube-apiserver
        kube-controller-manager
        kube-scheduler
        kube-proxy
        kubelet
        crond
        docker
        etcd
        httpd
        nginx
        keepalived
        glusterd
        flanneld
    )

    if ! [[ "${1}" =~ ^(start|stop|restart)$ ]]; then
        LOG error "Usage: all_k8s_services <start|stop|restart>"
        return 1
    fi

    for service in "${services[@]}"; do
        systemctl list-unit-files | grep -q "${service}" || continue
        LOG debug "${1}ing ${service} ..."
        systemctl "${1}" "${service}" &
    done && wait
}


################################################################################
####################### define your own functions below ########################
###### NOTES: you should name own functions with all lowercase characters ######
################################################################################


################################################################################
############## parse the options and parameters of devops command ##############
################################################################################
user_defined_func="($(declare -f | grep -oP '^\S+(?= \(\))' | grep -v '[A-Z]' | paste -sd '|'))"
hosts=()
parallel="1"
func=""
timeout="${TIMEOUT}"
port="${SSHD_PORT}"
raw_cmds="false"

while true; do
    case "${1}" in
        -h|--hosts)
            if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                LOG error "<${2}> is an invalid ipv4 address or hostname!"
                util::usage 101
            elif [[ "${2}" == "master" ]]; then
                hosts+=($(grep -oP '^[0-9.]+(?= k8s-master\d+)' /etc/hosts || true))
                shift 2
            elif [[ "${2}" == "node" ]]; then
                hosts+=($(grep -oP '^[0-9.]+(?= k8s-node\d+)' /etc/hosts || true))
                shift 2
            elif [[ "${2}" == "all" ]]; then
                hosts+=($(grep -oP '^[0-9.]+(?= k8s-(master|node)\d+)' /etc/hosts | sort -u || true))
                shift 2
            else
                hosts+=("${2}")
                shift 2
                while [[ "$#" -gt 0 ]]; do
                    [[ "${1}" =~ ^--? ]] && continue 2
                    # if the next parameter doesn't start with
                    # '-' or '--', which is another option, so
                    # we just treat it as another host of '-h'
                    hosts+=("${1}")
                    shift
                done
            fi
            ;;
        -p|--parallel)
            if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                parallel="${MAX_PARALLEL}"
                shift
            elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                if [[ "${2}" -lt 2 || "${2}" -gt ${MAX_PARALLEL} ]]; then
                    LOG warn "The parallel degree you provided is out of range" \
                             "[2, ${MAX_PARALLEL}], set it to ${MAX_PARALLEL}!"
                    parallel="${MAX_PARALLEL}"
                else
                    parallel="${2}"
                fi
                shift 2
            else
                LOG error "<${2}> is an invalid argument of [-p|--parallel]!"
                util::usage 102
            fi
            ;;
        -f|--function)
            if [[ "${2}" =~ ^${user_defined_func}$ ]]; then
                func="${2}"
                shift 2
            else
                LOG error "<${2}> is an invalid argument of [-f|--function]!" \
                          "Only support the following arguments now: ${user_defined_func}"
                util::usage 103
            fi
            ;;
        -P|--port)
            if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                port="${SSHD_PORT}"
                shift
            elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                if [[ "${2}" -lt 65536 ]]; then
                    port="${2}"
                    shift 2
                else
                    LOG error "<${2}> is out of port range [0, 65535]!"
                    util::usage 104
                fi
            else
                LOG error "<${2}> is an invalid argument of [-P|--port]!"
                util::usage 105
            fi
            ;;
        -t|--timeout)
            if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                timeout="${TIMEOUT}"
                shift
            elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                timeout="${2}"
                shift 2
            else
                LOG error "<${2}> is an invalid argument of [-t|--timeout]!"
                util::usage 106
            fi
            ;;
        -r|--raw-cmds)
            raw_cmds="true"
            shift
            ;;
        -\?|--help)
            util::usage
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done


if [[ "${raw_cmds}" == "true" ]]; then
    if [[ -n "${func}" ]]; then
        LOG error "The option '-r' conflicts with '-f'!"
        util::usage 107
    elif [[ -z "${*}" ]]; then
        LOG error "Your raw commands are empty!"
        util::usage 108
    fi
else
    if [[ -z "${func}" ]]; then
        LOG error "You MUST provide ONE of '-f' and '-r'!"
        util::usage 109
    fi
fi


random_dir="/tmp/$(util::random_string)"
mkdir -p "${random_dir}"

start=0
total_hosts="${#hosts[@]}"
loop_number="$((total_hosts / MAX_PARALLEL + 1))"
for (( idx=0; idx<loop_number; idx++ )); do
    curr_hosts=(${hosts[@]:${start}:${MAX_PARALLEL}})
    [[ "${#curr_hosts[@]}" -eq 0 ]] && break

    LOG info "Checking the availability for the target hosts:" \
             "No.${start} - No.$((start+${#curr_hosts[@]}-1))"
    ((start+=MAX_PARALLEL))

    for host in "${curr_hosts[@]}"; do
        (
            if ! util::can_ping "${host}"; then
                LOG warn "The remote host <${host}> is NOT active now, will skip it!"
                echo 1 > "${random_dir}/${host}"
            elif ! util::can_ssh "${host}" "${port}" &>/dev/null; then
                LOG warn "The current machine can NOT access the remote host <${host}>" \
                         "using root without password, will skip it!"
                echo 2 > "${random_dir}/${host}"
            else
                echo 0 > "${random_dir}/${host}"
            fi
        ) &
    done && wait
done

# NOTE:
# append a blank space to the end of the string '${valid_hosts_string}'
# to ensure that each hostname is **followed by a blank space**.
# so it's easy and clear to delete an invalid host from the string
# '${valid_hosts_string}' (just delete the pair '${host} ').
valid_hosts_string="${hosts[*]} "
for host in "${hosts[@]}"; do
    if [[ "$(cat ${random_dir}/${host})" -gt 0 ]]; then
        valid_hosts_string="${valid_hosts_string//${host} /}"
    fi
done

valid_hosts_array=($(tr ' ' '\n' <<< "${valid_hosts_string}" | sort -u))
rm -rf "${random_dir}"

if [[ "${#valid_hosts_array[@]}" -eq 0 ]]; then
    LOG error "You must provide at least one valid remote host!"
    util::usage 110
fi

################################################################################
###################### execute the actual devops command #######################
################################################################################

function devops() {
    local ssh_execute_options

    if [[ "${raw_cmds}" == "true" ]]; then
        ssh_execute_options="-r"
    else
        ssh_execute_options="-f ${func}"
    fi

    if [[ "${parallel}" -gt 1 ]]; then
        random_dir="/tmp/$(util::random_string)"
        mkdir -p "${random_dir}"

        local start=0
        local total_hosts="${#valid_hosts_array[@]}"
        local loop_number="$((total_hosts / parallel + 1))"

        for ((idx=0; idx<loop_number; idx++)); do
            curr_hosts=(${valid_hosts_array[@]:${start}:${parallel}})
            [[ "${#curr_hosts[@]}" -eq 0 ]] && break

            LOG info "Executing commands parallelly on the target hosts:" \
                     "No.${start} - No.$((start+${#curr_hosts[@]}-1))"
            ((start+=parallel))

            for host in "${curr_hosts[@]}"; do
                (
                    ssh::execute -h "${host}" \
                                 -p "${port}" \
                                 -t "${timeout}" \
                                 ${ssh_execute_options} \
                                 -- "$@" | tee /dev/null
                    echo "${PIPESTATUS[0]}" > "${random_dir}/${host}"
                ) &
            done && wait
        done

        local failed_jobs=0
        for host in "${valid_hosts_array[@]}"; do
            if [[ "$(cat ${random_dir}/${host})" -gt 0 ]]; then
                ((++failed_jobs))
                LOG error "The job executed on ${host} failed!"
            fi
        done

        rm -rf "${random_dir}"
        util::summarize "${failed_jobs}"
    else
        for host in "${valid_hosts_array[@]}"; do
            ssh::execute -h "${host}" \
                         -p "${port}" \
                         -t "${timeout}" \
                         ${ssh_execute_options} \
                         -- "$@" | tee /dev/null
            exit_code="${PIPESTATUS[0]}"
            if [[ "${exit_code}" -gt 0 ]]; then
                LOG error "The job executed on ${host} failed!"
                util::summarize "${exit_code}"
            fi
        done

        util::summarize 0
    fi
}


LOG debug "Starting to execute the command: ${CMD_NAME} ${CMD_ARGS}" >> "${LOG_FILE}"
devops "$@" |& tee -a "${LOG_FILE}"
