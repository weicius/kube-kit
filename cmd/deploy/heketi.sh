#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2045,SC2153,SC2206,SC2207

functions_file="${__KUBE_KIT_DIR__}/src/deploy/heketi.sh"
heketi_dir="${__KUBE_KIT_DIR__}/addon/heketi"
heketi_manifest_dir="${heketi_dir}/manifest"

[[ -d "${heketi_manifest_dir}" ]] || mkdir -p "${heketi_manifest_dir}"
cp -f "${heketi_dir}/heketi.yaml" "${heketi_manifest_dir}/heketi.yaml"

# NOTE: heketi_node_ip is configurated in etc/heketi.ini
# and is in the kubernetes cluster subnet.
for heketi_node_ip in "${HEKETI_NODE_IPS_ARRAY[@]}"; do
    devices=(${HEKETI_DISKS_ARRAY[${heketi_node_ip}]})
    for device in "${devices[@]}"; do
        ssh::execute -q \
                     -h "${heketi_node_ip}" \
                     -s "${functions_file}" \
                     -- "heketi_contains_node_and_device" \
                        "${device}" | tee /dev/null

        # if the heketi cluster contains the node and the device,
        # skip the following actions to avoid to init same heketi
        # node and device multiple times.
        [[ "${PIPESTATUS[0]}" -eq 0 ]] && continue

        ssh::execute -h "${heketi_node_ip}" \
                     -s "${__KUBE_KIT_DIR__}/src/init/disk.sh" \
                     -- "wipe_device" "${device}"

        continue
        # maybe this is unnecessary.
        ssh::execute -h "${heketi_node_ip}" \
                     -s "${functions_file}" \
                     -- "ensure_pvcreate_can_succeed" \
                        "${device}"
    done
done

ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "init_heketi_dir"

scp::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${__KUBE_KIT_DIR__}/addon/heketi/heketi.json" \
             -d "${KUBE_SHARED_VOLUME_MNT_DIR}/heketi/config/"

# need to modify the default port of sshd for heketi.
ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "modify_sshd_port"

scp::execute_parallel -h "node" \
                      -s "${__KUBE_KIT_DIR__}/binaries/heketi/heketi-cli" \
                      -d "/usr/local/bin"

ssh::execute_parallel -h "node" \
                      -s "${functions_file}" \
                      -- "config_heketi_cli"

sed -i -r \
    -e "s|__HEKETI_IMAGE__|${HEKETI_IMAGE}|" \
    -e "s|__KUBE_HEKETI_PORT__|${KUBE_HEKETI_PORT}|" \
    -e "s|__KUBE_SHARED_VOLUME_MNT_DIR__|${KUBE_SHARED_VOLUME_MNT_DIR}|" \
    "${heketi_manifest_dir}/heketi.yaml"

kubectl delete -f "${heketi_manifest_dir}/heketi.yaml" 2>/dev/null || true
wait::resource -t deployment -n heketi -s deleted

kubectl create -f "${heketi_manifest_dir}/heketi.yaml"
wait::resource -t deployment -n heketi -s ready

if ! wait::until -t 100 -i 5 -f ready::heketi; then
    LOG error "Failed to wait for heketi service to be ready ..."
    exit 1
fi

ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
             -s "${functions_file}" \
             -- "load_heketi_topology"

cluster_id=$(ssh::execute -h "${KUBE_NODE_IPS_ARRAY[0]}" \
                          -s "${functions_file}" \
                          -- "get_heketi_cluster_id")

cp -f "${heketi_dir}/default-sc.yaml" "${heketi_manifest_dir}/default-sc.yaml"

sed -i -r \
    -e "s|__CLUSTER_ID__|${cluster_id}|" \
    -e "s|__HEKETI_SERVER__|${HEKETI_SERVER}|" \
    -e "s|__GLUSTERFS_DEFAULT_SC__|${GLUSTERFS_DEFAULT_SC}|" \
    -e "s|__GLUSTERFS_VOLUME_TYPE__|${GLUSTERFS_VOLUME_TYPE}|" \
    "${heketi_manifest_dir}/default-sc.yaml"

if kubectl get storageclass "${GLUSTERFS_DEFAULT_SC}" &>/dev/null; then
    kubectl delete storageclass "${GLUSTERFS_DEFAULT_SC}"
fi

kubectl create -f "${heketi_manifest_dir}/default-sc.yaml"
