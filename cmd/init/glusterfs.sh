#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/init/glusterfs.sh"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "install_glusterfs"

ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "gluster_peer_probe"

ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "init_shared_volume"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "mount_shared_volume"
