#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207

################################################################################
# *************** install necessary packages for kube-kit itself ***************
################################################################################

if [[ "${ENABLE_LOCAL_YUM_REPO,,}" != "true" ]]; then
    rpm -qa | grep -q epel-release || \
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
# ********* generate KUBE_ENV_PREFIX_REGEX and KUBE_LIB_FUNCTION_REGEX *********
################################################################################

env_prefix_file="${__KUBE_KIT_DIR__}/etc/env.prefix"
KUBE_ENV_PREFIX_REGEX=$(grep -oP '^[A-Z]+' "${env_prefix_file}" | paste -sd '|')

library_dir="${__KUBE_KIT_DIR__}/library"
# NOTE: kube-kit support the format of definitions of functions:
# 1). the keyword `function` must be at the leftest postion of a line.
# 2). the left brace `{` can be at the same line with `func_name` or a newline.
# 3). the right brace `}` must be at the leftest postion of a line.
# 4). there can be arbitrary spaces between `function` and `func_name`.
# 5). there can be arbitrary spaces between `func_name` and `()`.
# ^function func_name() {
# ^    blabla...
# ^}
# ^function func_name {
# ^    blabla...
# ^}
# ^func_name() {
# ^    blabla...
# ^}

KUBE_FUNCTION_DEF_REGEX="^(function\s+([a-zA-Z0-9:_]+)|([a-zA-Z0-9:_]+)\s*\(\)).*"
KUBE_LIB_FUNCTION_REGEX=$(find "${library_dir}" -type f -name '*.sh' -exec cat {} + |\
    sed -nr "s/${KUBE_FUNCTION_DEF_REGEX}/\2\3/p" | paste -sd '|')

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
