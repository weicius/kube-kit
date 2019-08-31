#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

if [[ "${#BASH_SOURCE[@]}" -ne 0 ]]; then
    __KUBE_KIT_DIR__=$(dirname "$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)")
fi

# options of ssh/scp command for automatization in scripts:
# ref: https://stackoverflow.com/a/11544979/6149338
# 1. LogLevel=error: print only error messages and drop something like 'Warning: Permanently added 'xx' (ECDSA)'
# 2. StrictHostKeyChecking=no: disable host key checking
# 3. UserKnownHostsFile=/dev/null: drop the fingerprints for the ECDSA key sent by the remote hosts
OPENSSH_OPTIONS=("-o" "LogLevel=error" "-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null")

# how many jobs are executed each time parallelly?
MAX_SSH_PARALLEL="50"

# NOTE: should NOT execute more than 10 scp commands to the same target parallelly.
# use the command to get the default max limits: `grep MaxSessions /etc/ssh/sshd_config`
# juts set it half of max limits to ensure it safe to execute multiple scp everytime.
MAX_SCP_PARALLEL="5"


################################################################################
########## the definition of the library function ** ssh::execute ** ###########
################################################################################

function ssh::execute() {
    local host=""
    local scripts=()
    local timeout="${SSH_EXECUTE_TIMEOUT}"
    local redirection_option=""
    local quiet="false"

    if [[ -n "${__KUBE_KIT_DIR__}" ]]; then
        # pass the library scripts to remote servers to enable your own function
        # to call any function which is defined in these scripts by default ONLY
        # when calling ssh::execute on current machine, NOT on remote hosts.
        scripts+=(${__KUBE_KIT_DIR__}/library/{logging,ipv4,util,usage,execute}.sh)
    fi

    while true; do
        case "${1}" in
            -h|--host)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-h|--host' requires an argument!"
                    usage::ssh::execute 101
                elif [[ "${2}" =~ ^${IPV4_REGEX}$ ]]; then
                    host="${2}"
                    shift 2
                else
                    LOG error "<${2}> is NOT a valid ipv4 address!"
                    usage::ssh::execute 102
                fi
                ;;
            -s|--script)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-s|--script' requires an argument!"
                    usage::ssh::execute 103
                elif [[ -f "${2}" && -x "${2}" ]]; then
                    if ! util::file_ends_with_newline "${2}"; then
                        LOG error "The script '${2}' ends with NO nowline!"
                        usage::ssh::execute 104
                    fi
                    # TODO: check if the script contains ONLY definitions
                    # of functions, and does NOT execute normal commands.
                    scripts+=("${2}")
                    shift 2
                else
                    LOG error "'${2}' is NOT a local executable file!"
                    usage::ssh::execute 105
                fi
                ;;
            -t|--timeout)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    timeout="${SSH_EXECUTE_TIMEOUT}"
                    shift
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    timeout="${2}"
                    shift 2
                else
                    LOG error "<${2}> is NOT a valid argument of '-t|--timeout'!"
                    usage::ssh::execute 106
                fi
                ;;
            -q|--quiet)
                # redirect the stdout and stderr to /dev/null if -q is offered.
                redirection_option="&>/dev/null"
                quiet="true"
                shift
                ;;
            -\?|--help)
                usage::ssh::execute 100
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

    if [[ -z "${host}" ]]; then
        LOG error "'-h|--host' is required!"
        usage::ssh::execute 107
    elif [[ -z "${*}" ]]; then
        LOG error "Your func_name or raw command is empty!"
        usage::ssh::execute 108
    fi

    # scripts=($(util::sort_uniq_array "${scripts[@]}"))
    # NOTE:
    # 1. this specific script should be added to the end of all scripts
    # to enable user to call functions just like normal commands.
    # 2. all scripts passed to remote servers should contain only the
    # definitions of all functions (must NOT execute normal commands)
    # except this one.
    local main_script="/root/.kube-kit.main.sh"
    if [[ ! -f "${main_script}" ]]; then
        echo 'set -e; eval -- "${@}"' > "${main_script}"
    fi
    scripts+=("${main_script}")

    # NOTE: we need to declare these two specific variables just before
    # counting the actual number of all global environment variables.
    local -a SCRIPTS
    local -A SCRIPTS_LINES

    # add the global env script of global env pairs and its line number.
    local global_env_script="/the/fake/global/env/script.sh"
    local global_env_script_line
    global_env_script_line="$(util::get_global_envs | wc -l)"

    # NOTE: we need to pass the array SCRIPTS which keeps all the scripts to be
    # passed to the remote hosts and SCRIPTS_LINES which maps the name of each
    # script to its total lines to remote servers, so calling_stack will parse
    # the right line number at which the command throws an error.
    SCRIPTS+=("${global_env_script}")
    SCRIPTS_LINES+=([${global_env_script}]="${global_env_script_line}")

    for script in "${scripts[@]}"; do
        SCRIPTS+=("${script}")
        SCRIPTS_LINES+=(["${script}"]="$(cat ${script} | wc -l)")
    done

    # the complex command combinated by `timeout`, `sshpass`, `ssh` and `bash`
    # will execute a local-defined function with arguments (all in ${@}) on a
    # remote host.
    # ssh::execute returns the same results and exit code with your commands.
    timeout --foreground -k 10s "${timeout}s" \
        sshpass -p "${KUBE_CIPHERS_ARRAY[${host}]}" \
            ssh "root@${host}" "${OPENSSH_OPTIONS[@]}" -p "${SSHD_PORT}" -qt \
                bash -s < <(cat <(util::get_global_envs) "${scripts[@]}") \
                -- "${@}" "${redirection_option}" | tee /dev/null

    # use `commands | tee /dev/null` to ensure the whole pipe above never fail!
    # and then we can use 'exit_code' to keep the exit_code of remote commands.
    local exit_code="${PIPESTATUS[0]}"
    # NOTE: if the remote commands failed, we need to print the calling stacks
    # executed on the local host. and your functions (executed on remote hosts)
    # should also call `LOG error` when error happens.
    [[ "${exit_code}" -gt 0 && "${quiet}" != "true" ]] && util::calling_stacks

    # return the actual exit code of remote commands.
    return "${exit_code}"
}


