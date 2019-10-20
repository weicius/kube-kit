#!/usr/bin/env bash
# vim: nu:noai:ts=4

ingress_dir="${__KUBE_KIT_DIR__}/addon/ingress"
ingress_manifest_dir="${ingress_dir}/manifest"

[[ -d "${ingress_manifest_dir}" ]] || mkdir -p "${ingress_manifest_dir}"
cp -f "${ingress_dir}/nginx-ingress-controller.yaml" \
      "${ingress_manifest_dir}/nginx-ingress-controller.yaml"

sed -i -r \
    -e "s|__KUBE_NGINX_INGRESS_CONTROLLER_IMAGE__|${KUBE_NGINX_INGRESS_CONTROLLER_IMAGE}|" \
    "${ingress_manifest_dir}/nginx-ingress-controller.yaml"

kubectl delete -f "${ingress_manifest_dir}" 2>/dev/null || true
kubectl create -f "${ingress_manifest_dir}"
wait::resource -t deployment -N ingress-nginx -n nginx-ingress-controller -s ready
