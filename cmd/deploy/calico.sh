#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207

calico_dir="${__KUBE_KIT_DIR__}/addon/calico"
calico_manifest_dir="${calico_dir}/manifest"

[[ -d "${calico_manifest_dir}" ]] || mkdir -p "${calico_manifest_dir}"
cp -f "${calico_dir}/calico.yaml" "${calico_manifest_dir}/calico.yaml"

ipip_mode="off"
[[ "${CALICO_MODE,,}" == "ipip" ]] && ipip_mode="always"

sed -i -r \
    -e "s|__CALICO_NODE_IMAGE__|${CALICO_NODE_IMAGE}|" \
    -e "s|__CALICO_CNI_IMAGE__|${CALICO_CNI_IMAGE}|" \
    -e "s|__CALICO_KUBE_CONTROLLERS_IMAGE__|${CALICO_KUBE_CONTROLLERS_IMAGE}|" \
    -e "s|__CALICO_POD2DAEMON_FLEXVOL_IMAGE__|${CALICO_POD2DAEMON_FLEXVOL_IMAGE}|" \
    -e "s|__CALICO_IPV4POOL_CIDR__|${KUBE_PODS_SUBNET}|" \
    -e "s|__CALICO_IPIP_MODE__|${ipip_mode}|" \
    -e "s|__CNI_BIN_DIR__|${CNI_BIN_DIR}|" \
    -e "s|__CNI_CONF_DIR__|${CNI_CONF_DIR}|" \
    -e "s|__DESTINATION__|${CALICO_NETWORK_GATEWAY:-${KUBE_KIT_GATEWAY}}|" \
    -e "s|__ETCD_SERVERS__|${ETCD_SERVERS}|" \
    "${calico_manifest_dir}/calico.yaml"

# generate base64 encoded strings of the entire contents of each file
etcd_ca_base64=$(base64 -w 0 "${KUBE_PKI_DIR}/ca.pem")
etcd_cert_base64=$(base64 -w 0 "${KUBE_PKI_DIR}/etcd.pem")
etcd_key_base64=$(base64 -w 0 "${KUBE_PKI_DIR}/etcd-key.pem")
sed -i -r \
    -e "s|^(  etcd-ca: ).*|\1\"${etcd_ca_base64}\"|" \
    -e "s|^(  etcd-cert: ).*|\1\"${etcd_cert_base64}\"|" \
    -e "s|^(  etcd-key: ).*|\1\"${etcd_key_base64}\"|" \
    "${calico_manifest_dir}/calico.yaml"

kubectl delete -f "${calico_manifest_dir}/calico.yaml" 2>/dev/null || true
wait::resource -t daemonset -n calico-node -s deleted
wait::resource -t deployment -n calico-kube-controllers -s deleted

kubectl create -f "${calico_manifest_dir}/calico.yaml"
wait::resource -t daemonset -n calico-node -s ready
wait::resource -t deployment -n calico-kube-controllers -s ready
