#!/usr/bin/env bash
# vim: nu:noai:ts=4


function nginx_is_running() {
    if systemctl is-active nginx.service -q; then
        return 0
    elif [[ "$(ps -C nginx --no-heading | wc -l)" -ne 0 ]]; then
        return 1
    else
        return 2
    fi
}

if ! nginx_is_running; then
    systemctl restart nginx.service
    sleep 2s
    if ! nginx_is_running; then
        exit 1
    fi
fi
