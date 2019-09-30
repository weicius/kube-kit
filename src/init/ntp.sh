#!/usr/bin/env bash
# vim: nu:noai:ts=4


function deploy_ntp_server() {
    sed -i '/ntpdate/d' /etc/crontab

    if ! systemctl list-unit-files | grep ntpd.service -q; then
        yum install -y -q ntp
    fi

    sed -i -r \
        -e "/^server/d" \
        -e "/^# Please consider/aserver 127.127.1.0" \
        -e "/${KUBE_KIT_NETWORK}/d" \
        -e "/^restrict ::1/arestrict ${KUBE_KIT_NETWORK} mask ${KUBE_KIT_NETMASK} nomodify notrap" \
        /etc/ntp.conf

    util::start_and_enable ntpd.service
}


function config_ntpdate_cronjob() {
    local index="${1}"
    sed -i '/ntpdate/d' /etc/crontab

    if systemctl list-unit-files | grep -q ntpd.service; then
        yum remove ntp -y &>/dev/null
    fi

    if ! systemctl list-unit-files | grep -q ntpdate.service; then
        yum install -y -q ntpdate
    fi

    # synchronize local system time at the same time when initializing environments
    # and then synchronize local hardware clock from local system time.
    local ntpdate_cmd="/usr/sbin/ntpdate ${KUBE_NTP_SERVER} >> ${KUBE_SYNC_TIME_LOG} 2>&1"
    local hwclock_cmd="/usr/sbin/hwclock --systohc >> ${KUBE_SYNC_TIME_LOG} 2>&1"
    local sync_time_cmd="${ntpdate_cmd} && ${hwclock_cmd}"
    eval -- "${sync_time_cmd}"

    # config crontab to synchronize localtime from ${KUBE_NTP_SERVER} automatically
    # every ${KUBE_SYNC_TIME_INTERVAL} hours.
	cat >> /etc/crontab <<-EOF
	$((index % 60)) */$((KUBE_SYNC_TIME_INTERVAL % 24)) * * * root ${sync_time_cmd}
	EOF
}
