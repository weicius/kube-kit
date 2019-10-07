#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


function remove_lv() {
    local device="${1}"
    local pv="${2}"
    local vg="${3}"
    local lv="${4}"
    current_ip="$(util::current_host_ip)"

    LOG info "There exists a lv ${lv} in the vg ${vg} in the pv ${pv}" \
             "in the device ${device} on ${current_ip}!"
    # skip to force umount the heketi disks, because these lvs will
    # not be auto-mounted after cleaning the kubernetes cluster.
    heketi_devices=(${HEKETI_DISKS_ARRAY[${current_ip}]})
    if ! util::element_in_array "${device}" "${heketi_devices[@]}"; then
        mapper_file="$(util::get_mapper_file ${vg} ${lv})"
        if [[ -z "${mapper_file}" ]]; then
            LOG error "Failed to get mapper file of lv ${lv} of vg ${vg}!"
            return 1
        elif ! lvdisplay "${mapper_file}" | grep -q 'LV Pool'; then
            mount_point=$(mount | grep "${mapper_file}" | awk '{print $3}')
            if [[ -n "${mount_point}" ]]; then
                LOG warn "The lv ${lv} has been mounted on ${mount_point}!"
                util::force_umount "${mapper_file}"
            fi
        fi
    fi

    LOG_EMPHASIZE warn "#" "Removing the lv ${lv} in the vg ${vg} in the pv" \
                  "${pv} in the device ${device} on ${current_ip} by force ..."
    lvremove -f "/dev/${vg}/${lv}"
    util::sleep_random
}


function remove_vg() {
    local device="${1}"
    local pv="${2}"
    local vg="${3}"
    current_ip="$(util::current_host_ip)"

    LOG info "There exists a vg ${vg} in the pv ${pv} in the" \
             "device ${device} on ${current_ip}!"
    for lv in $(lvs -o +devices | grep "${vg}" | awk '{print $1}' | uniq); do
        remove_lv "${device}" "${pv}" "${vg}" "${lv}"
    done

    LOG_EMPHASIZE warn '$' "Removing the vg ${vg} in the pv ${pv} in the" \
                  "device ${device} on ${current_ip} by force ..."
    vgremove -f "${vg}"
    util::sleep_random
}


function remove_pv() {
    local device="${1}"
    local pv="${2}"
    current_ip="$(util::current_host_ip)"

    LOG info "There exists a pv ${pv} in the device ${device} on ${current_ip}!"
    # NOTE: the condition `if(NF==7)` is necessary when the pv has no vgs.
    # can not use `vgs -o +devices | grep "${pv}" | awk '{print $1}' | uniq`
    # because `vgs -o +devices` can not list the vg and the pv of glusterfs.
    # the devices of glusterfs' vg is none or tp_xxx, NOT the pv's name!
    for vg in $(pvs -o +devices | grep "${pv}" | awk '{if(NF==7) print $2}' | uniq); do
        remove_vg "${device}" "${pv}" "${vg}"
    done

    LOG_EMPHASIZE warn '@' "Removing the pv ${pv} in device ${device}" \
                  "on ${current_ip} by force ..."
    pvremove -f "${pv}"
    util::sleep_random
}


function remove_8e_partitions() {
    local device="${1}"
    # remove all the lvs, vgs and pvs existed in this device.
    for pv in $(pvs -o +devices | grep "${device}" | awk '{print $1}' | uniq); do
        remove_pv "${device}" "${pv}"
    done
}


function remove_83_partitions() {
    local device="${1}"
    mount_points=($(lsblk -npr "${device}" | awk '{if($6=="part" && NF==7) print $7}'))
    [[ "${#mount_points[@]}" -eq 0 ]] && return 0

    for mount_point in "${mount_points[@]}"; do
        had_83_partitions="true"
        partition=$(lsblk -npr "${device}" | grep -oP "^\S+(?=.*${mount_point})")
        blocktype=$(blkid "${partition}" | sed 's/"//g' | grep -oP '(?<= TYPE=).*')
        [[ "${blocktype}" == "LVM2_member" ]] && continue
        LOG warn "The partition ${partition} on ${current_ip} is a normal partition!"
        util::force_umount "${partition}"
    done

    # need to remove the metadata of normal partitions.
    dd if=/dev/zero of="${device}" bs=1M count=1
}


