#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207,SC2216


function _get_all_options() {
    local all_options=(${@})
    local options_done=()
    local options_todo=()

    options_done=($(cat "${KUBE_KIT_INDICATE_FILE}" 2>/dev/null | grep -v all |\
        grep -oP "(?<=kube-kit ${SUBCMD} )\S+(?= completed)")) || true

    local flag="false"
    for option in "${all_options[@]}"; do
        if [[ "${flag}" == "true" ]]; then
            options_todo+=(${option})
            continue
        fi

        last_idx=$(util::last_idx_in_array "${option}" "${options_done[@]}")
        if [[ "${last_idx}" -eq -1 ]]; then
            options_todo+=(${option})
            flag="true"
        else
            # delete all the elements from index 0
            # to the last index of current element.
            for delete_idx in $(seq 0 ${last_idx}); do
                unset "options_done[${delete_idx}]"
            done
            # reset the array 'options_done', this is unnecessary.
            options_done=(${options_done[@]})
        fi
    done

    echo -n "${options_todo[@]}"
}


function _get_init_all_options() {
    local init_options=()

    for option in ${SUBCMD_OPTIONS["init"]}; do
        [[ "${option}" == "all" ]] && continue
        [[ "${ENABLE_LOCAL_YUM_REPO,,}" == "false" && "${option}" == "localrepo" ]] && continue
        [[ "${ENABLE_GLUSTERFS,,}" == "false" && "${option}" == "glusterfs" ]] && continue
        init_options+=(${option})
    done

    _get_all_options "${init_options[@]}"
}


function _get_deploy_all_options() {
    local deploy_options=()

    for option in ${SUBCMD_OPTIONS["deploy"]}; do
        [[ "${option}" =~ ^(heapster|dashboard|all)$ ]] && continue
        [[ "${ENABLE_CNI_PLUGIN}" == "true" && "${option}" == "flannel" ]] && continue
        [[ "${ENABLE_CNI_PLUGIN}" == "false" && "${option}" == "calico" ]] && continue
        deploy_options+=(${option})
    done

    _get_all_options "${deploy_options[@]}"
}


################################################################################
#### the following functions implement each subcommand of kube-kit commmand ####
################################################################################

function cmd::check() {
    case "${1}" in
        env)
            LOG info "Checking if the basic requirements are satisfied ..."
            source "${__KUBE_KIT_DIR__}/cmd/check/env.sh" "${KUBE_ALL_IPS_ARRAY[@]}"
            ;;
    esac
}


function cmd::init() {
    case "${1}" in
        localrepo)
            if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
                LOG error "You choose NOT to use local repo, exit ..."
                return 1
            fi
            LOG info "Creating a local yum mirror on ${LOCAL_YUM_REPO_HOST} ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/localrepo.sh"
            ;;
        hostname)
            LOG info "Resetting hostname & /etc/hosts on all the hosts ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/hostname.sh"
            ;;
        auto-ssh)
            LOG info "Configurating the certifications to allow ssh into each other ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/auto-ssh.sh"
            ;;
        ntp)
            LOG info "Setting crontab to sync time from local or remote ntpd server ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/ntp.sh"
            ;;
        disk)
            LOG info "Auto-partition a standalone disk into LVs to store data separately ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/disk.sh"
            ;;
        glusterfs)
            if [[ "${ENABLE_GLUSTERFS,,}" != "true" ]]; then
                LOG warn "You choose NOT to use glusterfs as storage, exit ..."
                return 2
            fi
            LOG info "Initializing the glusterfs cluster for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/glusterfs.sh"
            ;;
        env)
            LOG info "Configurating the basic environments on all machines ..."
            source "${__KUBE_KIT_DIR__}/cmd/init/env.sh"
            ;;
        cert)
            LOG info "Generating the certifications for all components in the cluster ..."
            for script in certificate kubeconfig; do
                source "${__KUBE_KIT_DIR__}/cmd/init/${script}.sh"
            done
            ;;
        all)
            LOG info "Initializing all the basic environments for kubernetes cluster ..."
            init_all_options=($(_get_init_all_options))
            if [[ "${#init_all_options[@]}" -eq 0 ]]; then
                LOG warn "All actions of 'init' sub-command have been executed successfully," \
                         "do nothing! Or, you can delete the indicate file" \
                         "'${KUBE_KIT_INDICATE_FILE}' to start over again ..."
                return 3
            fi

            first_option="${init_all_options[0]}"
            LOG info "\`kube-kit init all\` will start from <${first_option}>," \
                     "because all the options before <${first_option}> have" \
                     "been executed successfully!"

            for option in "${init_all_options[@]}"; do
                util::sleep_random
                # the output of subcommand of 'kube-kit init all' command should not be recorded.
                # otherwise, the local logfile will record the same messages twice. so, we need to
                # pass a variable 'RECORD_LOGS' to tell 'kube-kit' to drop logs in this situation.
                bash -c "export RECORD_LOGS=false; ${__KUBE_KIT_DIR__}/kube-kit init ${option}"
            done
    esac
}


