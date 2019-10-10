#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function install_docker() {
    local docker_pkg="docker-ce-${DOCKER_VERSION}"
    current_ip="$(util::current_host_ip)"

    if [[ -f /usr/bin/docker ]]; then
        current_docker_version=$(docker --version | grep -oP '[0-9.]+(-ce)?(?=,)')
        if [[ "${current_docker_version}" != "${DOCKER_VERSION}" ]]; then
            systemctl stop docker.service
            yum remove docker-ce -y &>/dev/null
        elif ! systemctl is-active docker.service --quiet; then
            yum remove docker-ce -y &>/dev/null
        else
            LOG warn "${docker_pkg} on ${current_ip} is active now! Just restarting docker ..."
        fi
    fi

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
        if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
			cat > /etc/yum.repos.d/docker-ce.repo <<-EOF
			[docker-ce-stable]
			name=Docker CE Stable Mirror Repository
			baseurl=${DOCKER_REPO_MIRROR}/docker-ce/linux/centos/7/x86_64/stable
			enabled=1
			gpgcheck=1
			gpgkey=${DOCKER_REPO_MIRROR}/docker-ce/linux/centos/gpg
			EOF
        fi
    fi

    LOG info "Trying to install ${docker_pkg} on ${current_ip} ..."
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
	            --debug=true \\
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

    # install nvidia-docker on current host only if it has GPUs.
    if ! ls /dev/nvidia* &>/dev/null; then
        LOG debug "There is NO nvidia GPUs on ${current_ip}! skipping ..."
        util::start_and_enable docker.service
        return 0
    fi

    # NOTE: take care of the order of `util::start_and_enable docker` and
    # `install_nvidia_docker` for nvidia-docker-v1 and nvidia-docker-v2
    if [[ "${DOCKER_NVIDIA_VERSION}" == "v1" ]]; then
        util::start_and_enable docker.service
        install_nvidia_docker
    else
        install_nvidia_docker2
        util::start_and_enable docker.service
    fi
}


function install_nvidia_docker() {
    current_ip="$(util::current_host_ip)"

    if ! rpm -qa | grep -q nvidia-docker; then
        LOG debug "Installing nvidia-docker on ${current_ip} ..."
        if [[ "${ENABLE_LOCAL_YUM_REPO,,}" == "true" ]]; then
            yum install -y -q nvidia-docker
        else
            # this rpm is officially released (without any dependencies) on GitHub.
            yum install -y -q https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.1/nvidia-docker-1.0.1-1.x86_64.rpm
        fi
    fi

    # Note: nvidia-docker collect all the library files (in the /usr subdirectory) for nvidia GPUs
    # and use *hard link* to map all these files into the directory /var/lib/nvidia-docker/volumes
    # by default. Using *hard link* to map a file into another different partition is forbidden.
    # So, if /var is mounted on a standalone device, creating docker volume will fail absolutely.
    if lsblk | grep -q '/var$'; then
        LOG warn "The '/var' has been mounted on a standalone device now!"
        new_volumes_dir="/usr/lib/nvidia-docker/volumes"
        sed -i -r \
            -e "s|(.*nvidia-docker-plugin -s \S+).*|\1 -d ${new_volumes_dir}|" \
            /usr/lib/systemd/system/nvidia-docker.service
        mkdir -p "${new_volumes_dir}"
        chown -R nvidia-docker:nvidia-docker "${new_volumes_dir}"
    else
        rm -rf /var/lib/nvidia-docker/volumes/*
        # avoid 'permission denied' after reinstalling nvidia-docker.
        chown -R nvidia-docker:nvidia-docker /var/lib/nvidia-docker/volumes
    fi

    util::start_and_enable nvidia-docker.service

    nvidia_docker_url="http://127.0.0.1:3476/docker/cli"
    LOG debug "Sleeping at most 60 seconds to wait for nvidia-docker.service to be ready ..."
    for ((idx=0; idx<6; idx++)); do
        util::sleep_random 5 10
        curl "${nvidia_docker_url}" &>/dev/null && break
    done

    if [[ "${idx}" -eq 6 ]]; then
        LOG error "Failed to wait for nvidia-docker.service to be ready!"
        return 1
    fi

    nvidia_gpu_volume=$(curl -s "${nvidia_docker_url}" 2>/dev/null |\
                        grep -oP '(?<=--volume=)[^:]+(?=:)')
    if [[ -z "${nvidia_gpu_volume}" ]]; then
        LOG error "Failed to get the name of nvidia_gpu_volume from nvidia-docker!"
        return 2
    fi

    LOG info "Creating the docker volume <${nvidia_gpu_volume}> on ${current_ip} ..."
    docker volume inspect "${nvidia_gpu_volume}" &>/dev/null && return 0
    docker volume create --name="${nvidia_gpu_volume}" --driver nvidia-docker
}


function install_nvidia_docker2() {
    current_ip="$(util::current_host_ip)"

    if ! rpm -qa | grep -q nvidia-docker2; then
        LOG debug "Installing nvidia-docker2 on ${current_ip} ..."
        if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
            # ref: https://github.com/NVIDIA/nvidia-docker#centos-7-docker-ce-rhel-7475-docker-ce-amazon-linux-12
            curl -s -L https://nvidia.github.io/nvidia-docker/centos7/nvidia-docker.repo \
                 -o /etc/yum.repos.d/nvidia-docker.repo
        fi
        yum install -y -q nvidia-docker2
    fi

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
