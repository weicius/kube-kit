#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207


function install_etcd() {
    local etcd_pkg="etcd-${ETCD_VERSION}"
    rpm -qa | grep -qE "^${etcd_pkg}" && return 0
    LOG info "Installing ${etcd_pkg} on $(util::current_host_ip) ..."
    yum install -q -y "${etcd_pkg}"
}


function config_etcd() {
    local etcd_node_ip
    local etcd_node_name
    etcd_node_ip="$(util::current_host_ip)"

    for idx in "${!ETCD_NODE_IPS_ARRAY[@]}"; do
        if [[ "${etcd_node_ip}" == "${ETCD_NODE_IPS_ARRAY[${idx}]}" ]]; then
            etcd_node_name="${ETCD_CLUSTER_MEMBER_PREFIX}${idx}"
            break
        fi
    done

    sed -i -r \
        -e "s|.*(ETCD_NAME=).*|\1\"${etcd_node_name}\"|" \
        -e "s|.*(ETCD_DATA_DIR=).*|\1\"${ETCD_WORKDIR}/${etcd_node_name}\"|" \
        -e "s|.*(ETCD_LISTEN_PEER_URLS=).*|\1\"https://${etcd_node_ip}:2380\"|" \
        -e "s|.*(ETCD_LISTEN_CLIENT_URLS=).*|\1\"https://${etcd_node_ip}:2379,https://127.0.0.1:2379\"|" \
        -e "s|.*(ETCD_INITIAL_ADVERTISE_PEER_URLS=).*|\1\"https://${etcd_node_ip}:2380\"|" \
        -e "s|.*(ETCD_INITIAL_CLUSTER=).*|\1\"${ETCD_INITIAL_CLUSTER}\"|" \
        -e "s|.*(ETCD_INITIAL_CLUSTER_STATE=).*|\1\"new\"|" \
        -e "s|.*(ETCD_INITIAL_CLUSTER_TOKEN=).*|\1\"${ETCD_CLUSTER_NAME}\"|" \
        -e "s|.*(ETCD_ADVERTISE_CLIENT_URLS=).*|\1\"https://${etcd_node_ip}:2379\"|" \
        -e "s|.*(ETCD_AUTO_COMPACTION_RETENTION=).*|\1\"1\"|" \
        -e "s|.*(ETCD_DEBUG=).*|\1\"true\"|" \
        -e "s|.*(ETCD_LOG_PACKAGE_LEVELS=).*|\1\"DEBUG\"|" \
        -e "s|.*(ETCD_CLIENT_CERT_AUTH=).*|\1\"true\"|" \
        -e "s|.*(ETCD_CERT_FILE=).*|\1\"${ETCD_PKI_DIR}/etcd.pem\"|" \
        -e "s|.*(ETCD_KEY_FILE=).*|\1\"${ETCD_PKI_DIR}/etcd-key.pem\"|" \
        -e "s|.*(ETCD_TRUSTED_CA_FILE=).*|\1\"${ETCD_PKI_DIR}/ca.pem\"|" \
        -e "s|.*(ETCD_PEER_CLIENT_CERT_AUTH=).*|\1\"true\"|" \
        -e "s|.*(ETCD_PEER_CERT_FILE=).*|\1\"${ETCD_PKI_DIR}/etcd.pem\"|" \
        -e "s|.*(ETCD_PEER_KEY_FILE=).*|\1\"${ETCD_PKI_DIR}/etcd-key.pem\"|" \
        -e "s|.*(ETCD_PEER_TRUSTED_CA_FILE=).*|\1\"${ETCD_PKI_DIR}/ca.pem\"|" \
        /etc/etcd/etcd.conf

    rm -rf "${ETCD_PKI_DIR}"
    mkdir -p "${ETCD_PKI_DIR}"

    # need to copy the latest credentials files from /etc/kubernetes/pki
    cp -f "${KUBE_PKI_DIR}"/{ca,etcd{,-key}}.pem "${ETCD_PKI_DIR}"

    # remove the existed alias of etcdctl if necessary.
    sed -i -r '/^alias etcdctl/d' /root/.bashrc

	cat >> /root/.bashrc <<-EOF
	alias etcdctlv2='ETCDCTL_API=2 etcdctl \
	                               --endpoints=${ETCD_SERVERS} \
	                               --ca-file=${ETCD_PKI_DIR}/ca.pem \
	                               --cert-file=${ETCD_PKI_DIR}/etcd.pem \
	                               --key-file=${ETCD_PKI_DIR}/etcd-key.pem'
	alias etcdctlv3='ETCDCTL_API=3 etcdctl \
	                               --endpoints=${ETCD_SERVERS} \
	                               --cacert=${ETCD_PKI_DIR}/ca.pem \
	                               --cert=${ETCD_PKI_DIR}/etcd.pem \
	                               --key=${ETCD_PKI_DIR}/etcd-key.pem'
	EOF

    sed -i -r '/^alias etcdctl/s/\s+/ /g' /root/.bashrc
}


function start_etcd() {
    sed -i -r "/MemoryLimit/d" \
        /usr/lib/systemd/system/etcd.service
    sed -i -r "/ExecStart/iMemoryLimit=${ETCD_MEMORY_LIMIT}" \
        /usr/lib/systemd/system/etcd.service

    chown -R etcd:etcd "${ETCD_CONFIG_DIR}" "${ETCD_WORKDIR}"
    LOG debug "Starting etcd.service on $(util::current_host_ip) ..."
    systemctl stop etcd.service &>/dev/null || true
    util::start_and_enable etcd.service
}
