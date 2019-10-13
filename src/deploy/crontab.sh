#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function config_kube_scripts() {
    sed -i -r \
        -e "s|__VOLUME__|${KUBE_SHARED_VOLUME_NAME}|" \
        -e "s|__MNTDIR__|${KUBE_SHARED_VOLUME_MNT_DIR}|" \
        -e "s|__CRONTAB_LOCK_FILE__|${CRONTAB_LOCK_FILE}|" \
        -e "s|__CRONTAB_LOGS_FILE__|${CRONTAB_LOGS_FILE}|" \
        -e "s|__KUBE_INJECT_IMAGE__|${KUBE_INJECT_IMAGE}|" \
        -e "s|__KUBE_MASTER_VIP__|${KUBE_MASTER_VIP}|" \
        -e "s|__KUBE_LOGS_DIR__|${KUBE_LOGS_DIR}|" \
        -e "s|__GLUSTERFS_NODE_NAME__|$(util::get_glusterfs_node_name)|" \
        /usr/local/bin/kube-crontab

    sed -i -r \
        -e "s|^(SSHD_PORT)=.*|\1=\"${SSHD_PORT}\"|" \
        /usr/local/bin/kube-devops

    sed -i -r \
        -e "s|__KUBE_PKI_DIR__|${KUBE_PKI_DIR}|" \
        -e "s|__KUBE_INJECT_IMAGE__|${KUBE_INJECT_IMAGE}|" \
        -e "s|__DOCKER_DAEMON_PORT__|${DOCKER_DAEMON_PORT}|" \
        /usr/local/bin/kube-inject

    chmod +x /usr/local/bin/kube-{crontab,devops,inject}
}


function config_crond_service() {
    local crond_service="/usr/lib/systemd/system/crond.service"
    local post_cmd="/usr/bin/bash -c 'true > ${CRONTAB_LOCK_FILE}'"

    # NOTE:
    # 1). here, we take advantage of ExecStartPost of systemd to
    # ensure that the lock file exist and keep empty when crond
    # start in case crond stops accidentally or system reboots,
    # in which situation the contents in lock file always exist
    # and the abnormally terminated job will never be executed!
    # 2). systemd does not use a shell to execute ExecStartPost
    # commands and does not perform $PATH lookup, so we need to
    # use this specifical form: /usr/bin/bash -c 'commands'.

    sed -i "/ExecStartPost/d" "${crond_service}"
    sed -i "/ExecReload/aExecStartPost=${post_cmd}" "${crond_service}"

    # stop crond from sending emails for each job.
    sed -i -r 's|^(MAILTO)=.*|\1=""|' /etc/crontab
    # disable all mails for crond.
    sed -i -r 's|^(CRONDARGS)=.*|\1=-m off|' /etc/sysconfig/crond

    util::start_and_enable crond.service
}


function set_crontab_for_k8s_masters() {
    local kube_crontab="/usr/local/bin/kube-crontab"

    if [[ "${KUBE_MASTER_IPS_ARRAY_LEN}" -gt 1 ]]; then
        sed -i -r '/keep_master_vip_existed/d' /etc/crontab
        cat >> /etc/crontab <<-EOF
		* * * * * root ${kube_crontab} keep_master_vip_existed
		EOF
    fi

    sed -i -e '/keep_master_services_active/d' \
           -e '/backup_heketi_db/d' \
           -e '/delete_kubernetes_logs/d' \
           /etc/crontab
    cat >> /etc/crontab <<-EOF
	* * * * * root ${kube_crontab} keep_master_services_active
	0 4 * * * root ${kube_crontab} backup_heketi_db
	0 * * * * root ${kube_crontab} delete_kubernetes_logs
	EOF
}


function set_crontab_for_k8s_nodes() {
    local kube_crontab="/usr/local/bin/kube-crontab"

    sed -i -e '/auto_mount_heketi_bricks/d' \
           -e '/auto_mount_shared_volume/d' \
           -e '/keep_node_services_active/d' \
           -e '/delete_not_k8s_containers/d' \
           -e '/delete_dangling_images/d' \
           -e '/delete_containers_logs/d' \
           -e '/delete_kubernetes_logs/d' \
           /etc/crontab
    cat >> /etc/crontab <<-EOF
	* * * * * root ${kube_crontab} auto_mount_heketi_bricks
	* * * * * root ${kube_crontab} auto_mount_shared_volume
	* * * * * root ${kube_crontab} keep_node_services_active
	* * * * * root ${kube_crontab} delete_not_k8s_containers
	0 * * * * root ${kube_crontab} delete_dangling_images
	1 * * * * root ${kube_crontab} delete_containers_logs
	2 * * * * root ${kube_crontab} delete_kubernetes_logs
	EOF
}
