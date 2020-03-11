#!/bin/bash

errorExit() {
	echo "*** $*" 1>&2
	exit 1
}

CMD="kubeadm upgrade node"

SLEEP_TIME=30
MAX_IT=5
for i in `seq 1 $MAX_IT`; do
	if ( echo "$CMD"; $CMD ); then
		CMD="kubectl uncordon $NODE_NAME"
		echo "$CMD"
		$CMD || errorExit "Error uncordon."
		exit 0
	elif [ "$i" -lt $MAX_IT ]; then
		echo "Upgrade was unsuccessful, waiting 30s and retrying."
		sleep ${SLEEP_TIME}s
		SLEEP_TIME=`expr $SLEEP_TIME \* 2`
	fi
done

errorExit "Upgrade was unsuccessful after ${MAX_IT} attempts. Giving up."
