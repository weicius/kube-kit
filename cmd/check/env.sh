#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/check/env.sh"
declare -a target_hosts=(${@})

LOG info "Checking if current host can ping all hosts ..."
for host in "${target_hosts[@]}"; do
    if ! util::can_ping "${host}"; then
        LOG error "The host ${host} is NOT active now!"
        exit 101
    fi
done

LOG info "Checking if the root password of all hosts are correct ..."
for host in "${target_hosts[@]}"; do
    if ! util::can_ssh "${host}"; then
        LOG error "The root password of ${host} is NOT correct!"
        exit 102
    fi
done

LOG info "Checking if the container/storage networks are correct ..."
ssh::execute_parallel -h "${target_hosts[@]}" \
                      -s "${functions_file}" \
                      -- "check::networks"

LOG info "Checking if the standalone device on all hosts exists ..."
ssh::execute_parallel -h "${target_hosts[@]}" \
                      -s "${functions_file}" \
                      -- "check::k8s_disks"

if [[ "${#HEKETI_NODE_IPS_ARRAY[@]}" -gt 0 && "${ENABLE_GLUSTERFS,,}" == "true" ]]; then
    LOG info "Checking if all the disks for heketi for glusterfs cluster exist ..."
    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${functions_file}" \
                          -- "check::heketi_disks"
fi
