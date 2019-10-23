#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2044,SC2045,SC2153,SC2206,SC2207

# how to generate the .tar.gz compressed file of necessary harbor images?
# $ HARBOR_VERSION=v1.5.3
# $ docker build --force-rm=true --rm=true --no-cache --tag vmware/harbor-cli:${HARBOR_VERSION} /root/kube-kit/addons/harbor
#
# $ harbor_installer=harbor-offline-installer-${HARBOR_VERSION}.tgz
# $ curl -LO https://storage.googleapis.com/harbor-releases/${harbor_installer}
# $ tar -xzvf ${harbor_installer}
#
# $ docker load -i harbor/harbor.${HARBOR_VERSION}.tar.gz
#
# $ docker tag vmware/{redis-photon,harbor-redis}:${HARBOR_VERSION}
# $ docker rmi vmware/redis-photon:${HARBOR_VERSION}
#
# $ docker tag vmware/{nginx-photon,harbor-nginx}:${HARBOR_VERSION}
# $ docker rmi vmware/nginx-photon:${HARBOR_VERSION}
#
# $ docker tag vmware/registry-photon:v2.6.2-${HARBOR_VERSION} vmware/harbor-registry:${HARBOR_VERSION}
# $ docker rmi vmware/registry-photon:v2.6.2-${HARBOR_VERSION}
#
# $ docker save vmware/harbor-{adminserver,db,jobservice,redis,registry,ui,nginx,cli}:${HARBOR_VERSION} | gzip > harbor-images-${HARBOR_VERSION}.tar.gz

functions_file="${__KUBE_KIT_DIR__}/src/deploy/harbor.sh"
harbor_binary_dir="${__KUBE_KIT_DIR__}/binaries/harbor"
harbor_images_filename="harbor-images-${HARBOR_VERSION}.tar.gz"

harbor_dir="${__KUBE_KIT_DIR__}/addon/harbor"
harbor_manifest_dir="${harbor_dir}/manifest"
harbor_config_dir="${KUBE_SHARED_VOLUME_MNT_DIR}/harbor"

harbor_ui_secret="$(util::random_string)"
jobservice_secret="$(util::random_string)"

################################################################################
##################### some util functions to deploy harbor #####################
################################################################################

function upload_harbor_images() {
    ssh::execute -q \
                 -h "${HOST}" \
                 -s "${functions_file}" \
                 -- "harbor_images_are_loaded" && return

    LOG debug "Loading all the harbor images on ${HOST} ..."
    scp::execute -h "${HOST}" \
                 -s "${harbor_binary_dir}/${harbor_images_filename}" \
                 -d "/tmp/${harbor_images_filename}"

    ssh::execute -h "${HOST}" \
                 -s "${functions_file}" \
                 -- "load_harbor_images" \
                    "/tmp/${harbor_images_filename}"
}


function vender_template_file() {
    local template_file="${1}"

    sed -i -r \
        -e "s|__GLUSTERFS_DEFAULT_SC__|${GLUSTERFS_DEFAULT_SC}|" \
        -e "s|__HARBOR_STORAGE_PVC_SIZE__|${HARBOR_STORAGE_PVC_SIZE}|" \
        -e "s|__HARBOR_VERSION__|${HARBOR_VERSION}|" \
        -e "s|__HARBOR_HOST__|${HARBOR_HOST}|" \
        -e "s|__KUBE_HARBOR_PORT__|${KUBE_HARBOR_PORT}|" \
        -e "s|__HARBOR_REGISTRY__|${HARBOR_REGISTRY}|" \
        -e "s|__HARBOR_CONFIG_DIR__|${harbor_config_dir}|" \
        -e "s|__HARBOR_MYSQL_ROOT_PASSWORD__|${HARBOR_MYSQL_ROOT_PASSWORD}|" \
        -e "s|__HARBOR_ADMIN_PASSWORD__|${HARBOR_ADMIN_PASSWORD}|" \
        -e "s|__HARBOR_UI_SECRET__|${harbor_ui_secret}|" \
        -e "s|__JOBSERVICE_SECRET__|${jobservice_secret}|" \
        "${template_file}"
}


