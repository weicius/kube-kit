#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function install_docker() {
    local docker_pkg="docker-ce-${DOCKER_VERSION}"
    current_ip="$(util::current_host_ip)"

    rpm -qa | grep -q "${docker_pkg}" && return 0
    # remove the docker-ce of other versions.
    if rpm -qa | grep -q docker-ce; then
        yum remove docker-ce -y &>/dev/null
    fi

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
        cat > /etc/yum.repos.d/docker-ce.repo <<-EOF
		[docker-ce-stable]
		name=Docker CE Stable Mirror Repository
		baseurl=${DOCKER_REPO_MIRROR}/docker-ce/linux/centos/7/x86_64/stable
		enabled=1
		gpgcheck=1
		gpgkey=${DOCKER_REPO_MIRROR}/docker-ce/linux/centos/gpg
		EOF
    fi

    LOG info "Installing ${docker_pkg} on ${current_ip} ..."
    yum install -y "${docker_pkg}" &>/dev/null
}


function config_docker() {
    current_ip="$(util::current_host_ip)"
    docker_service="/usr/lib/systemd/system/docker.service"

	cat > "${docker_service}" <<-EOF
	[Unit]
	Description=Docker Application Container Engine
	Documentation=https://docs.docker.com
	BindsTo=containerd.service
	After=network-online.target containerd.service
	Wants=network-online.target
	Requires=docker.socket

	[Service]
	Type=notify
	# the default is not to use systemd for cgroups because the delegate issues still
	# exists and systemd currently does not support the cgroup feature set required
	# for containers run by docker
	MemoryLimit=${DOCKERD_MEMORY_LIMIT}
	ExecStart=/usr/bin/dockerd \\
	            --containerd=/run/containerd/containerd.sock \\
	            --data-root=${DOCKER_WORKDIR} \\
	            --debug=false \\
	            --host=tcp://${current_ip}:${DOCKER_DAEMON_PORT} \\
	            --host=unix:///var/run/docker.sock \\
	            --insecure-registry=${HARBOR_REGISTRY} \\
	            --insecure-registry=k8s.gcr.io \\
	            --insecure-registry=quay.io \\
	            --ip-forward=true \\
	            --live-restore=true \\
	            --log-driver=json-file \\
	            --log-level=warn \\
	            --max-concurrent-downloads=10 \\
	            --max-concurrent-uploads=10 \\
	            --registry-mirror=${DOCKER_HUB_MIRROR} \\
	            --selinux-enabled=false \\
	            --shutdown-timeout=30 \\
	            --storage-driver=${DOCKER_STORAGE_DRIVER} \\
	            --tlscacert=${KUBE_PKI_DIR}/ca.pem \\
	            --tlscert=${KUBE_PKI_DIR}/docker.pem \\
	            --tlskey=${KUBE_PKI_DIR}/docker-key.pem \\
	            --tlsverify=true

	# need to reset the rule of iptables FORWARD chain to ACCEPT, because
	# docker 1.13 changed the default iptables forwarding policy to DROP.
	# https://github.com/moby/moby/pull/28257/files
	# https://github.com/kubernetes/kubernetes/issues/40182
	ExecStartPost=/usr/sbin/iptables -P FORWARD ACCEPT
	ExecReload=/bin/kill -s HUP \$MAINPID

	TimeoutSec=0
	RestartSec=2
	Restart=always

	# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
	# Both the old, and new location are accepted by systemd 229 and up, so using the old location
	# to make them work for either version of systemd.
	StartLimitBurst=3

	# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
	# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
	# this option work for either version of systemd.
	StartLimitInterval=60s

	# Having non-zero Limit*s causes performance problems due to accounting overhead
	# in the kernel. We recommend using cgroups to do container-local accounting.
	LimitNOFILE=infinity
	LimitNPROC=infinity
	LimitCORE=infinity

	# Comment TasksMax if your systemd version does not support it.
	# Only systemd 226 and above support this option.
	TasksMax=infinity

	# set delegate yes so that systemd does not reset the cgroups of docker containers
	Delegate=yes

	# kill only the docker process, not all processes in the cgroup
	KillMode=process

	[Install]
	WantedBy=multi-user.target
	EOF

    if [[ "${ENABLE_CNI_PLUGIN,,}" != "true" ]]; then
        sed -i -r \
            -e "/ExecStart/iEnvironmentFile=-/run/flannel/docker" \
            -e "/--data-root/i\            \\\$DOCKER_NETWORK_OPTIONS EOL" \
            "${docker_service}"
    fi

    case "${DOCKER_STORAGE_DRIVER}" in
        overlay|overlay2)
            sed -i -r \
                -e "/ExecStart/iExecStartPre=/usr/sbin/modprobe overlay" \
                "${docker_service}"
            echo "overlay" >/etc/modules-load.d/overlay.conf
            ;;
        devicemapper)
            config_devicemapper
            ;;
    esac

    sed -i -r 's|EOL|\\|g' "${docker_service}"

    # install nvidia-container-runtime only if current host has GPUs.
    if ls /dev/nvidia* &>/dev/null; then
        install_nvidia_container_runtime
    fi

    util::start_and_enable docker.service
}