function cmd::deploy() {
    case "${1}" in
        etcd)
            if etcd_env_ready; then
                LOG info "Deploying the etcd (in)secure cluster for kube-apiserver, flannel and calico ..."
                source "${__KUBE_KIT_DIR__}/cmd/deploy/etcd-cluster.sh"
            else
                return 1
            fi
            ;;
        flannel)
            if [[ "${ENABLE_CNI_PLUGIN,,}" == "true" ]]; then
                LOG error "You have choosen to use CNI plugin for kubernetes, can NOT deploy flannel!"
                LOG info "Please execute './kube-kit deploy calico' later!"
                return 1
            elif etcd_cluster_ready; then
                LOG info "Deploying the flanneld on all nodes ..."
                source "${__KUBE_KIT_DIR__}/cmd/deploy/flannel.sh"
            else
                return 2
            fi
            ;;
        docker)
            LOG info "Deploying the docker-ce-${DOCKER_VERSION} on all machines ..."
            if [[ "${ENABLE_CNI_PLUGIN,,}" == "true" ]]; then
                source "${__KUBE_KIT_DIR__}/cmd/deploy/docker.sh"
            elif flanneld_ready; then
                source "${__KUBE_KIT_DIR__}/cmd/deploy/docker.sh"
            else
                return 1
            fi
            ;;
        proxy)
            LOG info "Deploying the Reverse-proxy for all the exposed services ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/proxy.sh"
            ;;
        master)
            master_env_ready || return 1
            LOG info "Deploying the kubernetes masters ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/k8s-masters.sh"
            ;;
        node)
            node_env_ready || return 1
            LOG info "Deploying the kubernetes nodes ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/k8s-nodes.sh"
            ;;
        crontab)
            LOG info "Deploying the Crontab jobs on all hosts ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/crontab.sh"
            ;;
        calico)
            if [[ "${ENABLE_CNI_PLUGIN,,}" == "false" ]]; then
                LOG error "You have NOT choosen to use CNI plugin, can NOT deploy CNI plugin(calico)!"
                return 1
            elif ! util::can_ping "${KUBE_MASTER_VIP}"; then
                LOG error "KUBE_MASTER_VIP '${KUBE_MASTER_VIP}' can NOT be reached now!"
                # if there is only ONE master, KUBE_MASTER_VIP should be reached by ping.
                LOG info "You might have forgotten to execute './kube-kit deploy proxy'"
                return 2
            fi

            for _ in $(seq 5); do
                if [[ $(kubectl get nodes --no-headers | grep -wc 'Ready') -ne \
                      ${KUBE_NODE_IPS_ARRAY_LEN} ]]; then
                    sleep "$((RANDOM % 5 + 5))s"
                else
                    LOG info "Deploying the CNI plugin(calico) for kubernetes cluster ..."
                    source "${__KUBE_KIT_DIR__}/cmd/deploy/calico.sh"
                    return 0
                fi
            done

            LOG error "Kubernetes nodes are NOT all be in Ready status now!"
            return 3
            ;;
        coredns)
            LOG info "Deploying the CoreDNS addon for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/coredns.sh"
            ;;
        heketi)
            LOG info "Deploying the Heketi service to manage glusterfs cluster automatically ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/heketi.sh"
            ;;
        harbor)
            LOG info "Deploying the harbor docker private image repertory ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/harbor.sh"
            ;;
        ingress)
            LOG info "Deploying the nginx ingress controller addon for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/ingress.sh"
            ;;
        prometheus)
            LOG info "Deploying the Prometheus monitoring for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/prometheus.sh"
            ;;
        heapster)
            coredns_ready || return 1
            LOG info "Deploying the Heapster addon for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/heapster.sh"
            ;;
        dashboard)
            heapster_ready || return 1
            LOG info "Deploying the Dashboard addon for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/dashboard.sh"
            ;;
        efk)
            LOG info "Deploying the EFK logging addon for kubernetes cluster ..."
            source "${__KUBE_KIT_DIR__}/cmd/deploy/fluentd-es.sh"
            ;;
        all)
            LOG info "Deploying all the components for kubernetes cluster ..."
            deploy_all_options=($(_get_deploy_all_options))
            if [[ "${#deploy_all_options[@]}" -eq 0 ]]; then
                LOG warn "All actions of 'deploy' sub-command have been executed" \
                         "successfully, do nothing! Or, you can delete the indicate" \
                         "file '${KUBE_KIT_INDICATE_FILE}' to start over again ..."
                return 1
            fi

            first_option="${deploy_all_options[0]}"
            LOG info "\`kube-kit deploy all\` will start from <${first_option}>," \
                     "because all the options before <${first_option}> have" \
                     "been executed successfully!"

            for option in "${deploy_all_options[@]}"; do
                util::sleep_random
                # the output of subcommand of 'kube-kit deploy all' command should not
                # be recorded. otherwise, the local logfile will record the same messages
                # twice. so, we need to pass a variable 'RECORD_LOGS' to tell 'kube-kit'
                # to drop logs in this situation.
                bash -c "export RECORD_LOGS=false; ${__KUBE_KIT_DIR__}/kube-kit deploy ${option}"
            done
    esac
}


