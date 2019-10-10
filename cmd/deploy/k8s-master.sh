#!/usr/bin/env bash
# vim: nu:noai:ts=4

functions_file="${__KUBE_KIT_DIR__}/src/deploy/k8s-master.sh"

ssh::execute_parallel -h "master" \
                      -s "${functions_file}" \
                      -- "config_k8s_master"