################################################################################
#### the detailed explanation of bash knowledges used in the function above ####
################################################################################

# The basic command to execute a script with arguments on remote host:
# ssh root@ipv4_address ${OPENSSH_OPTIONS[@]} bash -s < local_script_file -- $@

# ******************************** CAUTIONS ************************************
# NOTE: the 'local_script_file' MUST be ONE local file. Use bash redirection to
# pass it to ssh command, but if we want to pass multiple local script files,
# need to take advantage of process substitution '<()' to merge the output of
# function util::get_global_envs and local files (in order) into ONE file.

# Note that the redirection can appear at any point in the command, this is
# because the shell first takes out the redirection instruction (regardless
# of where it is in the command), then sets up the redirection, and finally
# executes the rest of the command line with the redirection in place.
# ******************************************************************************


################################################################################
###### the definition of the library function ** ssh::execute_parallel ** ######
################################################################################

function ssh::execute_parallel() {
    local -a hosts
    local -a ssh_execute_options
    local parallel="${MAX_SSH_PARALLEL}"
    local timeout="${SSH_EXECUTE_TIMEOUT}"

    while true; do
        case "${1}" in
            -h|--hosts)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-h|--hosts' requires at least one argument!"
                    usage::ssh::execute_parallel 111
                elif [[ "${2,,}" == "all" ]]; then
                    hosts+=(${KUBE_ALL_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "master" ]]; then
                    hosts+=(${KUBE_MASTER_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "node" ]]; then
                    hosts+=(${KUBE_NODE_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "etcd" ]]; then
                    hosts+=(${ETCD_NODE_IPS_ARRAY[@]})
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
            -s|--script)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-s|--script' requires an argument!"
                    usage::ssh::execute_parallel 112
                elif [[ -f "${2}" && -x "${2}" ]]; then
                    if ! util::file_ends_with_newline "${2}"; then
                        LOG error "The script '${2}' ends with NO nowline!"
                        usage::ssh::execute_parallel 113
                    fi
                    ssh_execute_options+=("-s" "${2}")
                    shift 2
                else
                    LOG error "'${2}' is NOT a local executable file!"
                    usage::ssh::execute_parallel 114
                fi
                ;;
            -p|--parallel)
                # if degree is NOT provided, set it to MAX_SSH_PARALLEL.
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    parallel="${MAX_SSH_PARALLEL}"
                    shift
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    # also set it to MAX_SSH_PARALLEL if the degree is
                    # smaller than 2 or larger than MAX_SSH_PARALLEL.
                    if [[ "${2}" -lt 2 || "${2}" -gt "${MAX_SSH_PARALLEL}" ]]; then
                        LOG warn "The parallel degree you provided is out of the range" \
                                 "[2, ${MAX_SSH_PARALLEL}], set it to ${MAX_SSH_PARALLEL}!"
                        parallel="${MAX_SSH_PARALLEL}"
                    else
                        parallel="${2}"
                    fi
                    shift 2
                else
                    LOG error "<${2}> is an invalid argument of '-p|--parallel'!"
                    usage::ssh::execute_parallel 115
                fi
                ;;
            -t|--timeout)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    timeout="${SSH_EXECUTE_TIMEOUT}"
                    shift
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    timeout="${2}"
                    shift 2
                else
                    LOG error "<${2}> is NOT a valid argument of '-t|--timeout'!"
                    usage::ssh::execute_parallel 116
                fi
                ;;
            -q|--quiet)
                ssh_execute_options+=("-q")
                shift
                ;;
            -\?|--help)
                usage::ssh::execute_parallel 110
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

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        LOG error "'-h|--hosts' is required!"
        usage::ssh::execute_parallel 117
    fi

    for host in "${hosts[@]}"; do
        [[ "${host}" =~ ^${IPV4_REGEX}$ ]] && continue
        LOG error "'${host}' is NOT a valid ipv4 address!"
        usage::ssh::execute_parallel 118
    done

    # NOTE: need to remove the duplicated hosts to
    # avoid executing multiple times on same host.
    hosts=($(util::sort_uniq_array "${hosts[@]}"))

    if [[ -z "${*}" ]]; then
        LOG error "Your func_name or raw command is empty!"
        usage::ssh::execute_parallel 119
    fi

    # prepare the temporary directory to store exit_codes.
    local random_dir
    random_dir="/tmp/$(util::random_string)"
    mkdir -p "${random_dir}"

    local start=0
    local total_hosts="${#hosts[@]}"
    local loop_number="$((total_hosts / parallel + 1))"

    for ((loop_idx = 0; loop_idx < loop_number; loop_idx++)); do
        local curr_hosts=(${hosts[@]:${start}:${parallel}})
        local curr_hosts_len="${#curr_hosts[@]}"
        [[ "${curr_hosts_len}" -eq 0 ]] && break

        # LOG_EMPHASIZE title "*" "Executing the ssh command parallelly on the" \
        #               "remote hosts: No.${start} - No.$((start+curr_hosts_len-1))"

        for host in "${curr_hosts[@]}"; do
            (
                ssh::execute -h "${host}" \
                             -t "${timeout}" \
                             "${ssh_execute_options[@]}" \
                             -- "${@}" | tee /dev/null
                echo -n "${PIPESTATUS[0]}" > "${random_dir}/${host}"
            ) &
        done && wait

        ((start += parallel))
    done

    local failed_jobs=0
    for host in "${hosts[@]}"; do
        [[ "$(cat ${random_dir}/${host})" -eq 0 ]] && continue
        # https://unix.stackexchange.com/a/146778/264900
        # we must NOT use ((failed_jobs++)) here, because
        # failed_jobs is initialized to 0, the first time
        # to execute ((failed_jobs++)), the exit_code of
        # 'failed_jobs++' is 'failed_jobs' itself(i.e. 0)
        # which is a FAILURE (return 1)!
        # instead, use '++failed_jobs', the exit_code is
        # 'failed_jobs+1' (>0 anyway), so it won't fail.
        ((++failed_jobs))
        LOG error "Ooops! The job executed on ${host} failed!"
    done

    rm -rf "${random_dir}"

    # NOTE: the final real exit code shoule be: $((failed_jobs % 256)).
    [[ "${failed_jobs}" -eq 0 ]] && return 0
    return "$((failed_jobs % 256 == 0 ? 1 : failed_jobs))"
}


