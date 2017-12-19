#!/bin/sh

ERR=0
for k in `seq 1 10`; do
    FOUND=$(ps aux |grep kube-apiserver | grep -v grep | wc -l)
    if [ "$FOUND" = "0" ]; then
        ERR=$(expr $ERR + 1)
        sleep 5
        continue
    else
        ERR=0
        break
    fi
done
if [ "$ERR" != "0" ]; then
    echo "systemctl stop keepalived"
    /usr/bin/systemctl stop keepalived
    exit 1
else
    exit 0
fi

