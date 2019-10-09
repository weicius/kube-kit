#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/deploy/flannel.sh"
flanneld_dir="${__KUBE_KIT_DIR__}/binaries/flannel"
# https://github.com/coreos/flannel/releases
flanneld_tgz="${flanneld_dir}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz"

if [[ ! -f "${flanneld_tgz}" ]]; then
    LOG error "The local flanneld file ${flanneld_tgz} doesn't exist!"
    exit 1
fi

if [[ ! -f "${flanneld_dir}/flanneld" || \
      ! -f "${flanneld_dir}/mk-docker-opts.sh" ]]; then
    tar -xzvf "${flanneld_tgz}" -C "${flanneld_dir}" \
        {flanneld,mk-docker-opts.sh}
fi

ssh::execute -h "${ETCD_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "config_etcd"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "stop_flanneld"

scp::execute_parallel -h "node" \
                      -s "${flanneld_dir}/flanneld" \
                      -s "${flanneld_dir}/mk-docker-opts.sh" \
                      -d "/usr/local/bin"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "config_flanneld"
