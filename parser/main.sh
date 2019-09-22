#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1090

# NOTE: should source scripts by this order
source "${__KUBE_KIT_DIR__}/parser/init.sh"
source "${__KUBE_KIT_DIR__}/parser/ipv4.sh"
source "${__KUBE_KIT_DIR__}/parser/etcd.sh"
source "${__KUBE_KIT_DIR__}/parser/cni.sh"
source "${__KUBE_KIT_DIR__}/parser/disk.sh"
source "${__KUBE_KIT_DIR__}/parser/misc.sh"
