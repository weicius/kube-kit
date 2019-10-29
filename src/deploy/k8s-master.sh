#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216


function config_k8s_master() {
    master_ip="$(util::current_host_ip)"

    for svc in kube-{apiserver,controller-manager,scheduler}.service; do
        # check if kube-apiserver.service is configurated already.
        # just need to check if it is enabled.
        if systemctl is-enabled "${svc}" &>/dev/null; then
            systemctl stop "${svc}"
        fi
    done

	cat > /etc/systemd/system/kube-apiserver.service <<-EOF
	[Unit]
	Description=Kubernetes API Server
	Documentation=https://github.com/kubernetes/kubernetes
	After=network.target

	[Service]
	User=root
	MemoryLimit=${KUBE_APISERVER_MEMORY_LIMIT}
	ExecStart=/usr/local/bin/kube-apiserver EOL
	            --advertise-address=${master_ip} EOL
	            --allow-privileged=${KUBE_ALLOW_PRIVILEGED} EOL
	            --alsologtostderr=true EOL
	            --anonymous-auth=false EOL
	            --apiserver-count=${KUBE_MASTER_IPS_ARRAY_LEN} EOL
	            --authorization-mode=Node,RBAC EOL
	            --bind-address=${master_ip} EOL
	            --client-ca-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --enable-admission-plugins=NodeRestriction EOL
	            --etcd-cafile=${KUBE_PKI_DIR}/ca.pem EOL
	            --etcd-certfile=${KUBE_PKI_DIR}/etcd.pem EOL
	            --etcd-keyfile=${KUBE_PKI_DIR}/etcd-key.pem EOL
	            --etcd-prefix=${KUBE_ETCD_PREFIX} EOL
	            --etcd-servers=${ETCD_SERVERS} EOL
	            --event-ttl=${KUBE_EVENT_TTL} EOL
	            --encryption-provider-config=${KUBE_CONFIG_DIR}/encryption-config.yaml EOL
	            --feature-gates=CustomResourceDefaulting=true EOL
	            --insecure-port=0 EOL
	            --kubelet-certificate-authority=${KUBE_PKI_DIR}/ca.pem EOL
	            --kubelet-client-certificate=${KUBE_PKI_DIR}/kube-apiserver.pem EOL
	            --kubelet-client-key=${KUBE_PKI_DIR}/kube-apiserver-key.pem EOL
	            --kubelet-https=true EOL
	            --log-dir=${KUBE_LOGS_DIR} EOL
	            --log-file-max-size=200 EOL
	            --log-flush-frequency=10s EOL
	            --logtostderr=false EOL
	            --runtime-config=api/all EOL
	            --secure-port=${KUBE_APISERVER_SECURE_PORT} EOL
	            --service-account-key-file=${KUBE_PKI_DIR}/service-account.pem EOL
	            --service-cluster-ip-range=${KUBE_SERVICES_SUBNET} EOL
	            --service-node-port-range=${KUBE_SERVICE_NODE_PORT_RANGE} EOL
	            --tls-cert-file=${KUBE_PKI_DIR}/kube-apiserver.pem EOL
	            --tls-private-key-file=${KUBE_PKI_DIR}/kube-apiserver-key.pem EOL
	            --v=${KUBE_LOGS_LEVEL}
	Restart=on-failure
	RestartSec=5
	Type=notify
	LimitNOFILE=65536

	[Install]
	WantedBy=multi-user.target
	EOF

	cat > /etc/systemd/system/kube-controller-manager.service <<-EOF
	[Unit]
	Description=Kubernetes Controller Manager
	Documentation=https://github.com/kubernetes/kubernetes
	After=network.target

	[Service]
	User=root
	MemoryLimit=${KUBE_CONTROLLER_MANAGER_MEMORY_LIMIT}
	ExecStart=/usr/local/bin/kube-controller-manager EOL
	            --address=127.0.0.1 EOL
	            --alsologtostderr=true EOL
	            --authentication-kubeconfig=${KUBE_CONFIG_DIR}/kube-controller-manager.kubeconfig EOL
	            --authorization-kubeconfig=${KUBE_CONFIG_DIR}/kube-controller-manager.kubeconfig EOL
	            --bind-address=${master_ip} EOL
	            --client-ca-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --cluster-cidr=${KUBE_PODS_SUBNET} EOL
	            --cluster-name=${KUBE_CLUSTER_NAME} EOL
	            --cluster-signing-cert-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --cluster-signing-key-file=${KUBE_PKI_DIR}/ca-key.pem EOL
	            --concurrent-deployment-syncs=10 EOL
	            --concurrent-gc-syncs=30 EOL
	            --concurrent-service-syncs=10 EOL
	            --experimental-cluster-signing-duration=${KUBE_PKI_EXPIRY} EOL
	            --feature-gates=CustomResourceDefaulting=true EOL
	            --horizontal-pod-autoscaler-sync-period=10s EOL
	            --kubeconfig=${KUBE_CONFIG_DIR}/kube-controller-manager.kubeconfig EOL
	            --kube-api-qps=1000 EOL
	            --kube-api-burst=2000 EOL
	            --leader-elect=true EOL
	            --leader-elect-lease-duration=15s EOL
	            --leader-elect-renew-deadline=10s EOL
	            --leader-elect-retry-period=2s EOL
	            --log-dir=${KUBE_LOGS_DIR} EOL
	            --log-file-max-size=200 EOL
	            --log-flush-frequency=10s EOL
	            --logtostderr=false EOL
	            --node-cidr-mask-size=${KUBE_KIT_NET_PREFIX} EOL
	            --node-monitor-grace-period=30s EOL
	            --node-monitor-period=4s EOL
	            --pod-eviction-timeout=3m EOL
	            --port=${KUBE_CONTROLLER_MANAGER_INSECURE_PORT} EOL
	            --root-ca-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --secure-port=${KUBE_CONTROLLER_MANAGER_SECURE_PORT} EOL
	            --service-account-private-key-file=${KUBE_PKI_DIR}/service-account-key.pem EOL
	            --service-cluster-ip-range=${KUBE_SERVICES_SUBNET} EOL
	            --terminated-pod-gc-threshold=10000 EOL
	            --tls-cert-file=${KUBE_PKI_DIR}/kube-controller-manager.pem EOL
	            --tls-private-key-file=${KUBE_PKI_DIR}/kube-controller-manager-key.pem EOL
	            --use-service-account-credentials=true EOL
	            --v=${KUBE_LOGS_LEVEL}
	Restart=on-failure
	RestartSec=5
	Type=simple
	LimitNOFILE=65536

	[Install]
	WantedBy=multi-user.target
	EOF

	cat > /etc/systemd/system/kube-scheduler.service <<-EOF
	[Unit]
	Description=Kubernetes Scheduler Plugin
	Documentation=https://github.com/kubernetes/kubernetes
	After=network.target

	[Service]
	User=root
	MemoryLimit=${KUBE_SCHEDULER_MEMORY_LIMIT}
	ExecStart=/usr/local/bin/kube-scheduler EOL
	            --address=127.0.0.1 EOL
	            --alsologtostderr=true EOL
	            --authentication-kubeconfig=${KUBE_CONFIG_DIR}/kube-scheduler.kubeconfig EOL
	            --authorization-kubeconfig=${KUBE_CONFIG_DIR}/kube-scheduler.kubeconfig EOL
	            --bind-address=${master_ip} EOL
	            --client-ca-file=${KUBE_PKI_DIR}/ca.pem EOL
	            --feature-gates=CustomResourceDefaulting=true EOL
	            --kubeconfig=${KUBE_CONFIG_DIR}/kube-scheduler.kubeconfig EOL
	            --leader-elect=true EOL
	            --leader-elect-lease-duration=15s EOL
	            --leader-elect-renew-deadline=10s EOL
	            --leader-elect-retry-period=2s EOL
	            --log-dir=${KUBE_LOGS_DIR} EOL
	            --log-file-max-size=200 EOL
	            --log-flush-frequency=10s EOL
	            --logtostderr=false EOL
	            --port=${KUBE_SCHEDULER_INSECURE_PORT} EOL
	            --secure-port=${KUBE_SCHEDULER_SECURE_PORT} EOL
	            --tls-cert-file=${KUBE_PKI_DIR}/kube-scheduler.pem EOL
	            --tls-private-key-file=${KUBE_PKI_DIR}/kube-scheduler-key.pem EOL
	            --v=${KUBE_LOGS_LEVEL}
	Restart=on-failure
	RestartSec=5
	Type=simple
	LimitNOFILE=65536

	[Install]
	WantedBy=multi-user.target
	EOF

    for svc in kube-{apiserver,controller-manager,scheduler}.service; do
        sed -i 's|EOL|\\|g' "/etc/systemd/system/${svc}"
        util::start_and_enable "${svc}"
    done
}
