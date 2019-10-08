#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2153,SC2206,SC2207


function init_kube_env() {
    current_ip="$(util::current_host_ip)"

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
        rpm -qa | grep -q epel-release || \
            yum install -y -q epel-release
    fi

    # reset timezone if current timezone is NOT satisfied.
    if ! timedatectl status | grep -q "${KUBE_TIMEZONE}"; then
        timedatectl set-timezone "${KUBE_TIMEZONE}"
    fi

	cat > /etc/sysctl.d/kubernetes.conf <<-EOF
	net.ipv4.ip_forward = 1
	net.ipv4.conf.all.route_localnet = 1
	# in case that arp cache overflow in a latget cluster!
	net.ipv4.neigh.default.gc_thresh1 = 70000
	net.ipv4.neigh.default.gc_thresh2 = 80000
	net.ipv4.neigh.default.gc_thresh3 = 90000
	# net.bridge.bridge-nf-call-iptables = 1
	# net.bridge.bridge-nf-call-ip6tables = 1
	fs.file-max = 65535
	# es requires vm.max_map_count to be at least 262144.
	vm.max_map_count = 262144
	# kubelet requires swap off.
	# https://github.com/kubernetes/kubernetes/issues/53533
	vm.swappiness = 0
	EOF

    LOG debug "Setting some necessary kernel configurations on ${current_ip} ..."
    sysctl -p /etc/sysctl.d/kubernetes.conf

    if util::element_in_array "${current_ip}" "${KUBE_MASTER_IPS_ARRAY[@]}"; then
        # references:
        # https://github.com/denji/nginx-tuning
        # https://www.nginx.com/blog/tuning-nginx
		cat > /etc/sysctl.d/nginx.conf <<-EOF
		net.core.netdev_max_backlog = 262144
		net.core.somaxconn = 262144
		net.ipv4.tcp_tw_reuse = 1
		net.ipv4.tcp_keepalive_time = 600
		net.ipv4.tcp_fin_timeout = 30
		net.ipv4.tcp_max_tw_buckets = 5000
		net.ipv4.tcp_max_orphans = 262144
		net.ipv4.tcp_max_syn_backlog = 262144
		net.ipv4.tcp_timestamps = 0
		net.ipv4.tcp_synack_retries = 1
		net.ipv4.tcp_syn_retries = 1
		EOF

        LOG debug "Setting kernel configurations for nginx on ${current_ip} ..."
        sysctl -p /etc/sysctl.d/nginx.conf
    fi

    swapoff -a
    # disable the swap forever.
    sed -i -r 's|^\S+\s+swap\s+swap.*|# &|' /etc/fstab

    # modify the maxium number of files that can be opened by process
    # to avoid the nginx process of 'nginx-ingress-controller'
    # failed to set 'worker_rlimit_nofile' to '94520' in 0.12.0+
    sed -i -r '/^\* (soft|hard) nofile/d' /etc/security/limits.conf
    echo "* soft nofile 100000" >> /etc/security/limits.conf
    echo "* hard nofile 200000" >> /etc/security/limits.conf

    sed -i '\|/lib64/security/pam_limits.so|d' /etc/pam.d/login
    echo "session required /lib64/security/pam_limits.so" >> /etc/pam.d/login

    # speed up the ssh login authentication.
    sed -i -r \
        -e 's|.*(UseDNS).*|\1 no|' \
        -e 's|.*(GSSAPIAuthentication).*|\1 no|' \
        -e 's|.*(GSSAPICleanupCredentials).*|\1 no|' \
        -e 's|.*(GSSAPIStrictAcceptorCheck).*|\1 no|' \
        /etc/ssh/sshd_config

    systemctl daemon-reload && systemctl restart sshd

    # these packages shouldn't be installed on all the hosts.
    local exclude_pkgs=("createrepo" "docker-ce" "etcd" "flannel"
                        "glusterfs" "httpd" "keepalived" "nginx")
    exclude_pkgs_regex="($(sed 's/ /|/g' <<< "${exclude_pkgs[*]}"))"

    LOG debug "Installing some useful packages on ${current_ip} ..."
    for pkg in "${LOCAL_YUM_RPMS_ARRAY[@]}"; do
        [[ "${pkg}" =~ ^${exclude_pkgs_regex} ]] && continue
        rpm -qa | grep -qE "^${pkg}-" || yum install -y -q "${pkg}"
    done

    # acpid receives the ACPI power button signal from KVM, and then shut itself down
    # the guest machine maybe failed to shutdown/reboot without acpid.service running
    # ref: https://serverfault.com/questions/441204/kvm-qemu-guest-shutdown-problems

    for svc in {atd,acpid}.service; do
        util::start_and_enable "${svc}"
    done

    # need to stop and disable firewalld service.
    util::stop_and_disable firewalld.service

    # clean up the existed iptables rules.
    iptables -F && iptables -F -t nat
    iptables -X && iptables -X -t nat

    # disable selinux if necessary.
    if sestatus | grep -qE '^SELinux status:\s+enabled'; then
        sed -i -r 's|^(SELINUX=).*|\1disabled|' /etc/selinux/config
        setenforce 0
    fi

    # add bash completion script for kubectl command.
    /usr/local/bin/kubectl completion bash >/etc/bash_completion.d/kubectl 2>/dev/null

    # set some environment variables for history command.
    sed -i -r '/(HISTCONTROL|HISTFILESIZE|HISTSIZE|HISTTIMEFORMAT)/d' /root/.bashrc
	cat >> /root/.bashrc <<-EOF
	export HISTCONTROL=ignoreboth
	export HISTFILESIZE=100000
	export HISTSIZE=50000
	export HISTTIMEFORMAT='%y-%m-%d %T '
	EOF
}
