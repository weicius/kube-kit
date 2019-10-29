#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216


function get_system_reserved_memory() {
    node_ip="$(util::current_host_ip)"
    local system_reserved_memory_array=(
        "${DOCKERD_MEMORY_LIMIT}"
        "${KUBELET_MEMORY_LIMIT}"
        "${KUBE_PROXY_MEMORY_LIMIT}"
    )

    if util::element_in_array "${node_ip}" "${KUBE_MASTER_IPS_ARRAY[@]}"; then
        system_reserved_memory_array+=(
            "${KUBE_APISERVER_MEMORY_LIMIT}"
            "${KUBE_SCHEDULER_MEMORY_LIMIT}"
            "${KUBE_CONTROLLER_MANAGER_MEMORY_LIMIT}"
            "${ETCD_MEMORY_LIMIT}"
        )
    fi

    if [[ "${ENABLE_CNI_PLUGIN,,}" != "true" ]]; then
        system_reserved_memory_array+=("${FLANNELD_MEMORY_LIMIT}")
    fi

    local system_reserved_memory_in_mb=0
    for reserved_memory in "${system_reserved_memory_array[@]}"; do
        if [[ "${reserved_memory^^}" =~ ^([0-9]+)G$ ]]; then
            local memory_in_gb="${BASH_REMATCH[1]}"
            ((system_reserved_memory_in_mb += memory_in_gb * 1024))
        elif [[ "${reserved_memory^^}" =~ ^([0-9]+)M$ ]]; then
            local memory_in_mb="${BASH_REMATCH[1]}"
            ((system_reserved_memory_in_mb += memory_in_mb))
        fi
    done

    echo "${system_reserved_memory_in_mb}Mi"
}


function config_k8s_node() {
    node_ip="$(util::current_host_ip)"
    system_reserved_memory="$(get_system_reserved_memory)"

    for svc in {kubelet,kube-proxy}.service; do
        # check if kubelet.service is configurated already
        # just need to check if it is enabled.
        if systemctl is-enabled "${svc}" &>/dev/null; then
            systemctl stop "${svc}"
        fi
    done

	cat > /etc/systemd/system/kubelet.service <<-EOF
	[Unit]
	Description=Kubernetes Kubelet Server
	Documentation=https://github.com/kubernetes/kubernetes
	After=docker.service
	Requires=docker.service

	[Service]
	User=root
	WorkingDirectory=${KUBELET_WORKDIR}
	MemoryLimit=${KUBELET_MEMORY_LIMIT}
	ExecStart=/usr/local/bin/kubelet EOL
	            --address=${node_ip} EOL
	            --alsologtostderr=true EOL
	            --client-ca-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --cluster-dns=${KUBE_DNS_SVC_IP} EOL
	            --cluster-domain=${KUBE_DNS_DOMAIN} EOL
	            --docker-tls EOL
	            --docker-tls-ca=${KUBE_PKI_DIR}/ca.pem EOL
	            --docker-tls-cert=${KUBE_PKI_DIR}/docker.pem EOL
	            --docker-tls-key=${KUBE_PKI_DIR}/docker-key.pem EOL
	            --fail-swap-on=true EOL
	            --feature-gates=CustomResourceDefaulting=true EOL
	            --healthz-port=${KUBELET_HEALTHZ_PORT} EOL
	            --hostname-override= EOL
	            --image-pull-progress-deadline=30m EOL
	            --kubeconfig=${KUBE_CONFIG_DIR}/kubelet-$(hostname).kubeconfig EOL
	            --log-dir=${KUBE_LOGS_DIR} EOL
	            --log-file-max-size=200 EOL
	            --log-flush-frequency=10s EOL
	            --logtostderr=false EOL
	            --pod-infra-container-image=${KUBE_POD_INFRA_IMAGE} EOL
	            --port=${KUBELET_PORT} EOL
	            --read-only-port=${KUBELET_READONLY_PORT} EOL
	            --register-node=true EOL
	            --root-dir=${KUBELET_WORKDIR} EOL
	            --runtime-request-timeout=10m EOL
	            --serialize-image-pulls=false EOL
	            --system-reserved=memory=${system_reserved_memory} EOL
	            --tls-cert-file=${KUBE_PKI_DIR}/kubelet-$(hostname).pem EOL
	            --tls-private-key-file=${KUBE_PKI_DIR}/kubelet-$(hostname)-key.pem EOL
	            --v=${KUBE_LOGS_LEVEL}
	Restart=on-failure
	RestartSec=5
	Type=simple
	LimitNOFILE=65536

	[Install]
	WantedBy=multi-user.target
	EOF

    # configurate cni networking plugins.
    if [[ "${ENABLE_CNI_PLUGIN,,}" == "true" ]]; then
        sed -i -r \
            -e "/--cluster-domain/a\            --cni-conf-dir=${CNI_CONF_DIR} EOL" \
            -e "/--cluster-domain/a\            --cni-bin-dir=${CNI_BIN_DIR} EOL" \
            -e "/--logtostderr/a\            --network-plugin=cni EOL" \
            /etc/systemd/system/kubelet.service
    fi

	cat > /etc/systemd/system/kube-proxy.service <<-EOF
	[Unit]
	Description=Kubernetes Kube-Proxy Server
	Documentation=https://github.com/kubernetes/kubernetes
	After=network.target

	[Service]
	User=root
	MemoryLimit=${KUBE_PROXY_MEMORY_LIMIT}
	ExecStart=/usr/local/bin/kube-proxy EOL
	            --alsologtostderr=true EOL
	            --bind-address=${node_ip} EOL
	            --cluster-cidr=${KUBE_PODS_SUBNET} EOL
	            --feature-gates=CustomResourceDefaulting=true EOL
	            --hostname-override= EOL
	            --kubeconfig=${KUBE_CONFIG_DIR}/kube-proxy.kubeconfig EOL
	            --log-dir=${KUBE_LOGS_DIR} EOL
	            --log-file-max-size=200 EOL
	            --log-flush-frequency=10s EOL
	            --logtostderr=false EOL
	            --proxy-mode=${KUBE_PROXY_MODE} EOL
	            --v=${KUBE_LOGS_LEVEL}
	Restart=on-failure
	RestartSec=5
	Type=simple
	LimitNOFILE=65536

	[Install]
	WantedBy=multi-user.target
	EOF

    if [[ "${KUBE_PROXY_MODE}" == "ipvs" ]]; then
        sed -i -r \
            -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe ip_vs" \
            -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe ip_vs_rr" \
            -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe ip_vs_sh" \
            -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe ip_vs_wrr" \
            -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe nf_conntrack_ipv4" \
            /etc/systemd/system/kube-proxy.service
    fi

    for svc in {kubelet,kube-proxy}.service; do
        sed -i 's|EOL|\\|g' "/etc/systemd/system/${svc}"
        util::start_and_enable "${svc}"
    done
}


function label_master_role() {
    kubectl label node "$(hostname)" \
            node-role.kubernetes.io/master="$(hostname)" --overwrite
}


function label_node_role() {
    kubectl label node "$(hostname)" \
            node-role.kubernetes.io/node="$(hostname)" --overwrite
}


function label_cputype_gputype() {
    kubectl label node "$(hostname)" \
            cputype="$(util::get_cpu_type)" \
            gputype="$(util::get_gpu_type)" \
            --overwrite
}
