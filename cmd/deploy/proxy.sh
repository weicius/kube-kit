#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/deploy/proxy.sh"

for func_name in {install,config}_nginx; do
    ssh::execute_parallel -h "master" \
                          -s "${functions_file}" \
                          -- "${func_name}"
done

scp::execute_parallel -h "master" \
                      -s "${__KUBE_KIT_DIR__}/util/check-nginx.sh" \
                      -d "/usr/local/bin"

for func_name in {install,config}_keepalived; do
    ssh::execute_parallel -h "master" \
                          -s "${functions_file}" \
                          -- "${func_name}"
done
