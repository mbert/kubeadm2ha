# kubeadm2ha - Workarounds for the time before kubeadm HA becomes available

A set of scripts and documentation for adding redundancy (etcd cluster, multiple masters) to a cluster set up with kubeadm 1.8. This code is intended to demonstrate and simplify creation of redundant-master setups while still using kubeadm which is still lacking this functionality. See [kubernetes/kubeadm/issues/546](https://github.com/kubernetes/kubeadm/issues/546) for discussion on this.

This code largely follows the instructions published in [cookeem/kubeadm-ha](https://github.com/cookeem/kubeadm-ha) and added only minor contribution in changing little bits for K8s 1.8 compatibility and automating things.

## Overview

This repository contains a set of ansible scripts to do this. There are three playbooks:

1. _cluster-setup.yaml_ sets up a complete cluster including the HA setup. See below for more details.
2. _cluster-load-balanced.yaml_ sets up an NGINX load balancer for the apiserver.
3. _cluster-uninstall.yaml_ removes data and configuration files to a point that _cluster-setup.yaml_ can be used again.
4. _cluster-dashboard.yaml_ sets up the dashboard including influxdb/grafana. This setup is insecure (no SSL).
5. _etcd-operator.yaml_ sets up the etcd-operator.
6. _cluster-images.yaml_ prefetches all images needed for Kubernetes operations and transfers them to the target hosts.
7. _local-access.yaml_ fetches a patched _admin.conf_ file to _/tmp/MY-CLUSTER-NAME-admin.conf_. After copying it to _~/.kube/config_ remote _kubectl_ access via V-IP / load balancer can be tested. 
8. _uninstall-dashboard.yaml_ removes the dashboard.
9. _cluster-upgrade.yaml_ upgrades a cluster.

## Prerequisites

Ansible version 2.4 or higher is required. Older versions will not work. 

## Configuration

In order to use the ansible scripts, at least two files need to be configured:

1. Either edit _my-cluster.inventory_ or create your own. The inventory _must_ define the following groups: 
 _primary-master_ (a single machine on which _kubeadm_ will be run), _secondary-masters_ (the other masters), _masters_ (all masters), _minions_ (the worker nodes), _nodes_ (all nodes), _etcd_ (all machines on which etcd is installed, usually the masters).
2. Either edit _group_vars/my-cluster.yaml_ to your needs or create your own (named after the group defined in the inventory you want to use). Override settings from _group_vars/all.yaml_ where necessary.

## What the cluster setup does
1. Set up an _etcd_ cluster with self-signed certificates on all hosts in group _etcd._.
2. Set up a _keepalived_ cluster on all hosts in group _masters_.
3. Set up a master instance on the host in group _primary-master_ using _kubeadm._
4. Set up master instances on all hosts in group _secondary-masters_ by copying and patching (replace the primary master's host name and IP) the configuration created by _kubeadm_ and have them join the cluster.
5. Configure kube-proxy to use the V-IP / load balancer URL and configure _kube-dns_ to the master nodes' cardinality.
6. Use _kubeadm_ to join all hosts in the group _minions_. 

## What the additional playbooks can be used for:
- Add an NGINX-based load-balancer to the cluster. After this, the apiserver will be available through the virtual-IP on port 8443.
- Add etcd-operator for use with applications running in the cluster. This is an add-on purely because I happen to need it.
- Pre-fetch and transfer Kubernetes images. This is useful for systems without Internet access.

## What the images setup does

1. Pull all required images locally (hence you need to make sure to have docker installed on the host from which you run ansible).
2. Export the images to tar files.
3. Copy the tar files over to the target hosts.
4. Import the images from the tar files on the target hosts.

## Upgrading a cluster

For upgrading a cluster several steps are needed:

1. Find out which software versions to upgrade to.
2. Set the ansible variables to the new software versions.
3. Run the _cluster-images.yaml_ playbook if the cluster has no Internet access.
4. Run the _cluster-upgrade.yaml_ playbook.

**Note: Never upgrade a productive cluster without having tried it on a reference system before.**

### Preparation

To find out which software versions to upgrade to you will need to run a more recent version of _kubeadm_:

    export VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt) # or manually specify a released Kubernetes version
    export ARCH=amd64 # or: arm, arm64, ppc64le, s390x
    curl -sSL https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubeadm > /tmp/kubeadm
    chmod a+rx /tmp/kubeadm

Copy this file to _/tmp_ on your primary master if necessary. Now run this command for checking prerequisites and determining the versions you'd get:

    /tmp/kubeadm upgrade plan

If the prerequisites are met you'll get a summary of the software versions _kubeadm_ would upgrade to, like this:

    Upgrade to the latest stable version:

    COMPONENT            CURRENT   AVAILABLE
    API Server           v1.8.3    v1.9.2
    Controller Manager   v1.8.3    v1.9.2
    Scheduler            v1.8.3    v1.9.2
    Kube Proxy           v1.8.3    v1.9.2
    Kube DNS             1.14.5    1.14.7
    Etcd                 3.2.7     3.1.11

Note that upgrading _etcd_ is not supported here because we are running it externally, hence we'll have to upgrade it according to _etcd_'s upgrade instruction which is beyond scope here.

We will always use the same version for the Kubernetes base software installed on your OS (_kubelet_, _kubectl_, _kubeadm_) and the self-hosted core components (API Server, Controller Manager, Scheduler, Kube Proxy).
Hence the "v1.9.2" listed in the _kubeadm_ output will go into the `KUBERNETES_VERSION` ansible variable. Edit either _group_vars/all.yaml_ to change this globally or _group_vars/<your-environment>.yaml_ for your environment only.
The same applies for the Kube DNS version which corresponds with the `KUBERNETES_DNS_VERSION` ansible variable.

Having configured this you may now want to fetch and install the new images for your to-be-upgraded cluster, if your cluster has no internet access.
If it has you may want to do this anyway to make the upgrade more seamless.

To do so, run the following command:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory cluster-images.yaml

I usually set the number of concurrent processes manually because if a cluster consists of more than 5 (default) nodes picking a higher value here significantly speeds up the process.

### Perform the upgrade

You may want to backup _/etc/kubernetes_ on all your master machines. Do this before running the upgrade.

The actual upgrade is automated. Run the following command:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory cluster-upgrade.yaml

See the comment above on setting the number of concurrent processes.

The upgrade is not fully free of disruptions:

- while _kubeadm_ applies the changes on a master, it restarts a number of services, hence they may be unavailable for a short time
- if containers running on the minions keep local data they have to take care to rebuild it when relocated to different minions during the upgrade process (i.e. local data is ignored)

If any of these is unacceptable, a fully automated upgrade process does not really make any sense because deep knowledge of the application running in a respective cluster is required to work around this.
Hence in that case a manual upgrade process is recommended.

### If you are using the NGINX load balancer

After the upgrade the NGINX load balancer will not be in use. To reenable it, simply rerun the _cluster-load-balanced.yaml_ playbook.

### If something goes wrong

If the upgrade fails the situation afterwards depends on the phase in which things went wrong.

If _kubeadm_ failed to upgrade the cluster it will try to perform a rollback. Hence if that happened on the first master, chances are pretty good that the cluster is still intact. In that case all you need is to start _docker_, _kubelet_ and _keepalived_ on the secondary masters and then uncordon them (`kubectl uncordon <secondary-master-fqdn>`) to be back where you started from.

If _kubeadm_ on one of the secondary masters failed you still have a working, upgraded cluster, but without the secondary masters in a somewhat undefined condition. You will have to find out what went wrong and join the secondaries manually. Once this has succeeded, finish the automatic upgrade process by processing the second half of the playbook only:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory cluster-upgrade.yaml --tags nodes

If upgrading the software packages (i.e. the second half of the playbook) failed, you still have a working cluster. You may try to fix the problems and continue manually. See the _.yaml_ files under _roles/upgrade-nodes/tasks_ for what you need to do.

If you are trying out the upgrade on a reference system, you may have to downgrade at some point to start again. See the sequence for reinstalling a cluster below for an instruction how to do this (hint: it is important to erase the some base software packages before setting up a new cluster based on a lower Kubernetes version).

## Examples

To run one of the playbooks (e.g. to set up a cluster), run ansible like this:

    ansible-playbook -i <your-inventory-file>.inventory cluster-setup.yaml

You might want to adapt the number of parallel processes to your number of hosts using the `-f' option.

A sane sequence of playbooks for a complete setup would be:

- cluster-setup.yaml
- etcd-operator.yaml
- cluster-dashboard.yaml
- cluster-load-balanced.yaml

The following playbooks can be used as needed:

- cluster-uninstall.yaml
- local-access.yaml
- uninstall-dashboard.yaml

Sequence for reinstalling a cluster:

    INVENTORY=<your-inventory-file> 
    NODES=<number-of-nodes>
    ansible-playbook -f $NODES -i $INVENTORY cluster-uninstall.yaml 
    sleep 3m
    # if you want to downgrade your kubelet, kubectl, ... packages you need to uninstall them first
    # if this is not the issue here, you can skip the following line
    ansible -u root -f $NODES -i $INVENTORY nodes -m command -a "rpm -e kubelet kubectl kubeadm kubernetes-cni"
    for i in cluster-setup.yaml etcd-operator.yaml cluster-dashboard.yaml ; do 
        ansible-playbook -f $NODES -i $INVENTORY $i || break
        sleep 15s
    done

## Known limitations

This is a preview in order to obtain early feedback. It is not done yet. Known limitations are:

- There could be more error checking.
- The code has been tested almost exclusively in a Redhat-like (RHEL) environment. More testing on other distros is needed.

## Why is there no release yet?

Currently the code is in a "works for me" state. In order to make a release more feedback from others is needed.
I still expect some more bugs to be reported and fixed thereafter. Once this phase has ended there will be a first release.
