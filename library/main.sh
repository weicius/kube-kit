#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1090,SC2038,SC2044

find "${__KUBE_KIT_DIR__}" -name '*.sh' -o -name kube-kit | xargs chmod +x

for script in $(find "${__KUBE_KIT_DIR__}/library" -name '*.sh'); do
    # NOTE: can't source 'main.sh' itself.
    [[ "${script}" =~ main ]] && continue
    source "${script}"
done
