#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# ************* validate configurations of localrepo and local ntp *************
################################################################################

if [[ "${ENABLE_LOCAL_YUM_REPO,,}" == "true" ]]; then
    if [[ -z "${LOCAL_YUM_REPO_HOST}" || ! $(util::element_in_array \
        "${LOCAL_YUM_REPO_HOST}" "${KUBE_ALL_IPS_ARRAY[@]}") ]]; then
        LOCAL_YUM_REPO_HOST="${KUBE_MASTER_IPS_ARRAY[0]}"
        sed -i -r "s|^(LOCAL_YUM_REPO_HOST=).*|\1\"${LOCAL_YUM_REPO_HOST}\"|" \
            "${__KUBE_KIT_DIR__}/etc/kube-kit.env"
    fi

    # NOTE: LOCAL_YUM_RPMS_ARRAY keeps all the necessary rpm packages that
    # will be installed on all machines.
    rpm_list="${__KUBE_KIT_DIR__}/etc/rpm.list"
    declare -a LOCAL_YUM_RPMS_ARRAY=($(grep -v '^\s*#.*' "${rpm_list}"))
fi

if [[ "${ENABLE_LOCAL_NTP_SERVER,,}" == "true" ]]; then
    if [[ -z "${LOCAL_NTP_SERVER}" || ! $(util::element_in_array \
        "${LOCAL_NTP_SERVER}" "${KUBE_ALL_IPS_ARRAY[@]}") ]]; then
        KUBE_NTP_SERVER="${KUBE_MASTER_IPS_ARRAY[0]}"
        sed -i -r "s|^(LOCAL_NTP_SERVER=).*|\1\"${KUBE_NTP_SERVER}\"|" \
            "${__KUBE_KIT_DIR__}/etc/kube-kit.env"
    else
        KUBE_NTP_SERVER="${LOCAL_NTP_SERVER}"
    fi
else
    KUBE_NTP_SERVER="${REMOTE_NTP_SERVER}"
fi

################################################################################
# ******* delete all the fingerprints of hosts in the kubernetes cluster *******
################################################################################

if [[ -f /root/.ssh/known_hosts ]]; then
    for k8s_ip in "${KUBE_ALL_IPS_ARRAY[@]}"; do
        sed -i "/${k8s_ip}/d" /root/.ssh/known_hosts
    done
fi

################################################################################
# ** ensure current machine have kubernetes configuration files if they exist **
################################################################################

if [[ ! -f /root/.kube/config ]]; then
    first_node_ip="${KUBE_NODE_IPS_ARRAY[0]}"
    # NOTE: this is the first time to call ssh::execute
    if ssh::execute -h "${first_node_ip}" -q "[[ -f /root/.kube/config ]]"; then

        # LOG warn "Current machine doesn't have '/root/.kube/config' file!"
        # LOG debug "Copying '/root/.kube/config' from ${first_node_ip} ..."

        for kube_dir in "/root/.kube" "${KUBE_CONFIG_DIR}"; do
            [[ -d "${kube_dir}" ]] && rm -rf "${kube_dir}"
            mkdir -p "${kube_dir}"
        done

        scp::execute -r \
                     -h "${first_node_ip}" \
                     -s "/usr/local/bin/kubectl" \
                     -d "/usr/local/bin/kubectl"

        scp::execute -r \
                     -h "${first_node_ip}" \
                     -s "/root/.kube/config" \
                     -d "/root/.kube/config"

        LOG debug "Copying '${KUBE_CONFIG_DIR}' from ${first_node_ip} ..."
        scp::execute -r \
                     -h "${first_node_ip}" \
                     -s "${KUBE_CONFIG_DIR}" \
                     -d "/etc/"
    fi
fi
