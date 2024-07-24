# kubeadm2ha - Automatic setup of HA clusters using kubeadm

This code largely follows the instructions published on [kubernetes.io](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/) and provides a convenient automation for setting up a highly-available Kubernetes cluster (i.e. with more than one master node) and the Dashboard. It also provides limited support for installing and running systems not connected to the internet.

# July 2024: removal of additional software

As of 2024 this repository no longer contains automatic installation support for additional software (like e.g. the EFK stack, etcd operator, ...) and focuses solely on the core: Kubernetes and the Dashboard.
Upholding support was no longer feasible because one after the other these components were abandoned by their respective developers.

## Overview

This repository contains a set of ansible scripts to do this. There are these playbooks:

1. _playbook-00-os-setup.yaml_ sets up the prerequisites for installing Kubernetes on Oracle Linux 7 nodes.
2. _playbook-01-cluster-setup.yaml_ sets up a complete cluster including the HA setup. See below for more details.
3. _playbook-51-cluster-uninstall.yaml_ removes data and configuration files to a point that _cluster-setup.yaml_ can be used again.
4. _playbook-02-dashboard.yaml_ sets up the dashboard including influxdb/grafana.
5. _playbook-03-local-access.yaml_ creates a patched _admin.conf_ file in _/tmp/<my-cluster-name>-admin.conf_. After copying it to _~/.kube/config_ remote _kubectl_ access via V-IP / load balancer can be tested. 
6. _playbook-00-cluster-images.yaml_ prefetches all images needed for Kubernetes operations and transfers them to the target hosts.
7. _playbook-52-uninstall-dashboard.yaml_ removes the dashboard.
8. _playbook-31-cluster-upgrade.yaml_ upgrades a cluster.
9. _playbook-zz-zz-configure-imageversions.yaml_ updates the image tag names in the file _vars/imageversions.yaml_.