# ref: https://github.com/NVIDIA/nvidia-docker#centos-7-docker-ce-rhel-7475-docker-ce-amazon-linux-12
function install_nvidia_container_runtime() {
    current_ip="$(util::current_host_ip)"

    # NOTE: nvidia-container-runtime requires these three packages:
    # nvidia-container-toolkit libnvidia-container-tools libnvidia-container1
    rpm -qa | grep -q nvidia-container-runtime && return 0

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
        curl -s -L https://nvidia.github.io/nvidia-docker/centos7/nvidia-docker.repo \
             -o /etc/yum.repos.d/nvidia-docker.repo
        # in case this error: signature could not be verified for libnvidia-container
        sed -i -r \
            -e "s/^(repo_gpgcheck|gpgcheck|sslverify).*/\1=0/" \
            /etc/yum.repos.d/nvidia-docker.repo
    fi

    LOG debug "Installing nvidia-container-runtime on ${current_ip} ..."
    yum install -y -q nvidia-container-runtime

    # ref: https://github.com/NVIDIA/k8s-device-plugin
	cat > /etc/docker/daemon.json <<-EOF
	{
	    "default-runtime": "nvidia",
	    "runtimes": {
	        "nvidia": {
	            "path": "/usr/bin/nvidia-container-runtime",
	            "runtimeArgs": []
	        }
	    }
	}
	EOF
}


function config_devicemapper() {
    local vg_name="${KUBE_MASTER_STANDALONE_VG}"
    local lv_name="${KUBE_MASTER_DOCKER_LV}"
    local lv_ratio="${KUBE_MASTER_DOCKER_LV_RATIO}"

    if util::element_in_array "${current_ip}" "${KUBE_NODE_IPS_ARRAY[@]}"; then
        vg_name="${KUBE_NODE_STANDALONE_VG}"
        lv_name="${KUBE_NODE_DOCKER_LV}"
        lv_ratio="${KUBE_NODE_DOCKER_LV_RATIO}"
    fi

    current_ip="$(util::current_host_ip)"
    device="${KUBE_DISKS_ARRAY[${current_ip}]}"

    # calculate the total size of disk.
    device_size_in_gb=$(($(lsblk -bdn -o SIZE "${device}") / 1024 ** 3))
    # init the basesize(must be an integer) as a half of the total size of thinpool lv for docker.
    basesize_in_gb=$(python <<< "print(int(${device_size_in_gb} * ${lv_ratio} * 0.5))")

    # we need the thinpool name of docker lv '${lv_name}_thinpool'.
    mapper_file=$(util::get_mapper_file "${vg_name}" "${lv_name}_thinpool")

    # add the configurations for devicemapper only.
    sed -i -r \
        -e "/storage-driver/a\            --storage-opt=dm.basesize=${basesize_in_gb}G EOL" \
        -e "/storage-driver/a\            --storage-opt=dm.fs=xfs EOL" \
        -e "/storage-driver/a\            --storage-opt=dm.thinpooldev=${mapper_file} EOL" \
        -e "/storage-driver/a\            --storage-opt=dm.use_deferred_deletion=true EOL" \
        -e "/storage-driver/a\            --storage-opt=dm.use_deferred_removal=true EOL" \
        "${docker_service}"
}


function load_preload_images() {
    rm -rf /opt/preloaded-images
    tar -zxf /opt/preloaded-images.tar.gz -C /opt

    # sort the files by size in reverse order, i.e. smallest first
    for image_tar_file in $(ls -Sr /opt/preloaded-images/*.tar 2>/dev/null); do
        image_tar_filename="${image_tar_file##*/}"
        image_name="${image_tar_filename/.tar/}"
        new_image_name="${KUBE_ADDON_IMAGES_REPO}/${image_name}"

        docker load -i "${image_tar_file}" >/dev/null
        docker tag "${image_name}" "${new_image_name}" >/dev/null
        docker rmi "${image_name}" >/dev/null
    done

    rm -rf /opt/preloaded-images{,.tar.gz}
}