function create_harbor_resources() {
    if kubectl get namespace harbor-system &>/dev/null; then
        kubectl delete namespace harbor-system
    fi

    kubectl create namespace harbor-system

    cp -f "${harbor_dir}/harbor-pvc.yaml" "${harbor_manifest_dir}"
    vender_template_file "${harbor_manifest_dir}/harbor-pvc.yaml"
    kubectl create -f "${harbor_manifest_dir}/harbor-pvc.yaml"

    # generate a shared secret key with 16 random characters [a-zA-Z0-9]{16}
    ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" -- "
        echo -n $(util::random_string 16) > ${harbor_config_dir}/key
    "

    for resource in {registry,db,adminserver,redis,jobservice,ui,nginx}; do
        cp -rf "${harbor_dir}/${resource}" "${harbor_manifest_dir}"
        for template_file in $(find "${harbor_manifest_dir}/${resource}" -type f); do
            vender_template_file "${template_file}"
        done

        scp::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
                     -s "${harbor_manifest_dir}/${resource}" \
                     -d "${harbor_config_dir}"

        # only the ${resource}/${resource}.yaml (e.g. ui/ui.yaml)
        # is the real kubernetes resource configurate file.
        kubectl create -f "${harbor_manifest_dir}/${resource}/${resource}.yaml"
    done

    LOG debug "Waiting at most 300s until harbor ui is ready ..."
    if ! wait::until -t 300 -i 10 -f ready::harbor_ui; then
        LOG error "Failed to wait for harbor ui to be ready!"
        return 1
    fi

    LOG debug "Waiting at most 300s until we can docker login to harbor ..."
    if ! wait::until -t 300 -i 10 -f ready::docker_login_harbor; then
        LOG error "Failed to wait until we can docker login to harbor!"
        return 2
    fi
}

################################################################################
################### deploy harbor containers and push images ###################
################################################################################

# if we can't login to harbor as admin, then create harbor resources.
if ! ssh::execute -h "${HARBOR_HOST}" -q -- "ready::docker_login_harbor"; then
    rm -rf ${harbor_manifest_dir} ${harbor_binary_dir}/*.sha256
    mkdir -p "${harbor_manifest_dir}"
    ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" -- "
        rm -rf ${harbor_config_dir}
        mkdir -p ${harbor_config_dir}
    "

    local::execute_parallel -h node -f upload_harbor_images -p 5
    create_harbor_resources

    ssh::execute_parallel -h "node" \
                          -s "${functions_file}" \
                          -- "config_harbor_cli"

    # the project 'library' is created by harbor automatically,
    # so we need to create a new one if it's NOT 'library'.
    if [[ "${KUBE_ADDON_IMAGES_PROJECT}" != "library" ]]; then
        ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
                     -s "${functions_file}" \
                     -- "create_addon_project"
    fi
fi

# kube-kit will treat all files with postfix '.tar.gz' in binaries/harbor/ as image file.
for compressed_image_file in $(ls -Sr ${harbor_binary_dir}/*.tar.gz 2>/dev/null); do
    # need to skip the compressed file of harbor images itself.
    [[ "${compressed_image_file##*/}" == "${harbor_images_filename}" ]] && continue

    compressed_image_file_checksum="${compressed_image_file}.sha256"
    if [[ -f "${compressed_image_file_checksum}" ]]; then
        sha256sum --check "${compressed_image_file_checksum}" --status && continue
    fi

    LOG info "Copying ${compressed_image_file} to ${HARBOR_HOST} ..."
    scp::execute -h "${HARBOR_HOST}" \
                 -s "${compressed_image_file}" \
                 -d "/tmp/"

    ssh::execute -h "${HARBOR_HOST}" \
                 -s "${functions_file}" \
                 -t "1800" \
                 -- "push_images" "${compressed_image_file##*/}"

    # record the sha256-checksum of current compressed image file.
    sha256sum "${compressed_image_file}" > "${compressed_image_file_checksum}"
done
