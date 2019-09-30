#!/usr/bin/env bash
# vim: nu:noai:ts=4

functions_file="${__KUBE_KIT_DIR__}/src/init/ntp.sh"

# deploy local ntp server on the first machine.
if [[ "${ENABLE_LOCAL_NTP_SERVER,,}" == "true" ]]; then
    LOG debug "Deploying local ntp server on ${KUBE_NTP_SERVER} now ..."
    ssh::execute -h "${KUBE_NTP_SERVER}" \
                 -s "${functions_file}" \
                 -- "deploy_ntp_server"
fi


function config_ntpdate() {
    if [[ "${ENABLE_LOCAL_NTP_SERVER,,}" == "true" && \
          "${HOST}" == "${KUBE_NTP_SERVER}" ]]; then
        return 0
    fi

    LOG debug "Configurating cronjob to update time automatically on ${HOST} ..."
    ssh::execute -h "${HOST}" \
                 -s "${functions_file}" \
                 -- "config_ntpdate_cronjob" "${INDEX}"
}

local::execute_parallel -h all -f config_ntpdate