function get_block_label() {
    parted -s "${1}" print 2>/dev/null | grep -oP '(?<=Partition Table: ).*'
}


function wipe_device() {
    current_ip="$(util::current_host_ip)"
    device="${KUBE_DISKS_ARRAY[${current_ip}]}"

    # install some packages to deal with disk partitions if necessary.
    for pkg in device-mapper-persistent-data lvm2 parted; do
        rpm -qa | grep -q "${pkg}" || yum install -y -q "${pkg}"
    done

    # check if there is a standalone device or not.
    if ! lsblk "${device}" &>/dev/null; then
        LOG error "device ${device} on ${current_ip} does NOT exist!"
        return 1
    fi

    LOG warn "Trying to wipe the device ${device} on ${current_ip} now ..."

    remove_83_partitions "${device}"
    remove_8e_partitions "${device}"

    [[ "${KUBE_WIPE_DEVICE_COMPLETELY,,}" != "true" ]] && return 0

    LOG warn "Wiping the complete device ${device} by force ..."
    if [[ "${KUBE_WIPE_DEVICE_METHOD,,}" == "shred" ]]; then
        shred -n "${KUBE_SHRED_ITERATIONS:-2}" -fvz "${device}"
    else
        device_size_in_mb=$(($(lsblk -bdn -o SIZE "${device}") / 1024 ** 2))
        # wipefs --all --force "${device}"
        dd if=/dev/zero of="${device}" bs=1M count="${device_size_in_mb}"
    fi
}


# configure the direct-lvm for dockerd's storage driver when using devicemapper.
# references:
# https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver
# https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-manually
function config_direct_lvm() {
    local vg_name="${1}"
    local lv_name="${2}"
    local lv_ratio="${3}"
    local mount_point="${4}"

    current_ip="$(util::current_host_ip)"
    device="${KUBE_DISKS_ARRAY[${current_ip}]}"
    device_size_in_gb="$(util::device_size_in_gb ${device})"

    LOG info "Configuring the direct-lvm because dockerd use devicemapper as storage driver ..."
    thinpool_name="${lv_name}_thinpool"
    thinpool_metadata_name="${lv_name}_thinpool_metadata"
    thinpool_size_in_gb=$(python <<< "print(${device_size_in_gb} * ${lv_ratio} * 0.9)")
    thinpool_metadata_size_in_gb=$(python <<< "print(${device_size_in_gb} * ${lv_ratio} * 0.01)")

    LOG info "Creating a new lv ${thinpool_name} as the thinpool of direct-lvm ..."
    lvcreate -y -Wy -Zy \
             -L "${thinpool_size_in_gb}G" \
             -n "${thinpool_name}" "${vg_name}"

    util::sleep_random
    LOG info "Creating a new lv ${thinpool_metadata_name} as the thinpool_metadata of direct-lvm ..."
    lvcreate -y -Wy -Zy \
             -L "${thinpool_metadata_size_in_gb}G" \
             -n "${thinpool_metadata_name}" "${vg_name}"

    util::sleep_random
    LOG info "Converting the volumes to a thin pool and a storage location for metadata for the thin pool ..."
    lvconvert -y --zero n -c 512K \
              --thinpool "${vg_name}/${thinpool_name}" \
              --poolmetadata "${vg_name}/${thinpool_metadata_name}"

    # configure autoextension of thin pools via an lvm profile.
    # thin_pool_autoextend_threshold is the percentage of space used before lvm attempts
    # to autoextend the available space (100 = disabled, not recommended).
    # thin_pool_autoextend_percent is the amount of space to add to the disk when
    # automatically extending (0 = disabled).
	cat >/etc/lvm/profile/docker-thinpool.profile <<-EOF
	activation {
	    thin_pool_autoextend_threshold = 80
	    thin_pool_autoextend_percent = 20
	}
	EOF

    # apply the LVM profile.
    lvchange --metadataprofile docker-thinpool "${vg_name}/${thinpool_name}"

    # Enable monitoring for logical volumes on your host. Without this step,
    # automatic extension will not occur even in the presence of the LVM profile.
    lvs -o+seg_monitor
}


