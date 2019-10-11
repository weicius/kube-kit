#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/init/env.sh"

# prepare all binary files of kubernetes and deliver them.
source "${__KUBE_KIT_DIR__}/util/prepare-k8s-files.sh"
prepare::kube_master_binary_files "${KUBE_MASTER_IPS_ARRAY[@]}"
prepare::kube_node_binary_files "${KUBE_NODE_IPS_ARRAY[@]}"

ssh::execute_parallel -h "all" \
                      -s "${functions_file}" \
                      -- "init_kube_env"

# prepare all binary files of cni and deliver them.
if [[ "${ENABLE_CNI_PLUGIN,,}" == "true" ]]; then
    source "${__KUBE_KIT_DIR__}/util/prepare-cni-files.sh"
    prepare::cni_binary_files "${KUBE_NODE_IPS_ARRAY[@]}"
fi
