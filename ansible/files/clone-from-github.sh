#!/bin/sh

if [ -z "$1" -o -z "$2" ]; then
	echo "Usage: $0 <repo-owner> <repo-name> [<ref>]" 1>&2
	exit 1
fi

OWNER="$1"
REPO="$2"
REF="$3"

cloneFromGithub() {
	if [ -d ${REPO} ]; then
		cd ${REPO} || return 1
		git reset --hard HEAD || return 1
		git checkout master || return 1
		git pull || return 1
	else
		git clone https://github.com/${OWNER}/${REPO}.git || return 1
	fi
}

cd /tmp
if ! cloneFromGithub; then
	rm -rf ${REPO}
	cloneFromGithub
fi

if [ -n "$REF" ]; then
	cd /tmp/${REPO} && git checkout "$REF"
fi