#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2044,SC2045,SC2153,SC2206,SC2207

VOLUME="__VOLUME__"
MNTDIR="__MNTDIR__"
CRONTAB_LOCK_FILE="__CRONTAB_LOCK_FILE__"
CRONTAB_LOGS_FILE="__CRONTAB_LOGS_FILE__"
KUBE_INJECT_IMAGE="__KUBE_INJECT_IMAGE__"
KUBE_MASTER_VIP="__KUBE_MASTER_VIP__"
KUBE_LOGS_DIR="__KUBE_LOGS_DIR__"
GLUSTERFS_NODE_NAME="__GLUSTERFS_NODE_NAME__"
PATH="${PATH}:/usr/local/bin"

master_services=(
    kube-apiserver
    kube-controller-manager
    kube-scheduler
    etcd
    docker
    nginx
    keepalived
    httpd
    sshd
)

node_services=(
    kubelet
    kube-proxy
    docker
    glusterd
    flanneld
    sshd
)


################################################################################
####################### definitions of library functions #######################
################################################################################

function LOG() {
    local level="${1}"
    local texts="${*:2}"

    echo "$(date +'%Y-%m-%d %H:%M:%S') [${level^^}] ${texts}"
}


function sleep_random() {
    local min_seconds="${1:-1}"
    local max_seconds="${2:-2}"

    local min_msec max_msec
    min_msec=$(python -c "print(int(${min_seconds} * 1000))")
    max_msec=$(python -c "print(int(${max_seconds} * 1000))")

    local total_msec
    total_msec=$((min_msec + RANDOM % (max_msec - min_msec)))
    sleep "$(printf '%d.%03d' $((total_msec / 1000)) $((total_msec % 1000)))s"
}


function keep_services_active() {
    local -a services=(${*})
    for service in "${services[@]}"; do
        systemctl list-unit-files | grep -q "${service}" || continue
        systemctl is-active "${service}" -q && continue
        LOG warn "The service ${service} is not active, trying to restart it ..."
        systemctl restart "${service}"
    done
}

##########################################################################################
##################### crontab jobs executed on all the k8s-masters #######################
##########################################################################################

# this job is executed every minute.
function keep_master_services_active() {
    sleep_random 1 10
    keep_services_active "${master_services[@]}"
}


# this job is executed every minute.
function keep_master_vip_existed() {
    systemctl list-unit-files | grep -q keepalived || return
    ping -c 4 -W 1 -i 0.05 "${KUBE_MASTER_VIP}" &>/dev/null && return
    LOG error "KUBE_MASTER_VIP <${KUBE_MASTER_VIP}> is lost, restarting keepalived ..."
    systemctl daemon-reload && systemctl restart keepalived
}


# this job is executed every day.
function backup_heketi_db() {
    sleep_random 20 30

    local heketi_backup_dir="/var/backup/heketi"
    local heketi_db_dir="${MNTDIR}/heketi/db"
    heketi_backup_filename="heketi-$(hostname)-$(date +'%Y-%m-%d').db.tar.gz"
    heketi_backup_file="${heketi_backup_dir}/${heketi_backup_filename}"

    [[ -d "${heketi_db_dir}" ]] || return 0
    [[ -d "${heketi_backup_dir}" ]] || mkdir -p "${heketi_backup_dir}"

    # delete backup files which are older than 30 days.
    find "${heketi_backup_dir}" -type f -mtime +30 -exec rm -f {} +

    LOG info "Creating the heketi backupfile <${heketi_backup_file}> ..."
    tar -C "${heketi_db_dir}" -czf "${heketi_backup_file}" heketi.db
}


##########################################################################################
###################### crontab jobs executed on all the k8s-nodes ########################
##########################################################################################

# this job is executed every minute.
function keep_node_services_active() {
    sleep_random 30 40
    keep_services_active "${node_services[@]}"
}


# this job is executed every minute.
function auto_mount_heketi_bricks() {
    [[ -f /etc/heketi/fstab ]] || return 0
    grep -q heketi /etc/heketi/fstab || return 0
    df -hT | grep -q /var/lib/heketi || return 0

    LOG info "Auto-mount all bricks of heketi onboot!"
    mount --all --fstab /etc/heketi/fstab

    status_regex="[0-9a-f]+/brick\s+N/A\s+N/A\s+N\s+N/A"
    for idx in $(seq 10); do
        if ! systemctl is-active glusterd.service -q; then
            systemctl restart glusterd.service
            sleep "$((2 ** (idx -1)))"
        # just restart glusterd.service if one brick is offline.
        elif gluster volume status |& grep -qP "${status_regex}"; then
            LOG warn "There exist bricks which are offline," \
                     "restarting glusterd.service!"
            systemctl restart glusterd.service
            sleep "$((2 ** (idx -1)))"
        else
            return 0
        fi
    done
}


