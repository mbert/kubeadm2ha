#!/bin/sh

cloneHeapster() {
	if [ -d heapster ]; then
		cd heapster || return 1
		git reset --hard HEAD || return 1
		git pull || return 1
	else
		git clone https://github.com/kubernetes/heapster.git || return 1
	fi
}

cd /tmp
if ! cloneHeapster; then
	rm -rf heapster
	cloneHeapster
fi
