#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

declare -a target_hosts=(${@})

check_env_func_file="${__KUBE_KIT_DIR__}/src/check/env.sh"
init_localrepo_func_file="${__KUBE_KIT_DIR__}/src/init/localrepo.sh"

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
                      -s "${check_env_func_file}" \
                      -- "check::networks"

LOG info "Checking if the standalone device on all hosts exists ..."
ssh::execute_parallel -h "${target_hosts[@]}" \
                      -s "${check_env_func_file}" \
                      -- "check::k8s_disks"

if [[ "${ENABLE_GLUSTERFS,,}" == "true" && "${#HEKETI_NODE_IPS_ARRAY[@]}" -gt 0 ]]; then
    LOG info "Checking if all the disks for heketi for glusterfs cluster exist ..."
    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${check_env_func_file}" \
                          -- "check::heketi_disks"
fi

if [[ "${ENABLE_LOCAL_YUM_REPO,,}" == "true" ]]; then
    LOG info "Checking if the distro release of all hosts are CentOS-${CENTOS_VERSION} ..."
    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${check_env_func_file}" \
                          -- "check::distro"

    LOG info "Checking if all the hosts can install the required packages ..."
    LOG debug "Backing up the configuration files of origin yum repos on all hosts ..."
    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${init_localrepo_func_file}" \
                          -- "yum::backup_origin_repo"

    if curl "http://${LOCAL_YUM_REPO_HOST}:${LOCAL_YUM_REPO_PORT}" &>/dev/null; then
        local_repo_exists="true"
    fi

    if [[ "${local_repo_exists}" == "true" ]]; then
        ssh::execute_parallel -h "${target_hosts[@]}" \
                              -s "${init_localrepo_func_file}" \
                              -- "yum::generate_repo_file"
    else
        LOG info "Simulating the operation of 'kube-kit init localrepo' ..."
        source "${__KUBE_KIT_DIR__}/cmd/init/localrepo.sh" >/dev/null
    fi

    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${init_localrepo_func_file}" \
                          -- "yum::simulate_install" | tee /dev/null

    # NOTE: need to ensure the command above always succeed!
    # and also need to use a variable to record the exitcode.
    # if the command yum::simulate_install exits immediately,
    # the following action to cleanup will never be executed,
    # which is NOT acceptant.
    yum_simulate_install_exitcode="${PIPESTATUS[0]}"

    if [[ "${local_repo_exists}" != "true" ]]; then
        LOG info "Cleaning up local yum repos on ${LOCAL_YUM_REPO_HOST} ..."
        ssh::execute -h "${LOCAL_YUM_REPO_HOST}" -- "
            yum remove httpd -y &>/dev/null && rm -rf /var/www/html/
        "
        ssh::execute_parallel -h "${target_hosts[@]}" -- "
            rm -f /etc/yum.repos.d/${LOCAL_YUM_REPO_NAME}.repo
        "
    fi

    LOG info "Recovering the configuration files of origin yum repos on all hosts ..."
    ssh::execute_parallel -h "${target_hosts[@]}" \
                          -s "${init_localrepo_func_file}" \
                          -- "yum::recover_origin_repo"

    # if failed to execute simulate_install, just exit to skip the following commands.
    if [[ "${yum_simulate_install_exitcode}" -ne 0 ]]; then
        exit "${yum_simulate_install_exitcode}"
    fi
fi