################################################################################
########### the definition of the library function ** scp::execute ** ##########
################################################################################

function scp::execute() {
    local host=""
    local sources=()
    local destination=""
    local reverse="false"

    while true; do
        case "${1}" in
            -h|--host)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-h|--host' requires an argument!"
                    usage::scp::execute 121
                elif [[ "${2}" =~ ^${IPV4_REGEX}$ ]]; then
                    host="${2}"
                    shift 2
                else
                    LOG error "<${2}> is NOT a valid ipv4 address!"
                    usage::scp::execute 122
                fi
                ;;
            -s|--source)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-s|--source' requires an argument!"
                    usage::scp::execute 123
                else
                    sources+=("${2}")
                    shift 2
                fi
                ;;
            -d|--destination)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-d|--destination' requires an argument!"
                    usage::scp::execute 124
                else
                    destination="${2}"
                    shift 2
                fi
                ;;
            -r|--reverse)
                reverse="true"
                shift
                ;;
            -\?|--help)
                usage::scp::execute 120
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

    if [[ -z "${host}" ]]; then
        LOG error "'-h|--host' is required!"
        usage::scp::execute 125
    elif [[ "${#sources[@]}" -eq 0 ]]; then
        LOG error "'-s|--source' is required!"
        usage::scp::execute 126
    elif [[ -z "${destination}" ]]; then
        LOG error "'-d|--destination' is required!"
        usage::scp::execute 127
    fi

    # NOTE: Two situations of scp commands (copy to or from remote host):
    # 1. scp -r /path/to/file1 /path/to/dir1 root@host:destination
    # 2. scp -r root@host:/path/to/file1 root@host:/path/to/dir1 destination
    if [[ "${reverse}" == "false" ]]; then
        destination="root@${host}:${destination}"
    else
        for sidx in "${!sources[@]}"; do
            sources[${sidx}]="root@${host}:${sources[${sidx}]}"
        done
    fi

    sshpass -p "${KUBE_CIPHERS_ARRAY[${host}]}" \
            scp -r "${OPENSSH_OPTIONS[@]}" -P "${SSHD_PORT}" \
            "${sources[@]}" "${destination}"
}