function config_normal_lvm() {
    local vg_name="${1}"
    local lv_name="${2}"
    local lv_ratio="${3}"
    local mount_point="${4}"

    current_ip="$(util::current_host_ip)"
    device="${KUBE_DISKS_ARRAY[${current_ip}]}"
    device_size_in_gb="$(util::device_size_in_gb ${device})"

    # calculate the requird size of current lv.
    lv_size_in_gb=$(python <<< "print(${device_size_in_gb} * ${lv_ratio})")

    LOG info "Creating a new lv ${lv_name} with the size ${lv_size_in_gb}G ..."
    lvcreate -y -Wy -Zy -L "${lv_size_in_gb}G" -n "${lv_name}" "${vg_name}"
    util::sleep_random

    # references:
    # 1. https://github.com/moby/moby/issues/27358
    # 2. https://github.com/moby/moby/issues/31283
    # 3. https://github.com/moby/moby/issues/31445
    # 4. https://github.com/moby/moby/pull/27433
    # 5. https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/7.2_Release_Notes/technology-preview-file_systems.html
    # 6. https://docs.docker.com/engine/userguide/storagedriver/overlayfs-driver
    # 7. https://docs.docker.com/storage/storagedriver/overlayfs-driver/
    # make a new xfs file system using the new-created partition.
    LOG info "Making the xfs filesystem for the lv ${lv_name} ..."
    mkfs.xfs -f -n ftype=1 "/dev/${vg_name}/${lv_name}"
    util::sleep_random

    mapper_file="$(util::get_mapper_file ${vg_name} ${lv_name})"
    # remove the files in directory for the mount_point if necessary.
    [[ -d "${mount_point}" ]] && util::romove_contents "${mount_point}"
    mkdir -p "${mount_point}"

    # ref: https://forums.docker.com/t/storage-quota-per-container-overlay2-backed-by-xfs/37653
    # now, we can limit the capacity of the / partition within docker container:
    # docker run --rm --storage-opt size=5G busybox sh -c 'df -h | grep /$'
    # overlay                   5.0G      8.0K      5.0G   0% /
    # docker run --rm busybox sh -c 'df -h | grep /$'
    # overlay                  90.0G     11.8G     78.1G  13% /

    mount -o pquota,uquota "${mapper_file}" "${mount_point}"

    # write the mount information to /etc/fstab for auto-mounting onboot.
    sed -i "\|${mapper_file}|d" /etc/fstab
    LOG info "The mount information for ${mapper_file}:"
    echo "${mapper_file} ${mount_point} xfs pquota,uquota 0 0" | tee -a /etc/fstab
}


function do_partition() {
    local vg_name="${1}"
    local lv_names_array=(${2//,/ })
    local lv_ratios_array=(${3//,/ })
    local mount_points_array=(${4//,/ })

    current_ip="$(util::current_host_ip)"
    device="${KUBE_DISKS_ARRAY[${current_ip}]}"

    LOG title "Auto-paratition the device ${device} on ${current_ip} now ..."
    LOG info "Creating a new pv ${device} using device ${device} ..."
    pvcreate -y "${device}"
    util::sleep_random

    LOG info "Creating a new vg ${vg_name} using pv ${device} ..."
    vgcreate -y "${vg_name}" "${device}"
    util::sleep_random

    for ((idx = 0; idx < ${#lv_names_array[@]}; idx++)); do
        local lv_name="${lv_names_array[${idx}]}"
        local lv_ratio="${lv_ratios_array[${idx}]}"
        local mount_point="${mount_points_array[${idx}]}"
        local partition_func="config_normal_lvm"

        if [[ "${DOCKER_STORAGE_DRIVER}" == "devicemapper" && \
              "${DOCKER_WORKDIR}" == "${mount_point}" ]]; then
            partition_func="config_direct_lvm"
        fi

        "${partition_func}" "${vg_name}" \
                            "${lv_name}" \
                            "${lv_ratio}" \
                            "${mount_point}"
    done
}