# this job is executed every minute.
function auto_mount_shared_volume() {
    if [[ -z "${GLUSTERFS_NODE_NAME}" ]]; then
        return 0
    elif mount | grep -q "${VOLUME}"; then
        return 0
    elif ! systemctl is-active glusterd.service -q; then
        LOG error "glusterd is not active now, do nothing ..."
        return 1
    elif ! gluster volume info "${VOLUME}" &>/dev/null; then
        LOG error "<${VOLUME}> is not ready, do nothing ..."
        return 2
    fi

    LOG debug "<${VOLUME}> is ready now, mounting it on ${MNTDIR} ..."
    mount -t glusterfs "${GLUSTERFS_NODE_NAME}:${VOLUME}" "${MNTDIR}"
}


# this job is executed every minute.
function delete_not_k8s_containers() {
    for container_id in $(docker ps -a | grep -v k8s | sed '1d' | awk '{print $1}'); do
        image_name=$(docker inspect "${container_id}" --format='{{.Config.Image}}')
        [[ "${image_name}" == "${KUBE_INJECT_IMAGE}" ]] && continue
        LOG warn "Deleting the container NOT created by k8s: <${container_id}>" \
                 "using the image: <${image_name}>"
        docker rm -f "${container_id}" &>/dev/null
    done
}


# this job is executed every hour.
function delete_dangling_images() {
    for image in $(docker images --filter dangling=true -q); do
        docker rmi "${image}" &>/dev/null
    done
}


# this job is executed every hour.
function delete_containers_logs() {
    for container_dir in /var/lib/docker/containers/*; do
        container_id="${container_dir##*/}"
        container_log_file="${container_dir}/${container_id}-json.log"
        [[ -f "${container_log_file}" ]] || continue

        container_log_line=$(wc -l "${container_log_file}" | awk '{print $1}')
        container_log_line_ahalf="$((container_log_line / 2))"

        container_log_size=$(du -b "${container_log_file}" | awk '{print $1}')
        container_log_size_mb="$((container_log_size / 1024 ** 2))"

        # delete the first half logs of the container if logfile exceeds 10MB.
        [[ "${container_log_size_mb}" -gt 10 ]] || continue
        sed -i "1,${container_log_line_ahalf}d" "${container_log_file}"

        # fetch the name and namespace of the pod from the name of container.
        docker_container_name=$(docker inspect --format='{{.Name}}' "${container_id}")
        k8s_container_name=$(cut -d '_' -f 2 <<< "${docker_container_name}")
        k8s_pod_name=$(cut -d '_' -f 3 <<< "${docker_container_name}")
        k8s_pod_namespace=$(cut -d '_' -f 4 <<< "${docker_container_name}")

        [[ -n "${k8s_pod_name}" && -n "${k8s_pod_namespace}" ]] || continue
        LOG warn "The logfile size of the container <${k8s_container_name}> in" \
                 "the pod <${k8s_pod_name}> in the namespace <${k8s_pod_namespace}>" \
                 "exceed 10MB (${container_log_size_mb}MB)! Delete the first half" \
                 "(${container_log_line_ahalf} lines) logs to reduce the logfile size!"
    done
}


# this job is executed every hour.
function delete_kubernetes_logs() {
    # get all reguler files in /var/log/kubernetes
    for log_file in $(find "${KUBE_LOGS_DIR}" -type f ! -type l); do
        for link_file in $(find "${KUBE_LOGS_DIR}" -type l); do
            real_file=${KUBE_LOGS_DIR}/$(readlink "${link_file}")
            # if other symbolic link is linking to current log file,
            # just skip it.
            [[ "${real_file}" == "${log_file}" ]] && continue 2
        done
        # if current log file is created 30 days ago, just delete it.
        find "${KUBE_LOGS_DIR}" -name "${log_file##*/}" -mtime +30 -exec rm -f {} +
    done
}


##########################################################################################
############################## some other util functions #################################
##########################################################################################


# NOTE: the outer parenthesis '()' is the capture group of regex.
# it MUST be within double quotes, or it will be part of an array.
all_functions_regex="($(declare -f | grep -oP '^\w+' | paste -sd '|'))"

if [[ "${1}" =~ ^${all_functions_regex}$ ]]; then
    func_name="${1}"
else
    LOG error "Usage: $0 ${all_functions_regex} [other arguments]"
    exit 1
fi


if grep -q "${func_name}" "${CRONTAB_LOCK_FILE}"; then
    LOG warn "The same job <${func_name}> is executing now, skipping ..."
    exit 0
fi

echo "${func_name}" >> "${CRONTAB_LOCK_FILE}"
eval -- "${@}" 2>/dev/null | tee -a "${CRONTAB_LOGS_FILE}"
sed -i "/${func_name}/d" "${CRONTAB_LOCK_FILE}"
