#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216

functions_file="${__KUBE_KIT_DIR__}/src/deploy/k8s-node.sh"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "config_k8s_node"

LOG debug "Waiting at most 100 seconds until all nodes are in Ready status ..."
if ! wait::until -t 100 -i 5 -f ready::all_nodes; then
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