################################################################################
###### the definition of the library function ** scp::execute_parallel ** ######
################################################################################

function scp::execute_parallel() {
    local -a hosts
    local -a sources
    local destination=""
    local reverse="false"
    local parallel="${MAX_SCP_PARALLEL}"

    while true; do
        case "${1}" in
            -h|--hosts)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-h|--hosts' requires at least one argument!"
                    usage::scp::execute_parallel 131
                elif [[ "${2,,}" == "all" ]]; then
                    hosts+=(${KUBE_ALL_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "master" ]]; then
                    hosts+=(${KUBE_MASTER_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "node" ]]; then
                    hosts+=(${KUBE_NODE_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "etcd" ]]; then
                    hosts+=(${ETCD_NODE_IPS_ARRAY[@]})
                    shift 2
                else
                    hosts+=("${2}")
                    shift 2
                    while [[ "$#" -gt 0 ]]; do
                        [[ "${1}" =~ ^--? ]] && continue 2
                        hosts+=("${1}")
                        shift
                    done
                fi
                ;;
            -s|--source)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-s|--source' requires an argument!"
                    usage::scp::execute_parallel 132
                else
                    sources+=("${2}")
                    shift 2
                fi
                ;;
            -d|--destination)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-d|--destination' requires an argument!"
                    usage::scp::execute_parallel 133
                else
                    destination="${2}"
                    shift 2
                fi
                ;;
            -r|--reverse)
                reverse="true"
                shift
                ;;
            -p|--parallel)
                # if degree is NOT provided, set it to MAX_SCP_PARALLEL.
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    parallel="${MAX_SCP_PARALLEL}"
                    shift
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    # also set it to MAX_SCP_PARALLEL if the degree is
                    # smaller than 2 or larger than MAX_SCP_PARALLEL.
                    if [[ "${2}" -lt 2 || "${2}" -gt "${MAX_SCP_PARALLEL}" ]]; then
                        LOG warn "The parallel degree you provided is out of the range" \
                                 "[2, ${MAX_SCP_PARALLEL}], set it to ${MAX_SCP_PARALLEL}!"
                        parallel="${MAX_SCP_PARALLEL}"
                    else
                        parallel="${2}"
                    fi
                    shift 2
                else
                    LOG error "<${2}> is invalid argument of '-p|--parallel'!"
                    usage::scp::execute_parallel 134
                fi
                ;;
            -\?|--help)
                usage::scp::execute_parallel 130
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

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        LOG error "'-h|--hosts' is required!"
        usage::scp::execute_parallel 135
    fi

    for host in "${hosts[@]}"; do
        [[ "${host}" =~ ^${IPV4_REGEX}$ ]] && continue
        LOG error "'${host}' is NOT a valid ipv4 address!"
        usage::scp::execute_parallel 136
    done

    if [[ "${#sources[@]}" -eq 0 ]]; then
        LOG error "'-s|--source' is required!"
        usage::scp::execute_parallel 137
    elif [[ -z "${destination}" ]]; then
        LOG error "'-d|--destination' is required!"
        usage::scp::execute_parallel 138
    fi

    local -a scp_execute_options
    # if reverse is 'true', add '-r' to the final options.
    if [[ "${reverse}" == "true" ]]; then
        scp_execute_options+=("-r")
    fi

    for source in "${sources[@]}"; do
        scp_execute_options+=("-s" "${source}")
    done

    # prepare the temporary directory to store exit_codes.
    local random_dir
    random_dir="/tmp/$(util::random_string)"
    mkdir -p "${random_dir}"

    local start=0
    local total_hosts="${#hosts[@]}"
    local loop_number="$((total_hosts / parallel + 1))"

    for ((loop_idx = 0; loop_idx < loop_number; loop_idx++)); do
        local curr_hosts=(${hosts[@]:${start}:${parallel}})
        local curr_hosts_len="${#curr_hosts[@]}"
        [[ "${curr_hosts_len}" -eq 0 ]] && break

        # LOG_EMPHASIZE title "*" "Executing the scp command parallelly on the" \
        #               "remote hosts: No.${start} - No.$((start+curr_hosts_len-1))"

        for host in "${curr_hosts[@]}"; do
            (
                scp::execute -h "${host}" \
                             "${scp_execute_options[@]}" \
                             -d "${destination}" | tee /dev/null
                echo -n "${PIPESTATUS[0]}" > "${random_dir}/${host}"
            ) &
        done && wait

        ((start += parallel))
    done

    local failed_jobs=0
    for host in "${hosts[@]}"; do
        [[ "$(cat ${random_dir}/${host})" -eq 0 ]] && continue
        ((++failed_jobs))
        LOG error "Ooops! The job executed on ${host} failed!"
    done

    rm -rf "${random_dir}"

    # NOTE: the final real exit code shoule be: $((failed_jobs % 256)).
    [[ "${failed_jobs}" -eq 0 ]] && return 0
    return "$((failed_jobs % 256 == 0 ? 1 : failed_jobs))"
}


