#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function install_nginx() {
    master_ip="$(util::current_host_ip)"
    nginx_repo="/etc/yum.repos.d/nginx.repo"

    if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" && ! -f "${nginx_repo}" ]]; then
		cat > "${nginx_repo}" <<-EOF
		[nginx]
		name=Nginx Official Repository
		baseurl=https://nginx.org/packages/mainline/centos/7/x86_64
		enabled=1
		gpgcheck=0
		EOF
    fi

    if ! rpm -qa | grep -q '^nginx-'; then
        LOG info "Installing nginx on ${master_ip} ..."
        yum install -y nginx &>/dev/null
    fi
}


function config_nginx() {
    local start_msg_of_apiservers="reverse proxy for kube-apiservers."
    local end_msg_of_apiservers="reverse proxy for other services."
    local include_other_conf_msg="include other nginx configuration files here."
    cpus=$(lscpu | sed -nr 's|^CPU\(s\):\s+([0-9]+)$|\1|p')

    # generate template file of nginx.conf
	cat > /etc/nginx/nginx.conf <<-EOF
	worker_processes ${cpus:-auto};

	# number of file descriptors used for nginx.
	# the limit for the maximum FDs on the server is usually set by the OS.
	# if you don't set FD's then OS settings will be used which is by default 2000
	worker_rlimit_nofile 100000;

	error_log /var/log/nginx/error.log warn;
	pid       /var/run/nginx.pid;

	events {
	    use epoll;

	    # prevent the thundering herd problems.
	    accept_mutex on;

	    # each work process accepts as many connections as possible.
	    multi_accept on;

	    # determines how much clients will be served per worker
	    # max clients = worker_connections * worker_processes
	    # max clients is also limited by the number of socket
	    # connections available on the system (~64k).
	    worker_connections 5000;
	}

	# use nginx to reverse proxy for services which can only use TCP/UDP protocol.
	# https://www.nginx.com/blog/tcp-load-balancing-udp-load-balancing-nginx-tips-tricks
	stream {
	    # nginx built-in variables: http://nginx.org/en/docs/varindex.html
	    # ref: http://nginx.org/en/docs/stream/ngx_stream_log_module.html
	    log_format pretty_stream_logs
	               '[\$time_iso8601] \$remote_addr:\$remote_port => '
	               '\$server_addr:\$server_port => \$upstream_addr '
	               '\$protocol \$bytes_sent \$bytes_received';

	    # ${start_msg_of_apiservers}

	    upstream k8s-secure-apiservers {
	        __REVERSE_PROXY_ALGORITHM__
	        __KUBE_SECURE_SERVERS__
	    }
	    server {
	        listen ${KUBE_VIP_SECURE_PORT};
	        proxy_pass k8s-secure-apiservers;
	        access_log /var/log/nginx/k8s-secure-apiservers.log pretty_stream_logs __nginx_logs_settings__;
	        __STREAM_REVERSE_PROXY_SETTINGS__
	    }

	    # ${end_msg_of_apiservers}
	}

	http {
	    # nginx built-in variables: http://nginx.org/en/docs/varindex.html
	    # ref: http://nginx.org/en/docs/http/ngx_http_log_module.html
	    # https://www.nginx.com/blog/using-nginx-logging-for-application-performance-monitoring
	    # \$request_time - Full request time, starting when NGINX reads the first byte from the
	    # client and ending when NGINX sends the last byte of the response body
	    # \$upstream_connect_time - Time spent establishing a connection with an upstream server
	    # \$upstream_header_time - Time between establishing a connection to an upstream server
	    # and receiving the first byte of the response header
	    # \$upstream_response_time - Time between establishing a connection to an upstream server
	    # and receiving the last byte of the response body
	    # P.S. \$upstream_header_time is included in \$upstream_response_time
	    # \$request_time == \$upstream_connect_time + \$upstream_response_time
	    log_format pretty_http_logs
	               '[\$time_iso8601] \$remote_addr:\$remote_port => '
	               '\$server_addr:\$server_port => \$upstream_addr '
	               '"\$request" \$status \$body_bytes_sent "\$http_user_agent" '
	               'rt=\$request_time uct=\$upstream_connect_time '
	               'uht=\$upstream_header_time urt=\$upstream_response_time';

	    ################################################
	    ## reverse-proxy for nginx-ingress-controller ##
	    ################################################
	    upstream nginx-ingress-controller {
	        __REVERSE_PROXY_ALGORITHM__
	        __KUBE_NGINX_INGRESS_CONTROLLER__
	    }
	    server {
	        listen ${KUBE_VIP_INGRESS_PORT};
	        location / {
	            proxy_pass http://nginx-ingress-controller;
	            __HTTP_REVERSE_PROXY_SETTINGS__
	        }
	        access_log /var/log/nginx/nginx-ingress-controller.log pretty_http_logs __nginx_logs_settings__;
	    }

	    ##############################
	    ## reverse-proxy for heketi ##
	    ##############################
	    upstream heketi {
	        __REVERSE_PROXY_ALGORITHM__
	        __KUBE_HEKETI__
	    }
	    server {
	        listen ${KUBE_VIP_HEKETI_PORT};
	        location / {
	            proxy_pass http://heketi;
	            __HTTP_REVERSE_PROXY_SETTINGS__
	        }
	        access_log /var/log/nginx/heketi.log pretty_http_logs __nginx_logs_settings__;
	    }
	}
	EOF

    if [[ "${KUBE_MASTER_IPS_ARRAY_LEN}" -eq 1 ]] ; then
        # if there is only one master, don NOT need to reverse proxy for kube-apiservers.
        sed -i "/${start_msg_of_apiservers}/,/${end_msg_of_apiservers}/d" /etc/nginx/nginx.conf
    else
        # use nginx to reverse kube-apiservers only when the number of masters is large than 1.
        for master_ip in "${KUBE_MASTER_IPS_ARRAY[@]}"; do
            sed -i -r \
                -e "/__KUBE_SECURE_SERVERS__/i\        server ${master_ip}:${KUBE_APISERVER_SECURE_PORT};" \
                /etc/nginx/nginx.conf
        done
    fi

    for node_ip in "${KUBE_NODE_IPS_ARRAY[@]}"; do
        sed -i -r \
            -e "/__KUBE_NGINX_INGRESS_CONTROLLER__/i\        server ${node_ip}:${KUBE_INGRESS_PORT};" \
            -e "/__KUBE_HEKETI__/i\        server ${node_ip}:${KUBE_HEKETI_PORT};" \
            /etc/nginx/nginx.conf
    done

    # set reverse proxy algorithm for all the proxies and logs settings
    # and the max_fails & fail_timeout of all the upstreams.
    sed -i -r \
        -e 's|__REVERSE_PROXY_ALGORITHM__|hash $remote_addr consistent;|' \
        -e 's|__nginx_logs_settings__|buffer=8k flush=10s|' \
        -e 's|(server [0-9.:]+)|\1 max_fails=3 fail_timeout=15s|' \
        /etc/nginx/nginx.conf

    # set stream reverse proxy settings.
    stream_reverse_proxy_settings=(
	    # nginx will return error if total time of retries exceed 20s.
	    'proxy_next_upstream_timeout 20s;'
	    'proxy_next_upstream_tries 0;'
	    'proxy_connect_timeout 5s;'
    )

    for setting in "${stream_reverse_proxy_settings[@]}"; do
        sed -i -r \
            -e "/__STREAM_REVERSE_PROXY_SETTINGS__/i\        ${setting}" \
            /etc/nginx/nginx.conf
    done

    # set http reverse proxy settings.
    http_reverse_proxy_settings=(
        'proxy_set_header Host $host;'
	    'proxy_set_header X-Real-IP $remote_addr;'
	    'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;'
	    # NOTE: the cases of error, timeout and invalid_header are always considered
	    # unsuccessful attempts even if they are not specified in the directive.
	    # normally, requests with a non-idempotent method (POST, LOCK, PATCH) are not
	    # passed to the next server if a request has been sent to an upstream server.
	    'proxy_next_upstream error timeout invalid_header http_500 non_idempotent;'
	    # nginx will return error if total time of retries exceed 20s.
	    'proxy_next_upstream_timeout 20s;'
	    'proxy_next_upstream_tries 0;'
	    # timeout for establishing a connection with a proxied server.
	    'proxy_connect_timeout 5s;'
	    # timeout for transmitting a request to the proxied server.
	    'proxy_send_timeout 5s;'
	    # timeout for reading a response from the proxied server
	    # NOTE: this should not be set too small.
	    'proxy_read_timeout 600s;'
	    'proxy_request_buffering on;'
        'client_max_body_size 1024m;'
    )

    for setting in "${http_reverse_proxy_settings[@]}"; do
        sed -i -r \
            -e "/__HTTP_REVERSE_PROXY_SETTINGS__/i\            ${setting}" \
            /etc/nginx/nginx.conf
    done

    # delete all the placeholders finally or nginx.conf will be invalid.
    sed -i -r \
        -e '/__KUBE_SECURE_SERVERS__/d' \
        -e '/__REVERSE_PROXY_ALGORITHM__/d' \
        -e '/__STREAM_REVERSE_PROXY_SETTINGS__/d' \
        -e '/__HTTP_REVERSE_PROXY_SETTINGS__/d' \
        -e '/__KUBE_NGINX_INGRESS_CONTROLLER__/d' \
        -e '/__KUBE_HEKETI__/d' \
        /etc/nginx/nginx.conf

    util::start_and_enable nginx.service
}