function cmd::clean() {
    case "${1}" in
        master|node)
            source "${__KUBE_KIT_DIR__}/cmd/clean/kubernetes.sh" "${1}"
            ;;
        all)
            if [[ "${ENABLE_FORCE_MODE,,}" == "false" ]]; then
                LOG warn -n "Cleaning all components will DESTROY" \
                            "kubernetes cluster, continue? [y/N]: "
                read answer1
            else
                answer1="y"
            fi

            [[ "${answer1,,}" == "n" ]] && return 0

            # need to delete the indicate file of kube-kit and checksum of image files.
            rm -f ${KUBE_KIT_INDICATE_FILE} ${__KUBE_KIT_DIR__}/binaries/harbor/*.sha256

            source "${__KUBE_KIT_DIR__}/cmd/clean/etcd-cluster.sh"
            for clean_idx in $(seq "${CLEAN_ENV_TIMES:-2}"); do
                LOG info "Cleaning up all the kubernetes-releated components: #${clean_idx} ..."

                for role in master node; do
                    source "${__KUBE_KIT_DIR__}/cmd/clean/kubernetes.sh" "${role}"
                done

                if [[ "${clean_idx}" -lt "${CLEAN_ENV_TIMES:-2}" ]]; then
                    sleep_time=$((RANDOM % 10 + 50))
                    LOG debug "Sleeping ${sleep_time} seconds to start next cleaning ..."
                    sleep "${sleep_time}s"
                fi
            done
            ;;
    esac
}


function cmd::update() {
    case "${1}" in
        cluster)
            source "${__KUBE_KIT_DIR__}/cmd/update/k8s-cluster.sh"
            ;;
        node)
            source "${__KUBE_KIT_DIR__}/cmd/update/k8s-nodes.sh"
            ;;
        heketi)
            source "${__KUBE_KIT_DIR__}/cmd/update/heketi.sh"
            ;;
    esac
}
