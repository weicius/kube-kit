#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2046,SC2153,SC2206,SC2207

cni_dir="${__KUBE_KIT_DIR__}/binaries/cni"
cni_tgz_file="${cni_dir}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"
cni_binary_dir="${cni_dir}/${CNI_VERSION}"
calico_cni_plugin_dir="${__KUBE_KIT_DIR__}/binaries/calico/cni-plugin/${CALICO_CNI_VERSION}"
calicoctl_dir="${__KUBE_KIT_DIR__}/binaries/calico/calicoctl/${CALICOCTL_VERSION}"


function prepare::cni_binary_files() {
    local node_ips=("${@}")

    # prepare cni binary files to start up kubelet.
    mkdir -p "${cni_binary_dir}"
    tar -xzf "${cni_tgz_file}" -C "${cni_binary_dir}"
    for calico_file in calico calico-ipam; do
        if [[ ! -x "${calico_cni_plugin_dir}/${calico_file}" ]]; then
            chmod +x "${calico_cni_plugin_dir}/${calico_file}"
        fi
    done

    if [[ ! -x "${calicoctl_dir}/calicoctl" ]]; then
        chmod +x "${calicoctl_dir}/calicoctl"
    fi

    ssh::execute_parallel -h "${node_ips[@]}" -- "
        rm -rf ${CNI_CONF_DIR} ${CNI_BIN_DIR}
        mkdir -p ${CNI_CONF_DIR} ${CNI_BIN_DIR}
    "

    LOG info "Copying cni-${CNI_VERSION} and calico cni-plugin-${CALICO_CNI_VERSION}" \
             "binary files to all Nodes ..."

    scp::execute_parallel -h "${node_ips[@]}" \
                          -s "${__KUBE_KIT_DIR__}/addon/calico/calico-node.conf" \
                          -d "${CNI_CONF_DIR}"

    scp::execute_parallel -h "${node_ips[@]}" \
                          -s "${cni_binary_dir}/loopback" \
                          -s "${calico_cni_plugin_dir}/calico" \
                          -s "${calico_cni_plugin_dir}/calico-ipam" \
                          -d "${CNI_BIN_DIR}"

    scp::execute_parallel -h "${node_ips[@]}" \
                          -s "${calicoctl_dir}/calicoctl" \
                          -d "/usr/local/bin"

    ssh::execute_parallel -h "${node_ips[@]}" -- "
        sed -i -r '/DATASTORE_TYPE|KUBECONFIG/d' /root/.bashrc
		cat >> /root/.bashrc <<-EOF
		export DATASTORE_TYPE=kubernetes
		export KUBECONFIG=/root/.kube/config
		EOF
    "

    rm -rf "${cni_binary_dir}"
}
