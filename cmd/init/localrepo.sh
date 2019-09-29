#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/init/localrepo.sh"
local_rpms_dir="${__KUBE_KIT_DIR__}/binaries/rpms"
local_yum_repo="http://${LOCAL_YUM_REPO_HOST}:${LOCAL_YUM_REPO_PORT}"

if curl "${local_yum_repo}" &>/dev/null; then
    answer="y"
    if [[ "${ENABLE_FORCE_MODE,,}" != "true" ]]; then
        LOG warn -n "Local yum repo is running on ${local_yum_repo}," \
                    "re-create it? [Y/n]: "
        read answer
    fi
    [[ "${answer,,}" != "y" ]] && exit 0
fi

if [[ ! -d "${local_rpms_dir}" ]]; then
    LOG error "Local rpms directory '${local_rpms_dir}' does NOT exist!"
    exit 1
fi

for pkg in httpd createrepo sshpass; do
    if ! find "${local_rpms_dir}" -name "${pkg}*.rpm" &>/dev/null; then
        LOG error "Local ${pkg} rpms in '${local_rpms_dir}' does NOT exist!"
        exit 2
    fi
done

# find binaries/rpms/ -name '*.rpm' -exec basename {} \; | sort
# find /var/www/html/kubernetes/ -name '*.rpm' -printf '%f\n' | sort
ssh::execute -h "${LOCAL_YUM_REPO_HOST}" "rm -rf /opt/rpms"

LOG info "Copying all the offline rpms to ${LOCAL_YUM_REPO_HOST} ..."
scp::execute -h "${LOCAL_YUM_REPO_HOST}" \
             -s "${local_rpms_dir}" \
             -d "/opt/"

LOG info "Creating the local yum repo on ${LOCAL_YUM_REPO_HOST} ..."
ssh::execute -h "${LOCAL_YUM_REPO_HOST}" \
             -s "${functions_file}" \
             -- "yum::create_local_repo"

LOG info "Configurating to use the local yum repo on all the hosts ..."
ssh::execute_parallel -h "all" \
                      -s "${functions_file}" \
                      -- "yum::prepare_local_repo"
