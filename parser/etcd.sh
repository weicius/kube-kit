#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# ***************** validate and generate etcd configurations ******************
################################################################################

declare -a ETCD_NODE_IPS_ARRAY
ETCD_NODE_IPS_ARRAY=(${KUBE_MASTER_IPS_ARRAY[@]})
ETCD_NODE_IPS_ARRAY_LEN="${#ETCD_NODE_IPS_ARRAY[@]}"
ETCD_INITIAL_CLUSTER=""
ETCD_SERVERS=""

for etcd_idx in "${!ETCD_NODE_IPS_ARRAY[@]}"; do
    etcd_node_ip=${ETCD_NODE_IPS_ARRAY[${etcd_idx}]}
    ETCD_INITIAL_CLUSTER+="${ETCD_CLUSTER_MEMBER_PREFIX}${etcd_idx}=${ETCD_PROTOCOL}://${etcd_node_ip}:2380,"
    ETCD_SERVERS+="${ETCD_PROTOCOL}://${etcd_node_ip}:2379,"
done

# remove the tailing comma ','
ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER%?}"
ETCD_SERVERS="${ETCD_SERVERS%?}"
ETCDCTL="etcdctl --endpoints=${ETCD_SERVERS}"

if [[ "${ETCD_PROTOCOL,,}" == "https" ]]; then
    ETCDCTL=$(cat <<-EOF | sed -r 's/\s+/ /g'
		etcdctl --endpoints=${ETCD_SERVERS} \
		        --ca-file=${ETCD_PKI_DIR}/ca.pem \
		        --cert-file=${ETCD_PKI_DIR}/etcd.pem \
		        --key-file=${ETCD_PKI_DIR}/etcd-key.pem
		EOF
    )
fi
