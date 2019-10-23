#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

coredns_dir="${__KUBE_KIT_DIR__}/addon/coredns"
coredns_manifest_dir="${coredns_dir}/manifest"

[[ -d "${coredns_manifest_dir}" ]] || mkdir -p "${coredns_manifest_dir}"
cp -f "${coredns_dir}/coredns.yaml" "${coredns_manifest_dir}/coredns.yaml"

sed -i -r \
    -e "s|__KUBE_DNS_DOMAIN__|${KUBE_DNS_DOMAIN}|" \
    -e "s|__KUBE_DNS_SVC_IP__|${KUBE_DNS_SVC_IP}|" \
    -e "s|__COREDNS_IMAGE__|${COREDNS_IMAGE}|" \
    "${coredns_manifest_dir}/coredns.yaml"

kubectl delete -f "${coredns_manifest_dir}/coredns.yaml" 2>/dev/null || true
wait::resource -t deployment -n coredns -s deleted

kubectl create -f "${coredns_manifest_dir}/coredns.yaml"
wait::resource -t deployment -n coredns -s ready
