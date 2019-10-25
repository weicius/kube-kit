#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


function yum::create_local_repo() {
    current_ip="$(util::current_host_ip)"

    local local_repo_dir="/var/www/html/${LOCAL_YUM_REPO_NAME}"
    # NOTE: add `|| true` to ensure the command always return true.
    installed_httpd_rpms=$(rpm -qa | egrep -wc '(apr|httpd|mailcap)' || true)

    if [[ "${installed_httpd_rpms}" -ne 5 ]]; then
        LOG debug "Installing httpd from local rpms on ${current_ip} ..."
        yum install -y -q /opt/rpms/{httpd*,apr*,mailcap*}
    fi

    createrepo_regex="(createrepo|deltarpm|python-deltarpm|libxml2-python)"
    installed_createrepo_rpms=$(rpm -qa | egrep -wc "${createrepo_regex}" || true)
    if [[ "${installed_createrepo_rpms}" -ne 4 ]]; then
        LOG debug "Installing createrepo from local rpms on ${current_ip} ..."
        yum install -y -q /opt/rpms/{createrepo*,deltarpm*,python-deltarpm*,libxml2-python*}
    fi

    # modify the port which httpd listens.
    sed -i -r "s|^(Listen).*|\1 ${LOCAL_YUM_REPO_PORT}|" /etc/httpd/conf/httpd.conf

    util::start_and_enable httpd.service

    [[ -d "${local_repo_dir}" ]] && rm -rf "${local_repo_dir}"
    mkdir -p "${local_repo_dir}"

    cp /opt/rpms/* "${local_repo_dir}"

    LOG debug "Creating local repos using 'createrepo' command on ${current_ip} ..."
    createrepo "${local_repo_dir}" >/dev/null

    # need to stop and disable firewalld service.
    util::stop_and_disable firewalld.service

    iptables -F && iptables -F -t nat
    iptables -X && iptables -X -t nat

    rm -rf /opt/rpms/
}


function yum::generate_repo_file() {
    current_ip="$(util::current_host_ip)"
    local_yum_repo="http://${LOCAL_YUM_REPO_HOST}:${LOCAL_YUM_REPO_PORT}"
    LOG debug "Generating local yum repo file on ${current_ip} ..."
	cat > "/etc/yum.repos.d/${LOCAL_YUM_REPO_NAME}.repo" <<-EOF
	[kubernetes-dependent]
	name=Kubernetes Dependency Repository
	baseurl=${local_yum_repo}/${LOCAL_YUM_REPO_NAME}
	enabled=1
	gpgcheck=0
	EOF
}


function yum::backup_origin_repo() {
    yum clean all &>/dev/null || true
    local backup_dir="/etc/yum.repos.d/backup"
    [[ -d "${backup_dir}" ]] || mkdir -p "${backup_dir}"

    find /etc/yum.repos.d/ -maxdepth 1 -name '*.repo' -exec mv {} "${backup_dir}" \;
}


function yum::recover_origin_repo() {
    yum clean all &>/dev/null || true
    mv -f /etc/yum.repos.d/backup/* /etc/yum.repos.d/ &>/dev/null || true
    rm -rf /etc/yum.repos.d/backup &>/dev/null || true
}


function yum::prepare_local_repo() {
    current_ip="$(util::current_host_ip)"

    LOG info "Configurating to use local yum repo on ${current_ip} ..."
    yum::backup_origin_repo
    yum::generate_repo_file

    yum clean all &>/dev/null || true
    yum makecache &>/dev/null || true
    yum install -y bash-completion &>/dev/null || true
}


function yum::simulate_install() {
    current_ip="$(util::current_host_ip)"

    LOG debug "Simulating to install all the required packages on ${current_ip} ..."
    for pkg in "${KUBE_PKGS_ARRAY[@]}"; do
        rpm -qa | grep -q "^${pkg}-" && continue
        # check if something error occurs when simulating to install this package.
        yum install --assumeno "${pkg}" 2>&1 | \
            grep -Eq '^(Error:|Failed connect to)' || continue
        LOG error "${current_ip} can NOT install the package ${pkg} from localrepo!"
        printf '%0.s@' {1..100} && echo
        yum install --assumeno "${pkg}" >/dev/null
        printf '%0.s@' {1..100} && echo
        LOG error "It will NOT be succeed to deploy kubernetes for the reason above!"
        return 1
    done
}
