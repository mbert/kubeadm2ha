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

## Examples

To run one of the playbooks (e.g. to set up a cluster), run ansible like this:

$ ansible-playbook -i <your-inventory-file>.inventory cluster-setup.yaml

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

## Known limitations
This is a preview in order to obtain early feedback. It is far from done. In particular:

- Error checking is vastly missing (e.g. whether the additional masters successfully joined).
- Those I can't remember now ;)
