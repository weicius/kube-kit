#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# *************** install necessary packages for kube-kit itself ***************
################################################################################

if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
    yum install -y -q epel-release

    # there packages are necessary for kube-kit.
    for pkg in sshpass jq net-tools iproute; do
        # `yum list installed` needs access to internet.
        rpm -qa | grep -q "${pkg}" || \
            yum install -y -q "${pkg}"
    done
else
    # NOTE: oniguruma is required by jq, need to install it first.
    for pkg in sshpass oniguruma jq net-tools iproute; do
        rpm -qa | grep -q "${pkg}" || \
            yum install -y -q ${__KUBE_KIT_DIR__}/binaries/rpms/${pkg}-*.rpm
    done
fi

################################################################################
# ********************* validate the version of kubernetes *********************
################################################################################

KUBE_VERSION_REGEX="v[0-9]+(\.[0-9]+){2}"
if [[ ! ("${KUBE_VERSION}" =~ ^${KUBE_VERSION_REGEX}$) ]]; then
    LOG error "KUBE_VERSION '${KUBE_VERSION}' is invalid, version format: v1.2.3"
    exit 100
fi

# kubernetes version e.g: v1.2.3, fetch its major minor and patch version:
# KUBE_MAJOR_VERSION=1, KUBE_MINOR_VERSION=2, KUBE_PATCH_VERSION=3
IFS=. read -r KUBE_{MAJOR,MINOR,PATCH}_VERSION <<< "${KUBE_VERSION:1}"
