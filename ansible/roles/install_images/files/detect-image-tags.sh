#!/bin/sh

TAG_PADDERN='^v?[0-9][^a-z]+$'

errorExit() {
	echo "*** $*" 1>&2
	exit 1
}


getKubeAdmDefaults() {
	CMD="kubeadm config images list --kubernetes-version $1"
	OUTPUT="$(${CMD})" || errorExit "Error running '${CMD}'"

	echo "$OUTPUT" | sed \
		-e 's|.*/kube-apiserver:|THE_KUBERNETES_TAG: |' \
		-e 's|.*/coredns/coredns:|THE_COREDNS_TAG: |' \
		-e 's|.*/pause:|THE_PAUSE_TAG: |' \
		-e 's|.*/etcd:|THE_ETCD_TAG: |' \
		| grep '^[A-Z].*:'
}

getLatestTag() {
	LATEST="$($ORAS repo tags $2 | grep -E "$TAG_PADDERN" | sort -V | tail -1)" || errorExit "Error resolving "
	test -n "$LATEST" || errorExit "Unable to read the latest tag for image '$2'."
	echo "$1: $LATEST"
}


test -n "$2" || errorExit "Usage: $0 <K8S_VERSION> <HOST_ARCH>"
K8S_VERSION="$1"
HOST_ARCH="$2"

command -V docker >/dev/null || errorExit "Error, no 'docker' command found in path."
command -V kubeadm >/dev/null || errorExit "Error, no 'kubeadm' command found in path."
ORAS="docker run -it --rm ghcr.io/oras-project/oras:main"


getKubeAdmDefaults $K8S_VERSION

getLatestTag THE_KEEPALIVED_TAG docker.io/osixia/keepalived
getLatestTag THE_KUBE_VIP_TAG docker.io/plndr/kube-vip
getLatestTag THE_NGINX_TAG docker.io/library/nginx
getLatestTag THE_HAPROXY_TAG docker.io/library/haproxy
getLatestTag THE_BUSYBOX_TAG docker.io/library/busybox
getLatestTag THE_DASHBOARD_TAG docker.io/kubernetesui/dashboard-${HOST_ARCH}
getLatestTag THE_METRICS_SCRAPER_TAG docker.io/kubernetesui/metrics-scraper-${HOST_ARCH}
getLatestTag THE_METRICS_SERVER_TAG registry.k8s.io/metrics-server-${HOST_ARCH}

