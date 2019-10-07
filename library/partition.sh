#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


function disk::partition() {
    local role_name="${1}"
    local hosts=(${2//,/ })
    local vg_name="${3}"
    local lv_names_array=(${4//,/ })
    local lv_ratios_array=(${5//,/ })
    local mount_points_array=(${6//,/ })

    if [[ $# -ne 6 ]]; then
        LOG error "Function disk::partition() needs 6 parameters!"
        return 1
    fi

    if ! [[ "${#lv_names_array[@]}" -eq "${#lv_ratios_array[@]}" && \
            "${#lv_names_array[@]}" -eq "${#mount_points_array[@]}" ]]; then
        LOG error "The numbers of lv_names, lv_ratios and mount_points MUST be the same!"
        return 2
    fi

    tatal_ratios_exp=$(sed "s/ /+/g" <<< "${lv_ratios_array[@]}")
    total_ratios_used=$(python <<< "print(int((${tatal_ratios_exp}) * 100))")
    if ((total_ratios_used >= 98)); then
        LOG error "The total ratios used for all the LVs can NOT be larger than 98%!"
        return 3
    fi

    local mapper_files_array=()
    local max_mapper_len_exp=""
    local max_mount_point_len_exp=""

    for idx in "${!lv_names_array[@]}"; do
        local lv_name="${lv_names_array[${idx}]}"
        local lv_ratio="${lv_ratios_array[${idx}]}"
        local mount_point="${mount_points_array[${idx}]}"

        mapper_file="/dev/mapper/${vg_name//-/--}-${lv_name//-/--}"
        mapper_files_array+=(${mapper_file})
        max_mapper_len_exp+="${#mapper_file},"
        max_mount_point_len_exp+="${#mount_point},"
    done

    max_mapper_len=$(python <<< "print(max([${max_mapper_len_exp%,}]))")
    max_mount_point_len=$(python <<< "print(max([${max_mount_point_len_exp%,}]))")

    local info_msg
    info_msg+="The preview of all the LVs' mount infos on selected ${role_name^^}:\n"
    info_msg+="$(printf "%-${max_mapper_len}s" "File-System") "
    info_msg+="$(printf "%-${max_mount_point_len}s" "Mount-Point") "
    info_msg+="Type Capacity(percent%)"

    for idx in "${!lv_names_array[@]}"; do
        lv_name="${lv_names_array[${idx}]}"
        lv_ratio="${lv_ratios_array[${idx}]}"
        mapper_file="${mapper_files_array[${idx}]}"
        mount_point="${mount_points_array[${idx}]}"

        info_msg+="\n"
        info_msg+="$(printf "%-${max_mapper_len}s" ${mapper_file}) "
        info_msg+="$(printf "%-${max_mount_point_len}s" ${mount_point}) "
        info_msg+="$(printf "%-5s" "xfs")"
        info_msg+="$(python <<< "print(${lv_ratio} * 100)")%"
    done

    LOG info "${info_msg}"
    local answer="y"
    if [[ "${ENABLE_FORCE_MODE,,}" == "false" ]]; then
        LOG warn "Auto-paratition the device using the configurations above" \
                 "on each ${role_name^^} will wipe all data!!"
        LOG warn -n "Is that all OK? [y/N]:"
        read answer
    fi

    if [[ "${answer,,}" != "y" ]]; then
        LOG warn "You have canceled to auto-paratition the device on each ${role_name^^}!"
        return 0
    fi

    local functions_file="${__KUBE_KIT_DIR__}/src/init/disk.sh"
    for host in "${hosts[@]}"; do
        ssh::execute -h "${host}" \
                     -s "${functions_file}" \
                     -- wipe_device
        ssh::execute -h "${host}" \
                     -s "${functions_file}" \
                     -- do_partition "${@:3}"
    done
}
