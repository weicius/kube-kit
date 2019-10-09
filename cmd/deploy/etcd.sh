#!/usr/bin/env bash
# vim: nu:noai:ts=4

functions_file="${__KUBE_KIT_DIR__}/src/deploy/etcd.sh"

for func_name in {install,config,start}_etcd; do
    ssh::execute_parallel -h "etcd" \
                          -s "${functions_file}" \
                          -- "${func_name}"
done
