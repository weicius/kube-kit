#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/deploy/crontab.sh"

for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
    for script in crontab devops inject; do
        scp::execute -h "${k8s_ip}" \
                     -s "${__KUBE_KIT_DIR__}/util/${script}.sh" \
                     -d "/usr/local/bin/kube-${script}"
    done
done

ssh::execute_parallel -h "all" \
                      -s "${functions_file}" \
                      -- "config_kube_scripts"

ssh::execute_parallel -h "all" \
                      -s "${functions_file}" \
                      -- "config_crond_service"

LOG info "Setting crontab for all the k8s masters ..."
ssh::execute_parallel -h "master" \
                      -s "${functions_file}" \
                      -- "set_crontab_for_k8s_masters"

LOG info "Setting crontab for all the k8s nodes ..."
ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "set_crontab_for_k8s_nodes"
