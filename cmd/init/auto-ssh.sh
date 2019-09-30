#!/usr/bin/env bash
# vim: nu:noai:ts=4

functions_file="${__KUBE_KIT_DIR__}/src/init/auto-ssh.sh"

[[ ! -f /usr/bin/sshpass ]] && yum install -y -q sshpass

ssh::execute_parallel -h "all" \
                      -s "${functions_file}" \
                      -- "generate_credentials"

# NOTE: this step can NOT be executed parallelly.
for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
    ssh::execute -h "${k8s_ip}" \
                 -s "${functions_file}" \
                 -- "authenticate_hosts"
done
