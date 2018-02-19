#!/bin/sh

errorExit() {
	echo "*** $*" 1>&2
	exit 1
}

KUBECONFIG=/etc/kubernetes/admin.conf
export KUBECONFIG

cp /etc/kubernetes/admin.conf /tmp/admin.conf || errorExit "Error copying '/etc/kubernetes/admin.conf' -> '/tmp/admin.conf'."

#
# If we are using a load balancer we will be accessing apiserver on a port different from what's in the kubeadm configuration,
# even if we are using kubectl against the local instance.
#
SERVER_PORT="`kubectl get -n kube-system configmap kube-proxy -o yaml | grep '^ *server: *https' | sed 's|.*server: *https://[^:]*:\([0-9]*\) *$|\1|'`"
echo "$SERVER_PORT" | egrep -q '^[0-9]+$' || errorExit "Error extracting server port from '/etc/kubernetes/kubelet.conf', got '$SERVER_PORT'."
perl -pi -e "s|^( *server: https://[^:]+):.*|\$1:${SERVER_PORT}|" /tmp/admin.conf

#
# If the dashboard was installed using the ansible job, then there will be an 'admin-user' service account. 
# If there is we use its token for authentication (preferred). 
# Else we leave the file as it is, hence the host's client-side certifiates will be used (less secure).
#
ADMIN_USER_SECRET_NAME="`kubectl -n kube-system get secret | grep admin-user | awk '{ print $1 }'`"
ADMIN_USER_TOKEN="`kubectl -n kube-system describe secret "$ADMIN_USER_SECRET_NAME" | grep '^token' | sed 's/^token:[ \t]*//'`"
if [ -z "$ADMIN_USER_TOKEN" -o `echo "$ADMIN_USER_TOKEN" | wc -l` -eq 1 ]; then
	sed -i '/^ *client-certificate-data:.*/d' /tmp/admin.conf
	sed -i '/^ *client-key-data:.*/d' /tmp/admin.conf
	perl -pi -e "s/^( *)(user: *$)/\$1\$2\n\$1  token: $ADMIN_USER_TOKEN/; s/kubernetes-admin/admin-user/g" /tmp/admin.conf
	cat >>/tmp/admin.conf <<EOF
#
# This configuration file can be used for both kubectl and authentication to the dashboard.
# It uses a token for authentication. The 'admin-user' service account that was installed with the dashboard will be used for this.
#
EOF
	egrep -q "^ *(client-certificate-data|client-key-data):" /tmp/admin.conf && errorExit "Error removing 'client-certificate-data' and 'client-key-data' from '/tmp/admin.conf'.."
	grep -q "^ *token: ${ADMIN_USER_TOKEN}" /tmp/admin.conf || errorExit "Error reconfiguring '/tmp/admin.conf' for use of admin token."
else
	cat >>/tmp/admin.conf <<EOF
#
# This configuration file can be used for kubectl. 
# For authentication it uses the client-side certificates from the server on which it was generated. 
# This is less secure and not recommended for productive environment since these files are not supposed to leave the machine they were installed on.
# For more secure authentication you may want to install the dashboard (and with it the admin-user service account) and re-generate this file.
#
EOF
fi