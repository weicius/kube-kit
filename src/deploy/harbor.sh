#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function harbor_images_are_loaded() {
    harbor_images_num=$(docker images 2>/dev/null |\
        grep -c "^vmware.*${HARBOR_VERSION}" || true)
    # we actually only need 8 images of harbor:
    # vmware/harbor-{adminserver,db,jobservice,redis,registry,ui,nginx,cli}:${HARBOR_VERSION}
    [[ "${harbor_images_num}" -eq 8 ]]
}


function load_harbor_images() {
    local harbor_images_filename="${1}"
    docker load -i "${harbor_images_filename}" >/dev/null
    rm -f "${harbor_images_filename}"
}


function config_harbor_cli() {
    sed -i '/harbor/d' /root/.bashrc
    echo "alias harbor=\"${HARBOR_CLI}\"" >> /root/.bashrc
}


function create_addon_project() {
    ${HARBOR_CLI} project-create --is-public true "${KUBE_ADDON_IMAGES_PROJECT}"
}


function push_images() {
    # e.g. library-images.tar.gz
    local compressed_image_filename="${1}"
    # e.g. /tmp/library-images.tar.gz
    local compressed_image_file="/tmp/${compressed_image_filename}"
    # e.g. /tmp/library-images
    local compressed_image_dir="${compressed_image_file/.tar.gz/}"

    LOG info "Trying to login to ${HARBOR_REGISTRY} using admin ..."
    docker login -u admin -p "${HARBOR_ADMIN_PASSWORD}" \
           "${HARBOR_REGISTRY}" 2>/dev/null

    LOG info "Uncompressing ${compressed_image_file} ..."
    rm -rf "${compressed_image_dir}"
    tar -zxvf "${compressed_image_file}" -C /tmp
    rm -f "${compressed_image_file}"

    # skip the empty directory.
    [[ -z $(ls -A "${compressed_image_dir}") ]] && return 0

    # push addon, aistack, ailab and preloaded
    # images into the kube-system repo.
    local images_repo="${KUBE_ADDON_IMAGES_REPO}"
    if [[ "${compressed_image_dir}" =~ library ]]; then
        images_repo="${KUBE_LIBRARY_IMAGES_REPO}"
    fi

    # sort the files by size in reverse order, i.e. smallest first
    for image_tar_file in $(ls -Sr ${compressed_image_dir}/*.tar 2>/dev/null); do
        image_tar_filename="${image_tar_file##*/}"
        image_name="${image_tar_filename/.tar/}"
        new_image_name="${images_repo}/${image_name}"

        LOG debug "Pushing the image: ${new_image_name} ..."
        docker load -i "${image_tar_file}" >/dev/null
        docker tag  "${image_name}" "${new_image_name}" >/dev/null
        docker rmi  "${image_name}" >/dev/null
        docker push "${new_image_name}" >/dev/null
    done

    rm -rf "${compressed_image_dir}"
}
