#!/bin/sh

errorExit() {
	echo "*** $*" 1>&2
	exit 1
}

ACTION="$1"
case "$ACTION" in
	drain) ACTION="$ACTION --ignore-daemonsets";;
	uncordon) ;;
	*) errorExit "Usage: $0 <drain|uncordon> <hostname>";;
esac

HOST="$2"
test -n "$HOST" || errorExit "Usage: $0 <drain|uncordon> <hostname>"

export KUBECONFIG=/etc/kubernetes/admin.conf

NODE_NAME="`kubectl get node | awk '{ print $1 }' | grep "^$HOST"`"
test -n "$NODE_NAME" || errorExit "Error determining node name for '$HOST'."

CMD="kubectl $ACTION $NODE_NAME"
echo "$CMD"
$CMD || errorExit "Error $ACTION."


