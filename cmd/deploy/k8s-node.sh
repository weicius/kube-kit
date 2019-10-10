#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216

functions_file="${__KUBE_KIT_DIR__}/src/deploy/k8s-node.sh"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "config_k8s_node"

LOG debug "Waiting at most 100 seconds for all nodes to in Ready status ..."
for ((idx=0; idx<10; idx++)); do
    util::sleep_random 5 10
    ready_nodes=$(kubectl get node 2>/dev/null | grep -wc 'Ready' || true)
    [[ "${ready_nodes}" -eq "${KUBE_NODE_IPS_ARRAY_LEN}" ]] && break
done

if [[ "${idx}" -eq 10 ]]; then
    LOG error "Failed to wait for all nodes to be in Ready status ..."
    exit 1
fi


LOG info "Setting master role for all kubernetes masters ..."
ssh::execute_parallel -h "master" \
                      -s "${functions_file}" \
                      -- "label_master_role"

util::sleep_random
LOG info "Setting node role for all kubernetes nodes ..."
ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "label_node_role"

util::sleep_random
LOG info "Setting cputype and gputype for all kubernetes nodes ..."
ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "label_cputype_gputype"
