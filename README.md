# kubeadm2ha - Automatic setup of HA clusters using kubeadm

A set of scripts and documentation for adding redundancy (etcd cluster, multiple masters) to a cluster set up with kubeadm 1.8. This code is intended to demonstrate and simplify creation of redundant-master setups while still using kubeadm which is still lacking this functionality. See [kubernetes/kubeadm/issues/546](https://github.com/kubernetes/kubeadm/issues/546) for discussion on this.

This code largely follows the instructions published in [cookeem/kubeadm-ha](https://github.com/cookeem/kubeadm-ha) and added only minor contribution in changing little bits for K8s 1.8 compatibility and automating things.

## Overview

This repository contains a set of ansible scripts to do this. There are three playbooks:

1. _cluster-setup.yaml_ sets up a complete cluster including the HA setup. See below for more details.
2. _cluster-load-balanced.yaml_ sets up an NGINX load balancer for the apiserver.
3. _cluster-uninstall.yaml_ removes data and configuration files to a point that _cluster-setup.yaml_ can be used again.
4. _cluster-dashboard.yaml_ sets up the dashboard including influxdb/grafana.
5. _etcd-operator.yaml_ sets up the etcd-operator.
6. _prometheus-operator.yaml_ sets up the prometheus-operator.
7. _efk-stack.yaml_ sets up an EFK stack for centralised logging.
8. _cluster-images.yaml_ prefetches all images needed for Kubernetes operations and transfers them to the target hosts.
9. _local-access.yaml_ fetches a patched _admin.conf_ file to _/tmp/MY-CLUSTER-NAME-admin.conf_. After copying it to _~/.kube/config_ remote _kubectl_ access via V-IP / load balancer can be tested. 
10. _uninstall-dashboard.yaml_ removes the dashboard.
11. _uninstall-efk-stack.yaml_ removes the EFK stack including Fluentd cache and Elasticsearch data files.

## Prerequisites

Ansible version 2.4 or higher is required. Older versions will not work. 

On the target environment, some settings for successful installation of Kubernetes are necessary. The "Before you begin" section in the [official kubernetes documentation](https://kubernetes.io/docs/setup/independent/install-kubeadm/) applies, nevertheless here is a convenience list of things to take care of:
1. Set the value of `/proc/sys/net/bridge/bridge-nf-call-iptables` to `1`. There may be different, distro-dependent ways to accomplish this in a persistent way, however most people will get away by editing _/etc/sysctl.conf_.
2. Load the `ip_vs` kernel module. Most people will want to create a file in _/etc/modprobe.de_ for this.
3. Disable swap. Make sure to edit _/etc/fstab_ to remove the swap mount from it.
4. If you want to use the EFK stack, you'll also have to define the following groups: _elasticsearch_hot_ (for hosts with fast hardware, more RAM on which the "hot" ES instances will be run, mutually exclusive with _elasticsearch_warm_), _elasticsearch_warm_ (for hosts with more disk space on which the "warm" ES instances will be run, mutually exclusive with _elasticsearch_hot_), _elasticsearch_ (all elasticsearch hosts). See the inventory _md-kubernetes.inventory_ for an example. The Elasticsearch data nodes require a `nofile` limit not lower than `65536` which is well above of the defaults on some systems. If using the JSON-based configuration file _/etc/docker/daemon.json_, you may have to add this: `"default-ulimits":{"nofile":{"Name":"nofile","Hard":65536,"Soft":65536}}`.

## Configuration

In order to use the ansible scripts, at least two files need to be configured:

1. Either edit _my-cluster.inventory_ or create your own. The inventory _must_ define the following groups: 
 _primary_master_ (a single machine on which _kubeadm_ will be run), _secondary_masters_ (the other masters), _masters_ (all masters), _minions_ (the worker nodes), _nodes_ (all nodes), _etcd_ (all machines on which etcd is installed, usually the masters).
2. Either edit _group_vars/my_cluster.yaml_ to your needs or create your own (named after the group defined in the inventory you want to use). Override settings from _group_vars/all.yaml_ where necessary. You may decide to change some of the defaults for your environment: `LOAD_BALANCING` (`kube-vip` or `nginx`), `NETWORK_PLUGIN` (`weavenet`, `flannel` or `calico`) and `ETCD_HOSTING` (`stacked` if running on the masters, else `external`).

## What the cluster setup does
1. Set up an _etcd_ cluster with self-signed certificates on all hosts in group _etcd._.
2. Set up a virtual IP and load balancing: either using a static pod for _kube-vip_ or a _keepalived_ cluster on all hosts in group _masters_.
3. Set up a master instance on the host in group _primary_master_ using _kubeadm._
4. Set up master instances on all hosts in group _secondary_masters_ by copying and patching (replace the primary master's host name and IP) the configuration created by _kubeadm_ and have them join the cluster.
5. Use _kubeadm_ to join all hosts in the group _minions_. 
6. Sets up a service account 'admin-user' and cluster role binding for the role 'cluster-admin' for remote access (if wanted).

## What the etcd-operator setup does

1. Install etcd-operator, so that applications can use it for creating their own _etcd_ clusters (Kubernetes is running on its own cluster running natively, not controlled by etcd-operator).

## What the prometheus-operator setup does

1. Install prometheus-operator, so that applications can use it for creating their own _prometheus_ instances, service monitors etc.

## What the additional playbooks can be used for:
- Add an NGINX-based load-balancer to the cluster. After this, the apiserver will be available through the virtual-IP on port 8443. Note that this is will interfere with _watch_ actions, like `kubectl log s -f` from a remote host (as a workaround you can still use port 6443 for remote a
ccess via `kubectl`, also see #4).
- Pre-fetch and transfer Kubernetes images. This is useful for systems without Internet access.

## What the images setup does

1. Pull all required images locally (hence you need to make sure to have docker installed on the host from which you run ansible).
2. Export the images to tar files.
3. Copy the tar files over to the target hosts.
4. Import the images from the tar files on the target hosts.

## Setting up the dashboard

The _cluster-dashboard.yaml_ playbook does the following:

1. Install the _dashboard_ and _metrics-server_ components.
2. Scale the number of instances to the number of master nodes.

For accessing the dashbord run `kubectl proxy` on your local host (which requires to have configured `kubectl` for your local host, see _Configuring local access_ below for automating this), then access via [http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)

The dashboard will ask you to authenticate. There are several options:

1. Use the token of an existing service account with sufficient privileges. On many clusters this command works for root-like access:

    ```
    kubectl -n kube-system describe secrets `kubectl -n kube-system get secrets | awk '/clusterrole-aggregation-controller/ {print $1}'` | awk '/token:/ {print $2}'
    ```

2. Use the token of the 'admin-user' service account (if it exists):

    ```
    kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
    ```

3. Use the _local-access.yaml_ playbook to generate a configuration file. That file can be copied to _~/.kube/config_ for local `kubectl` access. It can also be uploaded as _kubeconfig_ file in the dashboard's login dialogue.

## Setting up the EFK stack for centralised logging

1. Elasticsearch is installed as "hot/warm", i.e. all indices older than 3 days are moved from the "hot" to the "warm" instances automatically. It is assumed that the "hot" instances run on machines with faster hardware and probably less disk space. If `kubectl proxy` is running, the ES instance can be accessed through this URL: [http://localhost:8001/api/v1/namespaces/kube-system/services/elasticsearch-logging-client:9200/proxy/_search?q=*](http://localhost:8001/api/v1/namespaces/kube-system/services/elasticsearch-logging-client:9200/proxy/_search?q=*)

2. Kibana can be used for accessing the logs from Elasticsearch. If `kubectl proxy` is running it can be accessed through this URL: [http://localhost:8001/api/v1/namespaces/kube-system/services/kibana-logging:http/proxy/app/kibana#/](http://localhost:8001/api/v1/namespaces/kube-system/services/kibana-logging:http/proxy/app/kibana#/)

3. Fluentd collects the logs from the running pods. In order to normalise log files using different formats, you will most likely want to edit the the configmap fluentd uses (see the file _fluentd-es-configmap.yaml_ in _roles/fluentd/files_). A working, while not terribly efficient way to manage this is the use of the [rewrite_tag_filter](https://docs.fluentd.org/v1.0/articles/out_rewrite_tag_filter) as a multiplexer depending on the different log formats and then the [parser](https://docs.fluentd.org/v1.0/articles/parser-plugin-overview) filter with one section per (rewritten) tag for the actual parsing and normalising (for normalising different time/date formats, the [record_transformer](https://docs.fluentd.org/v1.0/articles/filter_record_transformer) filter can be used). 

## Configuring local access

Running the _local-access.yaml_ playbook creates a file _/tmp/<my-cluster-name>-admin.conf_ that can be used as _~/.kube/config_. If the dashboard has been installed (see above) the file will contain the 'admin-user' service account's token, so that for both `kubectl` and the dashboard root-like access is possible. If that service account does not exist, the client-side certificate will be used instead which is OK for testing environments but is generally considered not recommendable because the client-side certificates are not supposed to leave their master host.

## Upgrading a cluster

Here used to be a section about upgrading clusters. It will hopefully be back here in the near future. For now it is something that is being worked on.

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
