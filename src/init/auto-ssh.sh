#!/usr/bin/env bash
# vim: nu:noai:ts=4


function generate_credentials() {
    current_ip="$(util::current_host_ip)"

    [[ ! -f /usr/bin/sshpass ]] && yum install -y -q sshpass
    [[ -f /root/.ssh/id_rsa ]] && rm -rf /root/.ssh/*

    LOG debug "Generating new ssh credentials on ${current_ip} ..."
    ssh-keygen -t rsa \
               -b "${SSH_RSA_KEY_BITS}" \
               -f /root/.ssh/id_rsa \
               -N '' &>/dev/null
}


function authenticate_host() {
    current_ip="$(util::current_host_ip)"

    sshpass -p "${KUBE_CIPHERS_ARRAY[${HOST}]}" \
            ssh-copy-id -i "/root/.ssh/id_rsa.pub" \
                        -p "${SSHD_PORT}" \
                        "${OPENSSH_OPTIONS[@]}" \
                        "root@${HOST}" &>/dev/null

    LOG debug "Accessing to ${HOST} from ${current_ip} is authenticated!"
}


function authenticate_hosts() {
    local::execute_parallel -h all -f authenticate_host
}