Due to the frequent upgrades to both Kubernetes and _kubeadm_, these scripts cannot support all possible versions. For both, fresh installs and upgrades, please refer to the value of `KUBERNETES_VERSION` in _ansible/group_vars/all.yaml_ to find out which target version has been used for developing them. Other versions may work, too, but you may turn out to be the first to try this. Please refer to the following documents for compatibility information:
- [https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

## Prerequisites

Ansible version 2.4 or higher is required. Older versions will not work. 

## Prepare an environment for ansible

In order to use the ansible scripts, at least two files need to be configured:

1. Either edit _my-cluster.inventory_ or create your own. The inventory _must_ define the following groups: 
 _primary_master_ (a single machine on which _kubeadm_ will be run), _secondary_masters_ (the other masters), _masters_ (all masters), _minions_ (the worker nodes), _nodes_ (all nodes), _etcd_ (all machines on which etcd is installed, usually the masters).
2. Create a file named as the group defined in your inventory file in _group_vars_ overriding the defaults from _all.yaml_ where necessary. You may also decide to change some of the defaults for your environment: `LOAD_BALANCING` (`kube-vip`, `haproxy` or `nginx`), `NETWORK_PLUGIN` (`weavenet`, `flannel` or `calico`) and `ETCD_HOSTING` (`stacked` if running on the masters, else `external`).

## Prepare your hosts

On the target environment, some settings for successful installation of Kubernetes are necessary. The "Before you begin" section in the [official kubernetes documentation](https://kubernetes.io/docs/setup/independent/install-kubeadm/) applies, nevertheless here is a convenience list of things to take care of:
1. Set the value of `/proc/sys/net/bridge/bridge-nf-call-iptables` to `1`. There may be different, distro-dependent ways to accomplish this in a persistent way, however most people will get away by editing _/etc/sysctl.conf_.
2. Load the `ip_vs` kernel module. Most people will want to create a file in _/etc/modprobe.de_ for this.
3. Disable swap. Make sure to edit _/etc/fstab_ to remove the swap mount from it.
4. Make sure to have enough disk space on _/var/lib/docker_, ideally you should set up a dedicated partition and mount it, so that if downloaded docker images exceed the available space the operating system still works.
5. Make sure that the docker engine is installed. Other container engine implementations may work but have not been tested.
6. The primary master host requires passwordless `ssh` access to all other cluster hosts as `root`. After successful installation this can be removed if desired.
7. The primary master host needs to be able to resolve all other cluster host names as configured in the environments inventory files (see previous step), either via DNS or by entries in _/etc/hosts_.
8. Activate and start `containerd` and `docker`.

## What the cluster setup does
1. Set up an _etcd_ cluster with self-signed certificates on all hosts in group _etcd._.
2. Set up a virtual IP and load balancing: either using a static pod for _kube-vip_ or a _keepalived_ cluster with _nginx_ on all hosts in group _masters_.
3. Set up a master instance on the host in group _primary_master_ using _kubeadm._
4. Set up master instances on all hosts in group _secondary_masters_ by copying and patching (replace the primary master's host name and IP) the configuration created by _kubeadm_ and have them join the cluster.
5. Use _kubeadm_ to join all hosts in the group _minions_. 
6. Sets up a service account 'admin-user' and cluster role binding for the role 'cluster-admin' for remote access (if wanted).

Note that this step assumes that the Kubernetes software packages can be downloaded from some repository (like `yum` or `apt`). If your system has no connection to the internet you will need to set up a repository in your network and install the required packages beforehand.

## What the images setup does

1. Pull all required images locally (hence you need to make sure to have docker installed on the host from which you run ansible).
2. Export the images to tar files.
3. Copy the tar files over to the target hosts.
4. Import the images from the tar files on the target hosts.

## What the image tag update does

1. Detect the currently latest image tags with respect to the configured Kubernetes version
2. Overwrite the file _vars/imageversions.yaml_ with the latest image names and versions

Note that the image versions configured by this playbook will not necessarly work, as more recent versions may introduce incompatibilities, hence it they are merely a starting point and a helper for K8S updates.

## Setting up the dashboard

The _playbook-02-dashboard.yaml_ playbook does the following:

1. Install the _dashboard_ and _metrics-server_ components.
2. Scale the number of instances to the number of master nodes.

For accessing the dashbord run `kubectl proxy` on your local host (which requires to have configured `kubectl` for your local host, see _Configuring local access_ below for automating this), then access via [http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login)

The dashboard will ask you to authenticate. A user with admin privileges has been created during installation. In order to log in as this user, use this command to generate a token:

    kubectl -n kubernetes-dashboard create token admin-user

Copy the token from the console and use it for logging in to the dashboard.

3. Use the _playbook-03-local-access.yaml_ playbook to generate a configuration file. That file can be copied to _~/.kube/config_ for local `kubectl` access. It can also be uploaded as _kubeconfig_ file in the dashboard's login dialogue.

## Configuring local access

Running the _playbook-03-local-access.yaml_ playbook creates a file _/tmp/<my-cluster-name>-admin.conf_ that can be used as _~/.kube/config_. If the dashboard has been installed (see above) the file will contain the 'admin-user' service account's token, so that for both `kubectl` and the dashboard root-like access is possible. If that service account does not exist, the client-side certificate will be used instead which is OK for testing environments but is generally considered not recommendable because the client-side certificates are not supposed to leave their master host.

## Upgrading a cluster

**Note: this automatic upgrade will delete local pod storage. See below whether this is relevant for you or not:**
Pods may keep local data (e.g. the dashboard and its metrics components).
Whether such data needs to be preserved or not, depends on your application.
If the answer is yes, then don't use this here; upgrade manually instead.

For upgrading a cluster several steps are needed:

1. Find out which software versions to upgrade to.
2. Set the ansible variables to the new software versions.
3. Run the _playbook-00-cluster-images.yaml_ playbook if the cluster has no Internet access.
4. Run the _playbook-31-cluster-upgrade.yaml_ playbook.

**Note: Never upgrade a productive cluster without having tried it on a reference system before.**

### Preparation

First thing to do is find out to which version you want to upgrade. We only support systems where the version for all Kubernetes-related components (native packages, like _kubelet_, _kubectl_, _kubeadm_) and whatever they will run in containers when installed (API Server, Controller Manager, Scheduler, Kube Proxy) is the same. Hence, after having determined the version to upgrade to, update the variable `KUBERNETES_VERSION` either in _group_vars/all.yaml_ (global) or in _group_vars/<your-environment>.yaml_ (your environment only).

Next, you need to be able to upgrade the _kubelet_, _kubectl_, _kubeadm_ and - if upgraded, too - _kubernetes-cni_ on your cluster's machines using their package manager (_yum_, _apt_ or whatever). If you are connected to the internet, this is a no-brainer; the automatic upgrade will actually take care of this.

However in an isolated environment without internet access you will need to download these packages elsewhere and then make them available for your nodes, so that they can be installed using their package managers. This will most likely lead to creating local repos on the nodes or on a server in the same network and configure the package managers to use them. If your system is like that, again, the automatic upgrade will take care of upgradign the packages for you. I strongly recommend following this pattern, because the package upgrade needs to take place at a specific moment during upgrade which will effectively force you to perform the upgrade manually in the end.

Note that upgrading _etcd_ is only supported if it is installed on the master nodes (`ETCD_HOSTING` is `stacked`). Else you will have to upgrade _etcd_ manually which is beyond scope here.

Having configured this you may now want to fetch and install the new images for your to-be-upgraded cluster, if your cluster has no internet access.
If it has you may want to do this anyway to make the upgrade more seamless.

To do so, run the following command:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory playbook-00-cluster-images.yaml

I usually set the number of concurrent processes manually because if a cluster consists of more than 5 (default) nodes picking a higher value here significantly speeds up the process.

### Perform the upgrade

You may want to backup _/etc/kubernetes_ on all your master machines. Do this before running the upgrade.

The actual upgrade is automated. Run the following command:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory playbook-31-cluster-upgrade.yaml

See the comment above on setting the number of concurrent processes.

The upgrade is not fully free of disruptions:

- while _kubeadm_ applies the changes on a master, it restarts a number of services, hence they may be unavailable for a short time
- if containers running on the minions keep local data they have to take care to rebuild it when relocated to different minions during the upgrade process (i.e. local data is ignored)

If any of these is unacceptable, a fully automated upgrade process does not really make any sense because deep knowledge of the application running in a respective cluster is required to work around this.
Hence in that case a manual upgrade process is recommended.


### If something goes wrong

If the upgrade fails the situation afterwards depends on the phase in which things went wrong.

If _kubeadm_ failed to upgrade the cluster it will try to perform a rollback. Hence if that happened on the first master, chances are pretty good that the cluster is still intact. In that case all you need is to start _docker_, _kubelet_ and _keepalived_ on the secondary masters and then uncordon them (`kubectl uncordon <secondary-master-fqdn>`) to be back where you started from.

If _kubeadm_ on one of the secondary masters failed you still have a working, upgraded cluster, but without the secondary masters which may be in a somewhat undefined condition. In some cases _kubeadm_ fails if the cluster is still busy after having upgraded the previous master node, so that waiting a bit and running `kubeadm upgrade apply v<VERSION>` may even succeed. Otherwise you will have to find out what went wrong and join the secondaries manually. Once this has been done, finish the automatic upgrade process by processing the second half of the playbook only:

    ansible-playbook -f <good-number-of-concurrent-processes> -i <your-environment>.inventory playbook-31-cluster-upgrade.yaml --tags nodes

If upgrading the software packages (i.e. the second half of the playbook) failed, you still have a working cluster. You may try to fix the problems and continue manually. See the _.yaml_ files under _roles/upgrade-nodes/tasks_ for what you need to do.

If you are trying out the upgrade on a reference system, you may have to downgrade at some point to start again. See the sequence for reinstalling a cluster below for an instruction how to do this (hint: it is important to erase the some base software packages before setting up a new cluster based on a lower Kubernetes version).

## Examples

To run one of the playbooks (e.g. to set up a cluster), run ansible like this:

    ansible-playbook -i <your-inventory-file>.inventory playbook-01-cluster-setup.yaml

You might want to adapt the number of parallel processes to your number of hosts using the `-f' option.

A sane sequence of playbooks for a complete setup would be:

- playbook-00-cluster-images.yaml
- playbook-01-cluster-setup.yaml
- playbook-02-cluster-dashboard.yaml

The following playbooks can be used as needed:

- playbook-51-cluster-uninstall.yaml
- playbook-03-local-access.yaml
- playbook-52-uninstall-dashboard.yaml

Sequence for reinstalling a cluster:

    INVENTORY=<your-inventory-file> 
    NODES=<number-of-nodes>
    ansible-playbook -f $NODES -i $INVENTORY playbook-51-cluster-uninstall.yaml 
    # if you want to downgrade your kubelet, kubectl, ... packages you need to uninstall them first
    # if this is not the issue here, you can skip the following line
    ansible -u root -f $NODES -i $INVENTORY nodes -m command -a "rpm -e kubelet kubectl kubeadm kubernetes-cni"
    for i in playbook-01-cluster-setup.yaml playbook-02-cluster-dashboard.yaml; do 
        ansible-playbook -f $NODES -i $INVENTORY $i || break
        sleep 15s
    done

## Known limitations

This is a preview in order to obtain early feedback. It is not done yet. Known limitations are:

- The code has been tested almost exclusively in a Redhat-like (RHEL) environment. More testing on other distros is needed.
