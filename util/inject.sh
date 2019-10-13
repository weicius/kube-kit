#!/usr/bin/env bash


function main() {
    local ns_name="${1}"
    local pod_name="${2}"
    local container_name_or_idx="${3:-1}"

    local usage="Usage: kube-inject <ns_name> <pod_name> [container_name|container_index]"
    local kube_pki_dir="__KUBE_PKI_DIR__"
    local kube_inject_image="__KUBE_INJECT_IMAGE__"
    local docker_daemon_port="__DOCKER_DAEMON_PORT__"
    local docker_tls_flag="--tlsverify \
                           --tlscacert=${kube_pki_dir}/ca.pem \
                           --tlscert=${kube_pki_dir}/docker.pem \
                           --tlskey=${kube_pki_dir}/docker-key.pem"

    if [[ $# -lt 2 ]]; then
        echo "Error: kube-inject requires at least 2 arguments for ns_name and pod_name," \
             "and an optional argument for container's name or index!"
        echo "${usage}"
        return 1
    fi

    hostIP="$(kubectl -n ${ns_name} get pod ${pod_name} -ojsonpath='{.status.hostIP}' 2>/dev/null)"
    if [[ -z "${hostIP}" ]]; then
        echo "Error: no such pod ${pod_name} in the namespace ${ns_name}!"
        echo "${usage}"
        return 2
    fi

    phase="$(kubectl -n ${ns_name} get pod ${pod_name} -ojsonpath='{.status.phase}')"
    if [[ "${phase}" != "Running" ]]; then
        echo "Error: the pod ${pod_name} in the namespace ${ns_name} is not Running!"
        echo "${usage}"
        return 3
    fi

    local jsonpath
    if [[ "${container_name_or_idx}" =~ ^[1-9][0-9]*$ ]]; then
        # treat 'container_name_or_idx' as the index of the container in the pod.
        jsonpath="{.status.containerStatuses[$((container_name_or_idx-1))].containerID}"
    else
        # treat 'container_name_or_idx' as the name of the container in the pod.
        jsonpath="{.status.containerStatuses[?(@.name=='${container_name_or_idx}')].containerID}"
    fi

    cid=$(kubectl -n ${ns_name} get pod ${pod_name} -ojsonpath="${jsonpath}" 2>/dev/null)

    if ! [[ "${cid}" =~ ^docker://[0-9a-f]{64}$ ]]; then
        if [[ "${container_name_or_idx}" =~ ^[0-9]+$ ]]; then
            echo "Error: container index ${container_name_or_idx} is out of bounds!"
        else
            echo "Error: no such container ${container_name_or_idx} in the pod ${pod_name}!"
        fi

        echo "${usage}"
        return 4
    fi

    # remove the prefix 'docker://'.
    cid="${cid:9:64}"
    docker_cmd="docker -H ${hostIP}:${docker_daemon_port} ${docker_tls_flag}"
    merged_dir="$(${docker_cmd} inspect -f '{{.GraphDriver.Data.MergedDir}}' ${cid})"

    local -a volumes
    for bind in $(${docker_cmd} inspect -f '{{.HostConfig.Binds}}' ${cid} | tr -d '\[\]'); do
        # [[ "${bind}" =~ (/etc/hosts|/dev/termination-log) ]] && continue
        volumes+=("--volume=$(sed -nr 's|([^:]+):(.*)|\1:/container_root\2|p' <<< ${bind})")
    done

    ${docker_cmd} run \
                  -it --rm \
                  --ipc="container:${cid}" \
                  --network="container:${cid}" \
                  --pid="container:${cid}" \
                  --volume="${merged_dir}:/container_root:rw" \
                  "${volumes[@]}" \
                  "${kube_inject_image}" \
                  bash -l
}

main "${@}"
