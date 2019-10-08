#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2046,SC2153,SC2206,SC2207

kube_binary_dir="${__KUBE_KIT_DIR__}/binaries/kubernetes/${KUBE_VERSION}"
kubernetes_server_binary_filename="kubernetes-server-linux-amd64.tar.gz"
local_kubernetes_server_binary_file="${kube_binary_dir}/${kubernetes_server_binary_filename}"
[[ ! -d "${kube_binary_dir}" ]] || mkdir -p "${kube_binary_dir}"

kube_master_binary_files=("kubectl" "kube-apiserver" "kube-controller-manager" "kube-scheduler")
kube_node_binary_files=("kubectl" "kubelet" "kube-proxy")

kube_all_binary_files=($(util::sort_uniq_array "${kube_master_binary_files[@]}" \
                                               "${kube_node_binary_files[@]}"))


function prepare::local_kubectl_file() {
    # in case that current machine is NOT in the kubernetes cluster.
    if ! util::element_in_array "${KUBE_KIT_NET_IPADDR}" "${KUBE_ALL_IPS_ARRAY[@]}"; then
        rpm -qa | grep -q bash-completion || yum install -y -q bash-completion
        cp -f "${kube_binary_dir}/kubectl" "/usr/local/bin/kubectl"
        kubectl completion bash >/etc/bash_completion.d/kubectl 2>/dev/null
    fi
}


function prepare::local_kube_binary_files() {
    if [[ -f "${kube_binary_dir}/kubectl" ]]; then
        # just check the version of kubectl in the kubernetes binary directory.
        kubectl_current_version=$(
            ${kube_binary_dir}/kubectl version --client --short | awk '{print $3}')
        if [[ "${kubectl_current_version}" == "${KUBE_VERSION}" ]]; then
            prepare::local_kubectl_file
            return 0
        else
            rm -rf ${kube_binary_dir:-/tmp}/*
        fi
    fi

    if [[ ! -f "${local_kubernetes_server_binary_file}" ]]; then
        LOG info "Downloading kubernetes-${KUBE_VERSION} binary files from ${KUBE_DOWNLOAD_URL} ..."
        curl -L "${KUBE_DOWNLOAD_URL}/${KUBE_VERSION}/${kubernetes_server_binary_filename}" \
             -o "${local_kubernetes_server_binary_file}"
    else
        LOG debug "Kubernetes-${KUBE_VERSION} binary files existed already! Do nothing ..."
    fi

    LOG info "Uncompressing kubernetes-${KUBE_VERSION} binary files ..."
    # ref: https://weikeit.github.io/2019/08/05/oneline-command/combine-curl-and-tar/
    tar -xzvf "${local_kubernetes_server_binary_file}" \
        -C "${kube_binary_dir}" \
        --strip-components 3 \
        $(sed -r 's|\S+|kubernetes/server/bin/&|g' <<< "${kube_all_binary_files[*]}")

    prepare::local_kubectl_file
}


function prepare::kube_master_binary_files() {
    local -a master_ips=("${@}")
    local -a source_options

    prepare::local_kube_binary_files

    for bin_file in "${kube_master_binary_files[@]}"; do
        source_options+=("-s" "${kube_binary_dir}/${bin_file}")
    done

    LOG info "Copying kubernetes-${KUBE_VERSION} binary files to all Masters ..."
    scp::execute_parallel -h "${master_ips[@]}" \
                          "${source_options[@]}" \
                          -d "/usr/local/bin/"
}


function prepare::kube_node_binary_files() {
    local -a node_ips=("${@}")
    local -a source_options

    prepare::local_kube_binary_files

    for bin_file in "${kube_node_binary_files[@]}"; do
        source_options+=("-s" "${kube_binary_dir}/${bin_file}")
    done

    LOG info "Copying kubernetes-${KUBE_VERSION} binary files to all Nodes ..."
    scp::execute_parallel -h "${node_ips[@]}" \
                          "${source_options[@]}" \
                          -d "/usr/local/bin/"
}