################################################################################
##### the definition of the library function ** local::execute_parallel ** #####
################################################################################

function local::execute_parallel() {
    local hosts=()
    local func=""
    local parallel=""

    while true; do
        case "${1}" in
            -h|--hosts)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-h|--hosts' requires at least one argument!"
                    usage::local_execute_parallel 141
                elif [[ "${2,,}" == "all" ]]; then
                    hosts+=(${KUBE_ALL_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "master" ]]; then
                    hosts+=(${KUBE_MASTER_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "node" ]]; then
                    hosts+=(${KUBE_NODE_IPS_ARRAY[@]})
                    shift 2
                elif [[ "${2,,}" == "etcd" ]]; then
                    hosts+=(${ETCD_NODE_IPS_ARRAY[@]})
                    shift 2
                else
                    hosts+=("${2}")
                    shift 2
                    while [[ "$#" -gt 0 ]]; do
                        [[ "${1}" =~ ^--? ]] && continue 2
                        hosts+=("${1}")
                        shift
                    done
                fi
                ;;
            -f|--function)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-f|--function' requires an argument!"
                    usage::local_execute_parallel 142
                elif ! declare -f ${2} &>/dev/null; then
                    LOG error "The local function <${2}> is NOT defined!"
                    usage::local_execute_parallel 143
                else
                    func="${2}"
                    shift 2
                fi
                ;;
            -p|--parallel)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-p|--parallel' requires an argument!"
                    usage::local_execute_parallel 144
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    parallel="${2}"
                    shift 2
                else
                    LOG error "<${2}> is invalid argument of '-p|--parallel'!"
                    usage::local_execute_parallel 145
                fi
                ;;
            -\?|--help)
                usage::local_execute_parallel 140
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

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        LOG error "'-h|--hosts' is required!"
        usage::local_execute_parallel 146
    fi

    for host in "${hosts[@]}"; do
        [[ "${host}" =~ ^${IPV4_REGEX}$ ]] && continue
        LOG error "'${host}' is NOT a valid ipv4 address!"
        usage::local_execute_parallel 147
    done

    if [[ -z "${func}" ]]; then
        LOG error "'-f|--function' is required!"
        usage::local_execute_parallel 148
    fi

    # prepare the temporary directory to store exit_codes.
    local random_dir
    random_dir="/tmp/$(util::random_string)"
    mkdir -p "${random_dir}"

    local start=0
    local total_hosts="${#hosts[@]}"
    local loop_number="$((total_hosts / parallel + 1))"

    for ((loop_idx = 0; loop_idx < loop_number; loop_idx++)); do
        local curr_hosts=(${hosts[@]:${start}:${parallel}})
        local curr_hosts_len="${#curr_hosts[@]}"
        [[ "${curr_hosts_len}" -eq 0 ]] && break

        # LOG_EMPHASIZE title "*" "Executing function '${func}' parallelly on the" \
        #               "remote hosts: No.${start} - No.$((start+curr_hosts_len-1))"

        for host_idx in "${!curr_hosts[@]}"; do
            (
                local host="${curr_hosts[${host_idx}]}"
                # NOTE: You can use the built-in environment variables
                # '${HOST}' and '${INDEX}' in your local functions.
                export HOST="${host}"
                export INDEX="$((start + host_idx))"
                eval -- "${func} ${*}" | tee /dev/null
                echo -n "${PIPESTATUS[0]}" > "${random_dir}/${host}"
            ) &
        done && wait

        ((start += parallel))
    done

    local failed_jobs=0
    for host in "${hosts[@]}"; do
        [[ "$(cat ${random_dir}/${host})" -eq 0 ]] && continue
        ((++failed_jobs))
        LOG error "Ooops! Failed to execute the function '${func}'" \
                  "with the arguments [${*}] on the host '${host}'!"
    done

    rm -rf "${random_dir}"

    # NOTE: the final real exit code shoule be: $((failed_jobs % 256)).
    [[ "${failed_jobs}" -eq 0 ]] && return 0
    return "$((failed_jobs % 256 == 0 ? 1 : failed_jobs))"
}
