#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207


function heketi_contains_node_and_device() {
    local device="${1}"

    glusterfs_node_ip=$(util::get_glusterfs_node_ip)
    # if heketi is not deployed, just return 1.
    curl -sf "${HEKETI_SERVER}/hello" || return 1
    for heketi_node_id in $(heketi-cli node list | grep -oP '(?<=^Id:)[a-f0-9]+'); do
        heketi-cli node info "${heketi_node_id}" | grep -q "${glusterfs_node_ip}" || continue
        heketi-cli node info "${heketi_node_id}" | grep -q "${device}" && return 0
    done

    return 2
}


function ensure_pvcreate_can_succeed() {
    local device="${1}"

    if ! pvcreate "${device}" &>/dev/null; then
        dd if=/dev/zero of="${device}" bs=1M count=1
    else
        pvremove "${device}"
    fi
}


function init_heketi_dir() {
    [[ -d "${KUBE_SHARED_VOLUME_MNT_DIR}/heketi" ]] && return 0
    mkdir -p ${KUBE_SHARED_VOLUME_MNT_DIR}/heketi/{backup,config,db}
}


function modify_sshd_port() {
    sed -i -r "s|(\"port\"): \"22\",|\1: \"${SSHD_PORT}\",|" \
        "${KUBE_SHARED_VOLUME_MNT_DIR}/heketi/config/heketi.json"
}


function config_heketi_cli() {
    # to store /etc/heketi/fstab
    [[ -d /etc/heketi ]] || mkdir -p /etc/heketi
    sed -i '/HEKETI_CLI_SERVER/d' /root/.bashrc
    echo "export HEKETI_CLI_SERVER=${HEKETI_SERVER}" >> /root/.bashrc
}


function get_heketi_cluster_id() {
    heketi-cli cluster list | grep -oP '(?<=^Id:)[0-9a-f]+'
}


function load_heketi_topology() {
    local heketi_topology_file="${KUBE_SHARED_VOLUME_MNT_DIR}/heketi/config/topology.json"

    # $ declare -a HEKETI_NODE_IPS_ARRAY=([0]="192.168.10.11" [1]="192.168.10.12" [2]="192.168.10.13")
    # $ declare -A HEKETI_DISKS_ARRAY=([192.168.10.11]="/dev/sdc" [192.168.10.12]="/dev/sdc /dev/sdd" [192.168.10.13]="/dev/sdc /dev/sdd /dev/sde")
    # heketi_node_ip => glusterfs_node_ip
    # 192.168.10.11  => 192.168.30.11
    # 192.168.10.12  => 192.168.30.12
    # 192.168.10.13  => 192.168.30.13
    # glusterfs_node_ips=([0]="192.168.30.11" [1]="192.168.30.12" [2]="192.168.30.13")
    local -a glusterfs_node_ips
    for heketi_node_ip in "${HEKETI_NODE_IPS_ARRAY[@]}"; do
        glusterfs_node_ips+=($(ssh::execute -h "${heketi_node_ip}" \
                                            -- "util::get_glusterfs_node_ip"))
    done

    # use two environments HEKETI_NODE_IPS_ARRAY and HEKETI_DISKS_ARRAY
    # to generate a raw string of python dict (glusterfs_devices_dict):
    # glusterfs_devices_objects={"192.168.30.11":["/dev/sdc"],"192.168.30.12":["/dev/sdc","/dev/sdd"],"192.168.30.13":["/dev/sdc","/dev/sdd","/dev/sde"]}
    # glusterfs_devices_objects = {
    #     "192.168.30.11": [
    #         "/dev/sdc"
    #     ],
    #     "192.168.30.12": [
    #         "/dev/sdc",
    #         "/dev/sdd"
    #     ],
    #     "192.168.30.13": [
    #         "/dev/sdc",
    #         "/dev/sdd",
    #         "/dev/sde"
    #     ]
    # }
    glusterfs_devices_objects=$(
        # ref:
        # https://stackoverflow.com/a/34477713/6149338
        # https://stackoverflow.com/a/40491396/6149338
        # NOTE: heketi_node_ip is configurated in etc/heketi.ini
        # and is in the kubernetes cluster subnet.
        for idx in "${!HEKETI_NODE_IPS_ARRAY[@]}"; do
            heketi_node_ip="${HEKETI_NODE_IPS_ARRAY[${idx}]}"
            glusterfs_node_ip="${glusterfs_node_ips[${idx}]}"
            devices="${HEKETI_DISKS_ARRAY[${heketi_node_ip}]}"
            sed 's| |\n|g' <<< "${devices}" | jq -R '.' | jq -s "{\"${glusterfs_node_ip}\": .}"
        done | jq -c -M -s add
    )

    # ref: https://github.com/heketi/heketi/blob/master/client/cli/go/topology-sample.json
    LOG info "Generating a topology file of heketi cluster for glusterfs ..."
	python > "${heketi_topology_file}" <<-EOF
	import json

	glusterfs_node_ips = "${glusterfs_node_ips[@]}"
	glusterfs_devices_dict = ${glusterfs_devices_objects}

	nodes = []
	for glusterfs_node_ip in glusterfs_node_ips.split():
	    nodes.append({
	        "node": {
	            "hostnames": {
	                "manage": [glusterfs_node_ip],
	                "storage": [glusterfs_node_ip]
	            },
	            "zone": 1
	        },
	        "devices": glusterfs_devices_dict[glusterfs_node_ip]
	    })

	topology = {
	    "clusters": [
	        {
	            "nodes": nodes
	        }
	    ]
	}

	print(json.dumps(topology, indent=4))

	EOF

    LOG info "Loading the topology of glusterfs cluster into heketi ..."
    heketi-cli topology load --json="${heketi_topology_file}"
}