function install_keepalived() {
    master_ip="$(util::current_host_ip)"
    if ! rpm -qa | grep -q "^keepalived-"; then
        LOG info "Installing keepalived on ${master_ip} ..."
        yum install -y -q keepalived
    fi
}


function config_keepalived() {
    local vip_interface=""
    local index=""
    master_ip="$(util::current_host_ip)"

    # stop keepalived service first if it's active.
    if systemctl list-unit-files | grep -q keepalived; then
        if systemctl is-active keepalived.service -q; then
            systemctl stop keepalived.service
        fi
    fi

    for master_idx in "${!KUBE_MASTER_IPS_ARRAY[@]}"; do
        if [[ "${master_ip}" == "${KUBE_MASTER_IPS_ARRAY[${master_idx}]}" ]]; then
            index="${master_idx}"
            break
        fi
    done

    for iface in $(ip addr show | grep -oP '(?<=\d:\s)[^\s@]+(?=:)' | grep -vP '(docker0|lo)'); do
        ip addr show ${iface} | grep -wq inet || continue
        ipv4_addr=$(ip addr show "${iface}" | grep -oP '(?<=inet\s)[0-9.]+(?=/)')
        if [[ "${ipv4_addr}" == "${master_ip}" ]]; then
            vip_interface="${iface}"
            break
        fi
    done

    if [[ -z "${vip_interface}" ]]; then
        LOG error "Failed to get the interface for VIP on ${master_ip}, please try again ..."
        return 1
    fi

	cat > /etc/keepalived/keepalived.conf <<-EOF
	! Configuration File for keepalived

	global_defs {
	    router_id $(hostname)
	}

	vrrp_script check-nginx {
	    script /usr/local/bin/check-nginx.sh
	    interval 5
	    weight -${KUBE_MASTER_IPS_ARRAY_LEN}
	    fall 2
	    rise 1
	}

	vrrp_instance VI_1 {
	    state $([[ ${index} -eq 0 ]] && echo MASTER || echo BACKUP)
	    priority $((100 + KUBE_MASTER_IPS_ARRAY_LEN - index))
	    interface ${vip_interface}
	    mcast_src_ip ${master_ip}
	    virtual_router_id 51
	    advert_int 1
	    authentication {
	        auth_type PASS
	        auth_pass r00tme
	    }
	    virtual_ipaddress {
	        ${KUBE_MASTER_VIP}
	    }
	    track_script {
	        check-nginx
	    }
	}
	EOF

    sed -r -i \
        -e 's|.*(KEEPALIVED_OPTIONS=).*|\1"-D -d -S 0"|' \
        /etc/sysconfig/keepalived

    local keepalived_log="/var/log/keepalived.log"
    if ! grep -q "${keepalived_log}" /etc/rsyslog.conf; then
        sed -r -i \
            -e "\|/var/log/messages|alocal0.*$(printf ' %.0s' {1..48})${keepalived_log}" \
            /etc/rsyslog.conf
    fi

    for svc in keepalived rsyslog; do
        util::start_and_enable "${svc}"
    done
}
