#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1083,SC1090,SC2034,SC2163,SC2206,SC2207


function wait::until() {
    local timeout
    local interval
    local func

    while true; do
        case "${1}" in
            -t|--timeout)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-t|--timeout' requires an argument!"
                    usage::wait::until 101
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    timeout="${2}"
                    shift 2
                else
                    LOG error "'${2}' is not a valid integer!"
                    usage::wait::until 102
                fi
                ;;
            -i|--interval)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-i|--interval' requires an argument!"
                    usage::wait::until 103
                elif [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
                    interval="${2}"
                    shift 2
                else
                    LOG error "'${2}' is not a valid integer!"
                    usage::wait::until 104
                fi
                ;;
            -f|--function)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-f|--function' requires an argument!"
                    usage::wait::until 105
                elif ! declare -f ${2} &>/dev/null; then
                    LOG error "The local function '${2}' is NOT defined!"
                    usage::wait::until 106
                else
                    func="${2}"
                    shift 2
                fi
                ;;
            -\?|--help)
                usage::wait::until 100
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

    if [[ -z "${timeout}" ]]; then
        LOG error "'-t <timeout_seconds>' is required!"
        usage::wait::until 107
    elif [[ -z "${interval}" ]]; then
        LOG error "'-i <interval_seconds>' is required!"
        usage::wait::until 108
    elif [[ -z "${func}" ]]; then
        LOG error "'-f <func_name>' is required!"
        usage::wait::until 109
    fi

    local total_sec=0
    until "${func}" "${@}" &>/dev/null || ((total_sec > timeout)); do
        ((total_sec += interval))
        sleep "${interval}"
    done

    # return 0 if func succeeded but didn't excceed the timeout.
    ((total_sec < timeout))
}


function wait::resource() {
    local namespace="kube-system"
    local status
    local type
    local name

    while true; do
        case "${1}" in
            -N|--namespace)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-N|--namespace' requires an argument!"
                    usage::wait::resource 111
                fi
                namespace="${2}"
                shift 2
                ;;
            -t|--type)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-t|--type' requires an argument!"
                    usage::wait::resource 112
                fi
                type="${2}"
                shift 2
                ;;
            -n|--name)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-n|--name' requires an argument!"
                    usage::wait::resource 113
                fi
                name="${2}"
                shift 2
                ;;
            -s|--status)
                if [[ -z "${2}" || "${2}" =~ ^--? ]]; then
                    LOG error "'-s|--status' requires an argument!"
                    usage::wait::resource 114
                fi
                status="${2}"
                shift 2
                ;;
            -\?|--help)
                usage::wait::resource 110
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

    if [[ -z "${type}" ]]; then
        LOG error "'-t <resource_type>' is required!"
        usage::wait::resource 115
    elif ! [[ "${type}" =~ ^(daemonset|deployment)$ ]]; then
        LOG error "$0 only support two types: daemonset/deployment"
        usage::wait::resource 116
    elif [[ -z "${name}" ]]; then
        LOG error "'-n <resource_name>' is required!"
        usage::wait::resource 117
    elif [[ -z "${status}" ]]; then
        LOG error "'-s <wait_status>' is required!"
        usage::wait::resource 118
    elif ! [[ "${status}" =~ ^(ready|deleted)$ ]]; then
        LOG error "$0 only support two status: ready/deleted"
        usage::wait::resource 119
    fi

    if [[ "${status}" == "ready" ]]; then
        if ! kubectl get namespace "${namespace}" &>/dev/null; then
            LOG error "The namespace ${namespace} doesn't exist!"
            usage::wait::resource 120
        elif ! kubectl get "${type}" "${name}" -n "${namespace}" &>/dev/null; then
            LOG error "The resource ${namespace}/${name} doesn't exist!"
            usage::wait::resource 121
        fi
    fi

    LOG debug "Waiting at most ${SECONDS_TO_WAIT} seconds until all the pods of" \
              "${type}/${name} in the namespace ${namespace} are ${status} ..."

    wait::until -t "${SECONDS_TO_WAIT}" \
                -i "5" \
                -f "util::${type}_${status}" \
                -- "${namespace}" "${name}" | tee /dev/null

    local exit_code="${PIPESTATUS[0]}"
    [[ "${exit_code}" -eq 0 ]] && return 0

    LOG error "Failed to wait for all the pods of ${type}/${name}" \
              "in the namespace ${namespace} to be ${status}!"
    return "${exit_code}"
}


function util::daemonset_ready() {
    local namespace="${1}"
    local name="${2}"

    kubectl_cmd="kubectl get daemonset ${name} -n ${namespace}"
    desired=$(${kubectl_cmd} -o go-template="{{.status.desiredNumberScheduled}}")

    for metric in currentNumberScheduled numberAvailable \
                  numberReady updatedNumberScheduled; do
        counts=$(${kubectl_cmd} -o go-template="{{.status.${metric}}}")
        [[ "${counts}" == "${desired}" ]] || return 1
    done
}


function util::deployment_ready() {
    local namespace="${1}"
    local name="${2}"

    kubectl_cmd="kubectl get deployment ${name} -n ${namespace}"
    replicas=$(${kubectl_cmd} -o go-template="{{.status.replicas}}")

    for metric in availableReplicas readyReplicas updatedReplicas; do
        counts=$(${kubectl_cmd} -o go-template="{{.status.${metric}}}")
        [[ "${counts}" == "${replicas}" ]] || return 1
    done
}


function util::pods_deleted() {
    local namespace="${1}"
    local prefix="${2}"

    # count the pods whose name starts with the prefix.
    pod_number=$(kubectl get pod -n "${namespace}" |\
                 grep -cP "^${prefix}-[a-z0-9]{5}")
    ((pod_number == 0))
}


# the pod_regex of daemonset is just the name of the daemonset.
function util::daemonset_deleted() {
    util::pods_deleted "${@}"
}


function util::deployment_deleted() {
    local namespace="${1}"
    local name="${2}"

    # if the deployment doesn't exist, just return 0.
    kubectl get deployment "${name}" -n "${namespace}" &>/dev/null || return 0

    # fetch the replicaset bound to current resourceVersion of the deployment.
    replicaset=$(kubectl get deployment "${name}" -n "${namespace}" -o yaml |\
        grep -oP "(?<=ReplicaSet \")${name}-[0-9a-f]{9}(?=\" is progressing)")

    util::pods_deleted "${namespace}" "${replicaset}"
}
