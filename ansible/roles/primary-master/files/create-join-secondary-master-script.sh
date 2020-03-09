#!/bin/sh

errorExit() {
	echo "*** $*" 1>&2
	exit 1
}

echo "$0 $@"

INFILE="$1"
OUTFILE="$2"

test -r "$INFILE" || errorExit "Unable to read '$INFILE', usage: $0 <InFile> <OutFile>"
test -n "$OUTFILE" || errorExit "Usage: $0 <InFile> <OutFile>"

echo '#!/bin/bash' >"$OUTFILE"
test -r "$OUTFILE" || errorExit "Unable to write to '$OUTFILE'."
chmod a+x "$OUTFILE" || errorExit "Unable to set permissions to '$OUTFILE'."

JOIN_LINE="$(grep -A2 '^ *kubeadm join' "$INFILE" | perl -p -e 's/\\\n//' | grep -e --control-plane | sed -e 's/ \+/ /g' -e 's/^ \+//' -e 's/$/ --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests/')"

echo "${JOIN_LINE} 2>&1 | tee /tmp/kubeadm-join.out" >>"$OUTFILE"
echo 'exit ${PIPESTATUS[0]}' >>"$OUTFILE"