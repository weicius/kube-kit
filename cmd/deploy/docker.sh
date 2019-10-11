#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/deploy/docker.sh"

for func_name in {install,config}_docker; do
    ssh::execute_parallel -h "all" \
                          -s "${functions_file}" \
                          -- "${func_name}"
done

function upload_preload_images {
    preloaded_images_num=$(ssh::execute -h "${HOST}" 'docker images 2>/dev/null' |\
          grep -cP '(pause|calico|coredns|heketi)' || true)

    # need to load the following 7 images firstly:
    # pause-amd64, coredns, heketi
    # calico-node, calico-cni, calico-kube-controllers, calico-pod2daemon-flexvol
    [[ "${preloaded_images_num}" -eq 7 ]] && return 0 || true

    LOG debug "Loading preloaded images on ${HOST} ..."
    scp::execute -h "${HOST}" \
                 -s "${__KUBE_KIT_DIR__}/binaries/harbor/preloaded-images.tar.gz" \
                 -d "/opt/preloaded-images.tar.gz"

    ssh::execute -h "${HOST}" \
                 -s "${functions_file}" \
                 -- "load_preload_images"
}

local::execute_parallel -h all -f upload_preload_images -p 5
