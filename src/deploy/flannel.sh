#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207


function get_flanneld_iface() {
    local iface=""

    for netdev in /sys/class/net/*; do
        # skip all the virtual network devices.
        [[ $(readlink "${netdev}") =~ virtual ]] && continue
        phynic=$(basename "${netdev}")
        if [[ -n "${FLANNEL_NETWORK_GATEWAY}" ]]; then
            if ping -I "${phynic}" -c 4 -W 1 -i 0.05 "${FLANNEL_NETWORK_GATEWAY}" &>/dev/null; then
                iface="${phynic}"
                break
            fi
        elif ip addr show "${phynic}" | grep -q "$(util::current_host_ip)}"; then
            iface="${phynic}"
            break
        fi
    done

    echo -n "${iface}"
}


# NOTE: this function just need to be executed only once.
function config_etcd() {
    flannel_config=$(cat <<-EOF | python
		import json
		conf = dict()
		conf['Network'] = '${KUBE_PODS_SUBNET}'
		conf['SubnetLen'] = 24
		conf['Backend'] = {'Type': '${FLANNEL_TYPE}'}
		print(json.dumps(conf))
		EOF
    )

    ${ETCDCTL} ls "${FLANNEL_ETCD_PREFIX}" &>/dev/null && return 0
    ${ETCDCTL} set "${FLANNEL_ETCD_PREFIX}/config" "${flannel_config}"
}


function config_flanneld() {
    local flanneld_service="/etc/systemd/system/flanneld.service"
    current_ip="$(util::current_host_ip)"
    iface="$(get_flanneld_iface)"

    if [[ -z "${iface}" ]]; then
        LOG error "Failed to get the iface to serve flanneld!"
        return 1
    fi

    LOG debug "Config and start flanneld.service on ${current_ip} ..."
	cat > "${flanneld_service}" <<-EOF
	[Unit]
	Description=Flanneld overlay address etcd agent
	After=network.target
	After=network-online.target
	Wants=network-online.target
	Before=docker.service

	[Service]
	Type=notify
	ExecStart=/usr/local/bin/flanneld \\
	            -etcd-cafile=${KUBE_PKI_DIR}/ca.pem \\
	            -etcd-certfile=${KUBE_PKI_DIR}/etcd.pem \\
	            -etcd-endpoints=${ETCD_SERVERS} \\
	            -etcd-keyfile=${KUBE_PKI_DIR}/etcd-key.pem \\
	            -etcd-prefix=${FLANNEL_ETCD_PREFIX} \\
	            -iface=${iface} \\
	            -ip-masq
	ExecStartPost=/usr/local/bin/mk-docker-opts.sh \\
	            -k DOCKER_NETWORK_OPTIONS \\
	            -d /run/flannel/docker \\
	            -f /run/flannel/subnet.env
	Restart=on-failure

	[Install]
	WantedBy=multi-user.target
	WantedBy=docker.service
	EOF

    util::start_and_enable flanneld.service
}


function stop_flanneld() {
    systemctl is-active flanneld -q && systemctl stop flanneld
}
