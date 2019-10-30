# The `kube-kit` Project

`kube-kit` (get inspired from the project [kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way) ) is a pure-bash project to deploy a production-grade kubernetes cluster quickly and automatically.

You can use two or three commands of `kube-kit` to deploy a production-grade kubernetes cluster with HA, have fun!

## Environment Requirements

- CentOS7 latest version, minimal installed.
- Network already configurated correctly.
- Unused disks or partitions (optional).

> :book:&nbsp;&nbsp; `kube-kit` supports to configurate at most three different subnets for kubernetes, container and storage respectively.

## Configuration Files

All the configuration files can be found in the directory `etc`:
- `kube-kit.env`: contains most of the customized configurations.
- `cipher.ini`: the `root` password of all the target hosts.
- `disk.ini`: the unused disk or partition for `docker`, `kubelet`, `etcd` and `logs`.
- `heketi.ini`: the unused disks or partitions for distributed storage `glusterfs`.
- `limit.env`: the memory limit of some core services managed by systemd.
- `image.env`: the docker images name and tag (don't need to modify).
- `port.env`: the port of kubernetes components and addons (don't need to modify).
- `storage.env`: the pvc's size of some addon.
- `cmd.ini`: control the actions of `kube-kit` command itself.
- `env.prefix`: define the environment variables which can be accessed on remote hosts.
- `pkg.list`: the packages will be installed on the hosts.

## Kubernetes Infrastructures

There are three `CentOS-7.7.1908` hosts (with minimal installation), and each host has three network interfaces:
the first subnet will be used for core kubernetes components, the second for container communications and the third for distributed storage cluster communications.

| hostname | password | eth0 | eth1 | eth2 | k8s disk | glusterfs disks |
|:---|:---|:---|:---|:---|:---|:---|
| k8s-node1 | r00tnode1 | **192.168.10.11** | 192.168.20.11 | 192.168.30.11 | /dev/sdb | /dev/sdc |
| k8s-node2 | r00tnode2 | **192.168.10.12** | 192.168.20.12 | 192.168.30.12 | /dev/sdb | /dev/sdc, /dev/sdd |
| k8s-node3 | r00tnode3 | **192.168.10.13** | 192.168.20.13 | 192.168.30.13 | /dev/sdb | /dev/sdc, /dev/sdd, /dev/sde |

> :book:&nbsp;&nbsp; The gateways of the three subnets are: 192.168.10.2, 192.168.20.2 and 192.168.30.2

## Configurate `etc/cipher.ini`

> :warning:&nbsp;&nbsp; Only supports ipv4 address here! And all the ipv4 addresses **MUST** be in the **kubernetes subnet** (i.e. the ipv4 address of the interface `eth0`)

The modified `etc/cipher.ini`:

``` ini
[192.168.10.11]
r00tnode1
[192.168.10.12]
r00tnode2
[192.168.10.13]
r00tnode3
```

We use a special `ini` format to store the root password of an ipv4 group, which means if multiple hosts have the same root password, we can put them in an ipv4 group.

> :book:&nbsp;&nbsp; If the following hosts (`1.1.1.1`, `1.1.1.3`, `1.1.1.4`, `1.1.1.5`, `1.1.1.7`) have the same root password `r00tme`, then we can use an ipv4 group `[1.1.1.1,1.1.1.3-1.1.1.5,1.1.1.7]` to represent all the hosts:

``` ini
[1.1.1.1,1.1.1.3-1.1.1.5,1.1.1.7]
r00tme
```

> :book:&nbsp; The continuous ipv4 address means the 32-bit integers converted from the ipv4 address are continuous.

## Configurate `etc/disk.ini`

> :warning:&nbsp;&nbsp; Only supports ipv4 address here! And all the ipv4 addresses **MUST** be in the **kubernetes subnet** (i.e. the ipv4 address of the interface `eth0`)

The modified `etc/disk.ini`:

``` ini
[192.168.10.11-192.168.10.13]
/dev/sdb
```

Because all the hosts will use the disk `/dev/sdb` to store the data of `docker`, `kubelet`, `etcd` and `logs`, so we can use the ipv4 group `[192.168.10.11-192.168.10.13]` for all the hosts.

> :book:&nbsp;&nbsp; If the hosts don't have redundant disk for kubernetes, you can set `ENABLE_MASTER_STANDALONE_DEVICE` and `ENABLE_NODE_STANDALONE_DEVICE` (in `etc/kube-kit.env`) to `false`.

## Configurate `etc/heketi.ini`

> :warning:&nbsp;&nbsp; Only supports ipv4 address here! And all the ipv4 addresses **MUST** be in the **kubernetes subnet** (i.e. the ipv4 address of the interface `eth0`)

The modified `etc/heketi.ini`:

``` ini
[192.168.10.11]
/dev/sdc
[192.168.10.12]
/dev/sdc
/dev/sdd
[192.168.10.13]
/dev/sdc
/dev/sdd
/dev/sde
```

As we can see, if a host has multiple disks for glusterfs, just put multiple disks on multiple lines in an ipv4 group.

> :book:&nbsp;&nbsp; You can set `ENABLE_GLUSTERFS` to `false` if the hosts don't have redundant disks for glusterfs.

## Configurate `etc/kube-kit.ini`

> This document only introduces some **important** configurations.

### `KUBE_MASTER_VIP`

If you want to deploy multiple masters, you need to configurate an unused ipv4 address for `KUBE_MASTER_VIP`.

``` bash
KUBE_MASTER_VIP="192.168.10.10"
```

> :warning:&nbsp;&nbsp; This ipv4 address must be an **unused** address in the same subnet with kubernetes cluster!

### `KUBE_MASTER_IPS`

Set `KUBE_MASTER_IPS` to an ipv4 group of ipv4 addresses of the hosts (ipv4 address of `eth0`), whose role is `master`.

``` bash
KUBE_MASTER_IPS="192.168.10.11-192.168.10.13"
```

> The format of ipv4 group is `ip1,ip2-ip3,ip4`.

### `KUBE_NODE_IPS`

Set `KUBE_NODE_IPS` to an ipv4 group of ipv4 addresses of the hosts (ipv4 address of `eth0`), whose role is `node`.

``` bash
KUBE_NODE_IPS="192.168.10.11-192.168.10.13"
```

> The format of ipv4 group is `ip1,ip2-ip3,ip4`.

> :book:&nbsp;&nbsp; A host can have the role of both `master` and `node`.

### `KUBE_PODS_SUBNET`

``` bash
KUBE_PODS_SUBNET="172.17.0.0/16"
```

> :book:&nbsp;&nbsp; This subnet must be a private ipv4 cidr block, and will be used as the subnet of `pod`.

### `KUBE_SERVICES_SUBNET`

``` bash
KUBE_SERVICES_SUBNET="10.20.0.0/16"
```

> :book:&nbsp;&nbsp; This subnet must be a private ipv4 cidr block, and will be used as the subnet of kubernetes `service`.

> :warning:&nbsp; `KUBE_PODS_SUBNET` and `KUBE_SERVICES_SUBNET` can't contain any same ipv4 addresses!

### `KUBE_KUBERNETES_SVC_IP`

This ipv4 address will be used as `serviceIP` for the special auto-created service `kubernetes`. Then other pods can use the serviceName `kubernetes` (will be resolved to `${KUBE_KUBERNETES_SVC_IP}` by coredns) to access the kube-apiserver.

``` bash
KUBE_KUBERNETES_SVC_IP="10.20.0.1"
```

> :book:&nbsp;&nbsp; This ipv4 address should be the **first** ipv4 address of `KUBE_SERVICES_SUBNET`.

### `KUBE_DNS_SVC_IP`

``` bash
KUBE_DNS_SVC_IP="10.20.0.2"
```

This ipv4 address will be used as the address of `coredns`, and will be injected to the file `/etc/resolv.conf` of all the containers by kubelet, so pods can use the serviceName to access other pods' services (`coredns` will resolve the serviceName to its serviceIP).

``` txt
nameserver 10.20.0.2
search default.svc.k8s.cluster svc.k8s.cluster k8s.cluster
options ndots:5
```

> :book:&nbsp;&nbsp; This ipv4 address should be the **second** ipv4 address of `KUBE_SERVICES_SUBNET`.

### `ENABLE_CNI_PLUGIN`

If you want to use `CNI` plugin (only supports `calico` now) for cross-host communications between containers, set it to `true`, or `kube-kit` will deploy `flannel` if it's `false`.

#### `CALICO_NETWORK_GATEWAY`

> :warning:&nbsp;&nbsp; This variable works only when `ENABLE_CNI_PLUGIN` is `true`.

``` bash
ENABLE_CNI_PLUGIN="true"
CALICO_NETWORK_GATEWAY="192.168.20.2"
```

If you want to use a different subnet (e.g. `192.168.20.0/24` on `eth1`) for cross-host communications between containers, you need to set this variable to the **gateway** (e.g. `192.168.20.2`) of this different subnet! Or just leave it empty.

#### `FLANNEL_NETWORK_GATEWAY`

> :warning:&nbsp;&nbsp; This variable works only when `ENABLE_CNI_PLUGIN` is `false`.

``` bash
ENABLE_CNI_PLUGIN="false"
FLANNEL_NETWORK_GATEWAY="192.168.20.2"
```

If you want to use a different subnet (e.g. `192.168.20.0/24` on `eth1`) for cross-host communications between containers, you need to set this variable to the **gateway** (e.g. `192.168.20.2`) of this different subnet! Or just leave it empty.

### `ENABLE_GLUSTERFS`

If you want to use glusterfs as the distributed storage, set `ENABLE_GLUSTERFS` to `true`.

#### `GLUSTERFS_NETWORK_GATEWAY`

> :warning:&nbsp;&nbsp; This variable works only when `ENABLE_GLUSTERFS` is `true`.

``` bash
ENABLE_GLUSTERFS="true"
GLUSTERFS_NETWORK_GATEWAY="192.168.30.2"
```

If you want to use a different subnet (e.g. `192.168.30.0/24` on `eth2`) for distributed storage, you need to set this variable to the **gateway** (e.g. `192.168.30.2`) of this different subnet! Or just leave it empty.

### `ENABLE_LOCAL_YUM_REPO`

If you want to install the necessary packages from local rpms, set it to `true`, `kube-kit` will deploy a local yum repo.

> :warning:&nbsp;&nbsp; You need to download all the required rpm packages and their dependencies by executing the util script `util/prepare-rpm-files.sh` on a new-installed host.

> :book:&nbsp;&nbsp; Just set it to `false` if all the hosts can access the Internet.

#### `LOCAL_YUM_REPO_HOST`

> :warning:&nbsp;&nbsp; This variable works only when `ENABLE_LOCAL_YUM_REPO` is `true`.

``` bash
ENABLE_LOCAL_YUM_REPO="true"
LOCAL_YUM_REPO_HOST=""
```

You can choose one host from the kubernetes cluster as the local yum repo server, and leave it empty to use the first master by default.

### `ENABLE_LOCAL_NTP_SERVER`

If you want to use a local ntp server to sync time of all the hosts, set it to `true`.

> :book:&nbsp;&nbsp; Just set it to `false` if all the hosts can access the Internet.

#### `LOCAL_NTP_SERVER`

> :warning:&nbsp;&nbsp; This variable works only when `ENABLE_LOCAL_NTP_SERVER` is `true`.

``` bash
ENABLE_LOCAL_NTP_SERVER="true"
LOCAL_NTP_SERVER=""
```

You can choose one host from the kubernetes cluster as the ntp server, and leave it empty to use the first master by default.

## Install Kubernetes

`kube-kit` now has five subcommand:

- `check`: check if all the basic requirements are satisfied.
- `init`: init the basic environments defore startup kubernetes cluster.
- `deploy`: deploy kubernetes components, dependency services and addons.
- `clean`: clean the kubernetes cluster and dependency services (TODO).
- `update`: add new kubernetes/heketi nodes, update kubernetes version (TODO).

> :book:&nbsp;&nbsp; Execute `./kube-kit -h` to get the help messages:

<details><summary>:eyes: click me to show/hide long messages :eyes:</summary><p>

``` text
Usage: `kube-kit <Subcommand> <Subcommand-Option> [Options]`

Options (can be anywhere):
    -n|--no-records      Do not record the successful message of current subcommand

Subcommand:
    check                Check if all the basic requirements are satisfied
    init                 Init the basic environments defore startup kubernetes cluster
    deploy               Deploy kubernetes components, dependency services and addons
    clean                Clean the kubernetes cluster and dependency services
    update               Add new kubernetes/heketi nodes, update kubernetes version

Options for 'check':
    env                  Check if basic environment requirements are satisfied

Options for 'init':
    localrepo            Create a local yum mirror in current machine
    hostname             Reset hostnames & hosts files on all machines
    auto-ssh             Config the certifications to allow ssh into each other
    ntp                  Set crontab to sync time from local or remote ntpd server
    disk                 Auto-partition a standalone disk into LVs to store data separately
    glusterfs            Initialize the glusterfs cluster for kubernetes cluster
    env                  Config the basic environments on all machines
    cert                 Generate the certifications for all components in the cluster
    all                  Initialize all the basic environments for kubernetes cluster

Options for 'deploy':
    etcd                 Deploy the Etcd secure cluster for kube-apiserver, flannel and calico
    flannel              Deploy the Flanneld on all nodes
    docker               Deploy the Dockerd on all machines
    proxy                Deploy the Reverse-proxy for all the exposed services
    master               Deploy the Kubernetes master components
    node                 Deploy the Kubernetes node components
    crontab              Deploy the Crontab jobs on all hosts
    calico               Deploy the CNI plugin(calico) for kubernetes cluster
    coredns              Deploy the CoreDNS addon for kubernetes cluster
    heketi               Deploy the Heketi service to manage glusterfs cluster automatically
    harbor               Deploy the Harbor docker private image repertory
    ingress              Deploy the Nginx ingress controller addon for kubernetes cluster
    all                  Deploy all the components for kubernetes cluster

Options for 'clean':
    master               Clean the kubernetes masters
    node                 Clean the kubernetes nodes
    all                  Clean all the components listed above

Options for 'update':
    cluster              Update all the components of kubernetes
    node                 Add some NEW nodes into kubernetes cluster
    heketi               Add some NEW nodes or NEW devices into heketi cluster
```

</p></details>

### Subcommand `check`

``` bash
$ ./kube-kit check env
```

<details><summary>:eyes: click me to show/hide long messages :eyes:</summary><p>

``` text
2019-10-30 22:04:17 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:04:34 [TITLE] Starting to execute the command `kube-kit check env` ...
2019-10-30 22:04:34 [INFO] Checking if the basic requirements are satisfied ...
2019-10-30 22:04:34 [INFO] Checking if current host can ping all hosts ...
2019-10-30 22:04:34 [INFO] Checking if the root password of all hosts are correct ...
2019-10-30 22:04:35 [INFO] Checking if the container/storage networks are correct ...
[192.168.10.11] 2019-10-30 22:04:36 [DEBUG] Checking if the host 192.168.10.11 can ping the gateway 192.168.20.2 of flannel subnet ...
[192.168.10.13] 2019-10-30 22:04:35 [DEBUG] Checking if the host 192.168.10.13 can ping the gateway 192.168.20.2 of flannel subnet ...
[192.168.10.12] 2019-10-30 22:04:34 [DEBUG] Checking if the host 192.168.10.12 can ping the gateway 192.168.20.2 of flannel subnet ...
[192.168.10.11] 2019-10-30 22:04:36 [DEBUG] Checking if the host 192.168.10.11 can ping the gateway 192.168.30.2 of glusterfs subnet ...
[192.168.10.12] 2019-10-30 22:04:35 [DEBUG] Checking if the host 192.168.10.12 can ping the gateway 192.168.30.2 of glusterfs subnet ...
[192.168.10.11] 2019-10-30 22:04:36 [DEBUG] Checking if the host 192.168.10.11 can ping the gateway 192.168.20.2 of calico subnet ...
[192.168.10.12] 2019-10-30 22:04:35 [DEBUG] Checking if the host 192.168.10.12 can ping the gateway 192.168.20.2 of calico subnet ...
[192.168.10.13] 2019-10-30 22:04:35 [DEBUG] Checking if the host 192.168.10.13 can ping the gateway 192.168.30.2 of glusterfs subnet ...
[192.168.10.13] 2019-10-30 22:04:35 [DEBUG] Checking if the host 192.168.10.13 can ping the gateway 192.168.20.2 of calico subnet ...
2019-10-30 22:04:37 [INFO] Checking if the standalone device on all hosts exists ...
2019-10-30 22:04:41 [INFO] Checking if all the disks for heketi for glusterfs cluster exist ...
[192.168.10.12] 2019-10-30 22:04:40 [DEBUG] Checking the device /dev/sdc for heketi on 192.168.10.12 ...
[192.168.10.11] 2019-10-30 22:04:42 [DEBUG] Checking the device /dev/sdc for heketi on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:04:40 [DEBUG] Checking the device /dev/sdc for heketi on 192.168.10.13 ...
[192.168.10.13] 2019-10-30 22:04:41 [DEBUG] Checking the device /dev/sdd for heketi on 192.168.10.13 ...
[192.168.10.12] 2019-10-30 22:04:41 [DEBUG] Checking the device /dev/sdd for heketi on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:04:42 [DEBUG] Checking the device /dev/sde for heketi on 192.168.10.13 ...
2019-10-30 22:04:43 [INFO] Checking if the distro release of all hosts are CentOS-7.7.1908 ...
[192.168.10.12] 2019-10-30 22:04:43 [DEBUG] The distro of 192.168.10.12 is <CentOS Linux 7 (Core)>; and release version is <7.7.1908>; and kernel version is <3.10.0-1062.el7.x86_64>
[192.168.10.13] 2019-10-30 22:04:43 [DEBUG] The distro of 192.168.10.13 is <CentOS Linux 7 (Core)>; and release version is <7.7.1908>; and kernel version is <3.10.0-1062.el7.x86_64>
[192.168.10.11] 2019-10-30 22:04:44 [DEBUG] The distro of 192.168.10.11 is <CentOS Linux 7 (Core)>; and release version is <7.7.1908>; and kernel version is <3.10.0-1062.el7.x86_64>
2019-10-30 22:04:44 [INFO] Checking if all the hosts can install the required packages ...
2019-10-30 22:04:44 [DEBUG] Backing up the configuration files of origin yum repos on all hosts ...
2019-10-30 22:04:50 [INFO] Simulating the operation of 'kube-kit init localrepo' ...
[192.168.10.11] 2019-10-30 22:05:32 [DEBUG] Simulating to install all the required packages on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:05:30 [DEBUG] Simulating to install all the required packages on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:05:31 [DEBUG] Simulating to install all the required packages on 192.168.10.13 ...
2019-10-30 22:06:05 [INFO] Cleaning up local yum repos on 192.168.10.11 ...
2019-10-30 22:06:08 [INFO] Recovering the configuration files of origin yum repos on all hosts ...
2019-10-30 22:06:09 [INFO] [kube-kit check env] completed successfully!
2019-10-30 22:06:09 [INFO] [kube-kit check env] used total time: 1m52s
```

</p></details>

### Subcommand `init`

``` bash
$ ./kube-kit init all
```

<details><summary>:eyes: click me to show/hide long messages :eyes:</summary><p>

``` text
2019-10-30 22:06:49 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:06:55 [TITLE] Starting to execute the command `kube-kit init all` ...
2019-10-30 22:06:55 [INFO] Initializing all the basic environments for kubernetes cluster ...
2019-10-30 22:06:55 [INFO] `kube-kit init all` will start from <localrepo>, because all the options before <localrepo> have been executed successfully!
2019-10-30 22:06:57 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:07:03 [TITLE] Starting to execute the command `kube-kit init localrepo` ...
2019-10-30 22:07:03 [INFO] Creating a local yum mirror on 192.168.10.11 ...
2019-10-30 22:07:04 [INFO] Copying all the offline rpms to 192.168.10.11 ...
2019-10-30 22:07:08 [INFO] Creating the local yum repo on 192.168.10.11 ...
[192.168.10.11] 2019-10-30 22:07:09 [DEBUG] Installing httpd from local rpms on 192.168.10.11 ...
[192.168.10.11] 2019-10-30 22:07:32 [DEBUG] Creating local repos using 'createrepo' command on 192.168.10.11 ...
2019-10-30 22:07:33 [INFO] Configurating to use the local yum repo on all the hosts ...
[192.168.10.13] 2019-10-30 22:07:32 [INFO] Configurating to use local yum repo on 192.168.10.13 ...
[192.168.10.12] 2019-10-30 22:07:32 [INFO] Configurating to use local yum repo on 192.168.10.12 ...
[192.168.10.11] 2019-10-30 22:07:33 [INFO] Configurating to use local yum repo on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:07:32 [DEBUG] Generating local yum repo file on 192.168.10.13 ...
[192.168.10.11] 2019-10-30 22:07:34 [DEBUG] Generating local yum repo file on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:07:32 [DEBUG] Generating local yum repo file on 192.168.10.12 ...
2019-10-30 22:07:34 [INFO] [kube-kit init localrepo] completed successfully!
2019-10-30 22:07:34 [INFO] [kube-kit init localrepo] used total time: 37.4s
2019-10-30 22:07:36 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:07:42 [TITLE] Starting to execute the command `kube-kit init hostname` ...
2019-10-30 22:07:42 [INFO] Resetting hostname & /etc/hosts on all the hosts ...
2019-10-30 22:07:48 [INFO] [kube-kit init hostname] completed successfully!
2019-10-30 22:07:48 [INFO] [kube-kit init hostname] used total time: 11.7s
2019-10-30 22:07:49 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:07:56 [TITLE] Starting to execute the command `kube-kit init auto-ssh` ...
2019-10-30 22:07:56 [INFO] Configurating the certifications to allow ssh into each other ...
[192.168.10.11] 2019-10-30 22:07:56 [DEBUG] Generating new ssh credentials on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:07:57 [DEBUG] Generating new ssh credentials on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:07:57 [DEBUG] Generating new ssh credentials on 192.168.10.13 ...
[192.168.10.11] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.11 from 192.168.10.11 is authenticated!
[192.168.10.11] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.12 from 192.168.10.11 is authenticated!
[192.168.10.11] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.13 from 192.168.10.11 is authenticated!
[192.168.10.12] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.13 from 192.168.10.12 is authenticated!
[192.168.10.12] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.11 from 192.168.10.12 is authenticated!
[192.168.10.12] 2019-10-30 22:08:01 [DEBUG] Accessing to 192.168.10.12 from 192.168.10.12 is authenticated!
[192.168.10.13] 2019-10-30 22:08:02 [DEBUG] Accessing to 192.168.10.13 from 192.168.10.13 is authenticated!
[192.168.10.13] 2019-10-30 22:08:02 [DEBUG] Accessing to 192.168.10.12 from 192.168.10.13 is authenticated!
[192.168.10.13] 2019-10-30 22:08:02 [DEBUG] Accessing to 192.168.10.11 from 192.168.10.13 is authenticated!
2019-10-30 22:08:04 [INFO] [kube-kit init auto-ssh] completed successfully!
2019-10-30 22:08:04 [INFO] [kube-kit init auto-ssh] used total time: 14.2s
2019-10-30 22:08:06 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:08:11 [TITLE] Starting to execute the command `kube-kit init ntp` ...
2019-10-30 22:08:11 [INFO] Setting crontab to sync time from local or remote ntpd server ...
2019-10-30 22:08:11 [DEBUG] Deploying local ntp server on 192.168.10.11 now ...
2019-10-30 22:08:14 [DEBUG] Configurating cronjob to update time automatically on 192.168.10.13 ...
2019-10-30 22:08:14 [DEBUG] Configurating cronjob to update time automatically on 192.168.10.12 ...
2019-10-30 22:08:25 [INFO] [kube-kit init ntp] completed successfully!
2019-10-30 22:08:25 [INFO] [kube-kit init ntp] used total time: 19.3s
2019-10-30 22:08:27 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:08:32 [TITLE] Starting to execute the command `kube-kit init disk` ...
2019-10-30 22:08:32 [INFO] Auto-partition a standalone disk into LVs to store data separately ...
2019-10-30 22:08:32 [DEBUG] Hosts will be partitioned as master-node: 192.168.10.11 192.168.10.12 192.168.10.13
2019-10-30 22:08:33 [INFO] The preview of all the LVs' mount infos on selected MASTER-NODE:
File-System             Mount-Point         Type Capacity(percent%)
/dev/mapper/k8s-docker  /var/lib/docker     xfs  52.5%
/dev/mapper/k8s-etcd    /var/lib/etcd       xfs  7.5%
/dev/mapper/k8s-logs    /var/log/kubernetes xfs  7.5%
/dev/mapper/k8s-kubelet /var/lib/kubelet    xfs  29.25%
[192.168.10.11] 2019-10-30 22:08:35 [WARN] Trying to wipe the device /dev/sdb on 192.168.10.11 now ...
[192.168.10.11] 2019-10-30 22:08:35 [TITLE] Auto-paratition the device /dev/sdb on 192.168.10.11 now ...
[192.168.10.11] 2019-10-30 22:08:35 [INFO] Creating a new pv /dev/sdb using device /dev/sdb ...
  Physical volume "/dev/sdb" successfully created.
[192.168.10.11] 2019-10-30 22:08:37 [INFO] Creating a new vg k8s using pv /dev/sdb ...
  Volume group "k8s" successfully created
[192.168.10.11] 2019-10-30 22:08:39 [INFO] Creating a new lv docker with the size 26.25G ...
  Logical volume "docker" created.
[192.168.10.11] 2019-10-30 22:08:40 [INFO] Making the xfs filesystem for the lv docker ...
meta-data=/dev/k8s/docker        isize=512    agcount=4, agsize=1720320 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=6881280, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=3360, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.11] 2019-10-30 22:08:43 [INFO] The mount information for /dev/mapper/k8s-docker:
/dev/mapper/k8s-docker /var/lib/docker xfs pquota,uquota 0 0
[192.168.10.11] 2019-10-30 22:08:43 [INFO] Creating a new lv etcd with the size 3.75G ...
  Logical volume "etcd" created.
[192.168.10.11] 2019-10-30 22:08:45 [INFO] Making the xfs filesystem for the lv etcd ...
meta-data=/dev/k8s/etcd          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.11] 2019-10-30 22:08:46 [INFO] The mount information for /dev/mapper/k8s-etcd:
/dev/mapper/k8s-etcd /var/lib/etcd xfs pquota,uquota 0 0
[192.168.10.11] 2019-10-30 22:08:47 [INFO] Creating a new lv logs with the size 3.75G ...
  Logical volume "logs" created.
[192.168.10.11] 2019-10-30 22:08:48 [INFO] Making the xfs filesystem for the lv logs ...
meta-data=/dev/k8s/logs          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.11] 2019-10-30 22:08:49 [INFO] The mount information for /dev/mapper/k8s-logs:
/dev/mapper/k8s-logs /var/log/kubernetes xfs pquota,uquota 0 0
[192.168.10.11] 2019-10-30 22:08:49 [INFO] Creating a new lv kubelet with the size 14.625G ...
  Logical volume "kubelet" created.
[192.168.10.11] 2019-10-30 22:08:51 [INFO] Making the xfs filesystem for the lv kubelet ...
meta-data=/dev/k8s/kubelet       isize=512    agcount=4, agsize=958464 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=3833856, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.11] 2019-10-30 22:08:53 [INFO] The mount information for /dev/mapper/k8s-kubelet:
/dev/mapper/k8s-kubelet /var/lib/kubelet xfs pquota,uquota 0 0
[192.168.10.12] 2019-10-30 22:08:55 [WARN] Trying to wipe the device /dev/sdb on 192.168.10.12 now ...
[192.168.10.12] 2019-10-30 22:08:55 [TITLE] Auto-paratition the device /dev/sdb on 192.168.10.12 now ...
[192.168.10.12] 2019-10-30 22:08:55 [INFO] Creating a new pv /dev/sdb using device /dev/sdb ...
  Physical volume "/dev/sdb" successfully created.
[192.168.10.12] 2019-10-30 22:08:57 [INFO] Creating a new vg k8s using pv /dev/sdb ...
  Volume group "k8s" successfully created
[192.168.10.12] 2019-10-30 22:08:59 [INFO] Creating a new lv docker with the size 26.25G ...
  Logical volume "docker" created.
[192.168.10.12] 2019-10-30 22:09:01 [INFO] Making the xfs filesystem for the lv docker ...
meta-data=/dev/k8s/docker        isize=512    agcount=4, agsize=1720320 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=6881280, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=3360, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.12] 2019-10-30 22:09:03 [INFO] The mount information for /dev/mapper/k8s-docker:
/dev/mapper/k8s-docker /var/lib/docker xfs pquota,uquota 0 0
[192.168.10.12] 2019-10-30 22:09:03 [INFO] Creating a new lv etcd with the size 3.75G ...
  Logical volume "etcd" created.
[192.168.10.12] 2019-10-30 22:09:04 [INFO] Making the xfs filesystem for the lv etcd ...
meta-data=/dev/k8s/etcd          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.12] 2019-10-30 22:09:06 [INFO] The mount information for /dev/mapper/k8s-etcd:
/dev/mapper/k8s-etcd /var/lib/etcd xfs pquota,uquota 0 0
[192.168.10.12] 2019-10-30 22:09:06 [INFO] Creating a new lv logs with the size 3.75G ...
  Logical volume "logs" created.
[192.168.10.12] 2019-10-30 22:09:08 [INFO] Making the xfs filesystem for the lv logs ...
meta-data=/dev/k8s/logs          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.12] 2019-10-30 22:09:10 [INFO] The mount information for /dev/mapper/k8s-logs:
/dev/mapper/k8s-logs /var/log/kubernetes xfs pquota,uquota 0 0
[192.168.10.12] 2019-10-30 22:09:10 [INFO] Creating a new lv kubelet with the size 14.625G ...
  Logical volume "kubelet" created.
[192.168.10.12] 2019-10-30 22:09:12 [INFO] Making the xfs filesystem for the lv kubelet ...
meta-data=/dev/k8s/kubelet       isize=512    agcount=4, agsize=958464 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=3833856, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.12] 2019-10-30 22:09:14 [INFO] The mount information for /dev/mapper/k8s-kubelet:
/dev/mapper/k8s-kubelet /var/lib/kubelet xfs pquota,uquota 0 0
[192.168.10.13] 2019-10-30 22:09:16 [WARN] Trying to wipe the device /dev/sdb on 192.168.10.13 now ...
[192.168.10.13] 2019-10-30 22:09:17 [TITLE] Auto-paratition the device /dev/sdb on 192.168.10.13 now ...
[192.168.10.13] 2019-10-30 22:09:17 [INFO] Creating a new pv /dev/sdb using device /dev/sdb ...
  Physical volume "/dev/sdb" successfully created.
[192.168.10.13] 2019-10-30 22:09:19 [INFO] Creating a new vg k8s using pv /dev/sdb ...
  Volume group "k8s" successfully created
[192.168.10.13] 2019-10-30 22:09:21 [INFO] Creating a new lv docker with the size 26.25G ...
  Logical volume "docker" created.
[192.168.10.13] 2019-10-30 22:09:22 [INFO] Making the xfs filesystem for the lv docker ...
meta-data=/dev/k8s/docker        isize=512    agcount=4, agsize=1720320 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=6881280, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=3360, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.13] 2019-10-30 22:09:24 [INFO] The mount information for /dev/mapper/k8s-docker:
/dev/mapper/k8s-docker /var/lib/docker xfs pquota,uquota 0 0
[192.168.10.13] 2019-10-30 22:09:24 [INFO] Creating a new lv etcd with the size 3.75G ...
  Logical volume "etcd" created.
[192.168.10.13] 2019-10-30 22:09:26 [INFO] Making the xfs filesystem for the lv etcd ...
meta-data=/dev/k8s/etcd          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.13] 2019-10-30 22:09:28 [INFO] The mount information for /dev/mapper/k8s-etcd:
/dev/mapper/k8s-etcd /var/lib/etcd xfs pquota,uquota 0 0
[192.168.10.13] 2019-10-30 22:09:28 [INFO] Creating a new lv logs with the size 3.75G ...
  Logical volume "logs" created.
[192.168.10.13] 2019-10-30 22:09:30 [INFO] Making the xfs filesystem for the lv logs ...
meta-data=/dev/k8s/logs          isize=512    agcount=4, agsize=245760 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=983040, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.13] 2019-10-30 22:09:32 [INFO] The mount information for /dev/mapper/k8s-logs:
/dev/mapper/k8s-logs /var/log/kubernetes xfs pquota,uquota 0 0
[192.168.10.13] 2019-10-30 22:09:32 [INFO] Creating a new lv kubelet with the size 14.625G ...
  Logical volume "kubelet" created.
[192.168.10.13] 2019-10-30 22:09:33 [INFO] Making the xfs filesystem for the lv kubelet ...
meta-data=/dev/k8s/kubelet       isize=512    agcount=4, agsize=958464 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=3833856, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[192.168.10.13] 2019-10-30 22:09:35 [INFO] The mount information for /dev/mapper/k8s-kubelet:
/dev/mapper/k8s-kubelet /var/lib/kubelet xfs pquota,uquota 0 0
2019-10-30 22:09:35 [INFO] [kube-kit init disk] completed successfully!
2019-10-30 22:09:35 [INFO] [kube-kit init disk] used total time: 1m8s
2019-10-30 22:09:36 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:09:42 [TITLE] Starting to execute the command `kube-kit init glusterfs` ...
2019-10-30 22:09:42 [INFO] Initializing the glusterfs cluster for kubernetes cluster ...
[192.168.10.13] 2019-10-30 22:09:43 [DEBUG] Installing glusterfs on 192.168.10.13 ...
[192.168.10.11] 2019-10-30 22:09:43 [DEBUG] Installing glusterfs on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:09:43 [DEBUG] Installing glusterfs on 192.168.10.12 ...
[192.168.10.11] 2019-10-30 22:09:46 [DEBUG] Installing glusterfs-server on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:09:48 [DEBUG] Installing glusterfs-server on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:09:48 [DEBUG] Installing glusterfs-server on 192.168.10.13 ...
[192.168.10.11] 2019-10-30 22:10:00 [DEBUG] Adding glusterfs-node1 into glusterfs cluster ...
[192.168.10.11] 2019-10-30 22:10:01 [DEBUG] Adding glusterfs-node2 into glusterfs cluster ...
[192.168.10.11] 2019-10-30 22:10:03 [DEBUG] Adding glusterfs-node3 into glusterfs cluster ...
[192.168.10.11] 2019-10-30 22:10:05 [INFO] Creating the shared volume shared-volume ...
volume create: shared-volume: success: please start the volume to access data
[192.168.10.11] 2019-10-30 22:10:05 [INFO] Starting the shared volume shared-volume ...
volume start: shared-volume: success
[192.168.10.11] 2019-10-30 22:10:08 [INFO] Setting the capacity of shared-volume to 10GB ...
volume quota : success
volume quota : success
2019-10-30 22:10:10 [INFO] [kube-kit init glusterfs] completed successfully!
2019-10-30 22:10:10 [INFO] [kube-kit init glusterfs] used total time: 33.4s
2019-10-30 22:10:11 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:10:17 [TITLE] Starting to execute the command `kube-kit init env` ...
2019-10-30 22:10:17 [INFO] Configurating the basic environments on all machines ...
2019-10-30 22:10:17 [DEBUG] Kubernetes-v1.15.5 binary files existed already! Do nothing ...
2019-10-30 22:10:17 [INFO] Uncompressing kubernetes-v1.15.5 binary files ...
kubernetes/server/bin/kubelet
kubernetes/server/bin/kube-scheduler
kubernetes/server/bin/kube-proxy
kubernetes/server/bin/kubectl
kubernetes/server/bin/kube-apiserver
kubernetes/server/bin/kube-controller-manager
2019-10-30 22:10:27 [INFO] Copying kubernetes-v1.15.5 binary files to all Masters ...
2019-10-30 22:11:04 [INFO] Copying kubernetes-v1.15.5 binary files to all Nodes ...
[192.168.10.11] 2019-10-30 22:11:16 [DEBUG] Setting some necessary kernel configurations on 192.168.10.11 ...
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.neigh.default.gc_thresh1 = 70000
net.ipv4.neigh.default.gc_thresh2 = 80000
net.ipv4.neigh.default.gc_thresh3 = 90000
fs.file-max = 65535
vm.max_map_count = 262144
vm.swappiness = 0
[192.168.10.11] 2019-10-30 22:11:16 [DEBUG] Setting kernel configurations for nginx on 192.168.10.11 ...
sysctl: setting key "net.core.somaxconn": Invalid argument
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
[192.168.10.11] 2019-10-30 22:11:17 [DEBUG] Installing some useful packages on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:11:17 [DEBUG] Setting some necessary kernel configurations on 192.168.10.13 ...
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.neigh.default.gc_thresh1 = 70000
net.ipv4.neigh.default.gc_thresh2 = 80000
net.ipv4.neigh.default.gc_thresh3 = 90000
fs.file-max = 65535
vm.max_map_count = 262144
vm.swappiness = 0
[192.168.10.12] 2019-10-30 22:11:17 [DEBUG] Setting some necessary kernel configurations on 192.168.10.12 ...
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.neigh.default.gc_thresh1 = 70000
net.ipv4.neigh.default.gc_thresh2 = 80000
net.ipv4.neigh.default.gc_thresh3 = 90000
fs.file-max = 65535
vm.max_map_count = 262144
vm.swappiness = 0
sysctl: setting key "net.core.somaxconn": Invalid argument
[192.168.10.13] 2019-10-30 22:11:17 [DEBUG] Setting kernel configurations for nginx on 192.168.10.13 ...
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
[192.168.10.12] 2019-10-30 22:11:17 [DEBUG] Setting kernel configurations for nginx on 192.168.10.12 ...
sysctl: setting key "net.core.somaxconn": Invalid argument
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
[192.168.10.12] 2019-10-30 22:11:17 [DEBUG] Installing some useful packages on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:11:18 [DEBUG] Installing some useful packages on 192.168.10.13 ...
2019-10-30 22:11:47 [INFO] Copying cni-v0.8.2 and calico cni-plugin-v3.9.1 binary files to all Nodes ...
2019-10-30 22:11:58 [INFO] [kube-kit init env] completed successfully!
2019-10-30 22:11:58 [INFO] [kube-kit init env] used total time: 1m47s
2019-10-30 22:11:59 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:12:05 [TITLE] Starting to execute the command `kube-kit init cert` ...
2019-10-30 22:12:05 [INFO] Generating the certifications for all components in the cluster ...
2019-10-30 22:12:05 [TITLE] Generating certification files using cfssl tools ...
2019-10-30 22:12:10 [INFO] Generating the certificate and private key file for CA ...
2019/10/30 22:12:10 [INFO] generating a new CA key and certificate from CSR
2019/10/30 22:12:10 [INFO] generate received request
2019/10/30 22:12:10 [INFO] received CSR
2019/10/30 22:12:10 [INFO] generating key: rsa-4096
2019/10/30 22:12:11 [INFO] encoded CSR
2019/10/30 22:12:11 [INFO] signed certificate with serial number 455927868872275630105837191114948444235397461133
2019-10-30 22:12:11 [INFO] Generating the client certificate and private key file for etcd ...
2019/10/30 22:12:11 [INFO] generate received request
2019/10/30 22:12:11 [INFO] received CSR
2019/10/30 22:12:11 [INFO] generating key: rsa-4096
2019/10/30 22:12:14 [INFO] encoded CSR
2019/10/30 22:12:14 [INFO] signed certificate with serial number 562308641015034668877314983507901199064723393872
2019-10-30 22:12:14 [INFO] Generating the client certificate and private key file for docker ...
2019/10/30 22:12:14 [INFO] generate received request
2019/10/30 22:12:14 [INFO] received CSR
2019/10/30 22:12:14 [INFO] generating key: rsa-4096
2019/10/30 22:12:14 [INFO] encoded CSR
2019/10/30 22:12:14 [INFO] signed certificate with serial number 303726461614912743630233660836047809090920395815
2019-10-30 22:12:15 [INFO] Generating the client certificate and private key file for kube-apiserver ...
2019/10/30 22:12:15 [INFO] generate received request
2019/10/30 22:12:15 [INFO] received CSR
2019/10/30 22:12:15 [INFO] generating key: rsa-4096
2019/10/30 22:12:16 [INFO] encoded CSR
2019/10/30 22:12:16 [INFO] signed certificate with serial number 25668525702733197176770537094440750327475468513
2019-10-30 22:12:16 [INFO] Generating the client certificate and private key file for kube-controller-manager ...
2019/10/30 22:12:16 [INFO] generate received request
2019/10/30 22:12:16 [INFO] received CSR
2019/10/30 22:12:16 [INFO] generating key: rsa-4096
2019/10/30 22:12:18 [INFO] encoded CSR
2019/10/30 22:12:18 [INFO] signed certificate with serial number 711098801296158750950808695272861101926411584632
2019-10-30 22:12:18 [INFO] Generating the client certificate and private key file for kube-scheduler ...
2019/10/30 22:12:18 [INFO] generate received request
2019/10/30 22:12:18 [INFO] received CSR
2019/10/30 22:12:18 [INFO] generating key: rsa-4096
2019/10/30 22:12:20 [INFO] encoded CSR
2019/10/30 22:12:20 [INFO] signed certificate with serial number 46130561363251987957596525789934049357095070339
2019-10-30 22:12:20 [INFO] Generating the client certificate and private key file for kube-proxy ...
2019/10/30 22:12:20 [INFO] generate received request
2019/10/30 22:12:20 [INFO] received CSR
2019/10/30 22:12:20 [INFO] generating key: rsa-4096
2019/10/30 22:12:21 [INFO] encoded CSR
2019/10/30 22:12:21 [INFO] signed certificate with serial number 200338165050456332134962128191655710817955675049
2019-10-30 22:12:21 [INFO] Generating the client certificate and private key file for admin ...
2019/10/30 22:12:21 [INFO] generate received request
2019/10/30 22:12:21 [INFO] received CSR
2019/10/30 22:12:21 [INFO] generating key: rsa-4096
2019/10/30 22:12:23 [INFO] encoded CSR
2019/10/30 22:12:23 [INFO] signed certificate with serial number 720555416927829891223402816450061840072467657345
2019-10-30 22:12:23 [INFO] Generating the client certificate and private key file for service-account ...
2019/10/30 22:12:23 [INFO] generate received request
2019/10/30 22:12:23 [INFO] received CSR
2019/10/30 22:12:23 [INFO] generating key: rsa-4096
2019/10/30 22:12:27 [INFO] encoded CSR
2019/10/30 22:12:27 [INFO] signed certificate with serial number 364484248271787447097120969032147941340964391149
2019-10-30 22:12:27 [INFO] Distributing all the TLS certificates to all machines ...
[192.168.10.11] 2019-10-30 22:12:29 [INFO] Generating the client certificate and private key file for kubelet on 192.168.10.11 ...
2019/10/30 22:12:29 [INFO] generate received request
2019/10/30 22:12:29 [INFO] received CSR
2019/10/30 22:12:29 [INFO] generating key: rsa-4096
[192.168.10.13] 2019-10-30 22:12:29 [INFO] Generating the client certificate and private key file for kubelet on 192.168.10.13 ...
2019/10/30 22:12:29 [INFO] generate received request
2019/10/30 22:12:29 [INFO] received CSR
2019/10/30 22:12:29 [INFO] generating key: rsa-4096
[192.168.10.12] 2019-10-30 22:12:29 [INFO] Generating the client certificate and private key file for kubelet on 192.168.10.12 ...
2019/10/30 22:12:29 [INFO] generate received request
2019/10/30 22:12:29 [INFO] received CSR
2019/10/30 22:12:29 [INFO] generating key: rsa-4096
2019/10/30 22:12:30 [INFO] encoded CSR
2019/10/30 22:12:30 [INFO] encoded CSR
2019/10/30 22:12:30 [INFO] signed certificate with serial number 233177900276106427379860191878852506391290815614
2019/10/30 22:12:30 [INFO] signed certificate with serial number 638396454535262716534377928507089232904209137242
2019/10/30 22:12:33 [INFO] encoded CSR
2019/10/30 22:12:33 [INFO] signed certificate with serial number 727141257586612176523495635845510256236941350126
2019-10-30 22:12:33 [TITLE] Generating the data encryption config and key ...
2019-10-30 22:12:33 [INFO] Generating the kubeconfig file for kube-controller-manager ...
Cluster "kubernetes" set.
User "system:kube-controller-manager" set.
Context "default" created.
Switched to context "default".
2019-10-30 22:12:36 [INFO] Generating the kubeconfig file for kube-scheduler ...
Cluster "kubernetes" set.
User "system:kube-scheduler" set.
Context "default" created.
Switched to context "default".
2019-10-30 22:12:39 [INFO] Generating the kubeconfig file for kube-proxy ...
Cluster "kubernetes" set.
User "system:kube-proxy" set.
Context "default" created.
Switched to context "default".
2019-10-30 22:12:42 [INFO] Generating the kubeconfig file for user admin ...
Cluster "kubernetes" set.
User "admin" set.
Context "default" created.
Switched to context "default".
2019-10-30 22:12:45 [INFO] Distributing the kubeconfig files to all masters ...
2019-10-30 22:12:45 [INFO] Distributing the kubeconfig files to all nodes ...
[192.168.10.11] 2019-10-30 22:12:46 [INFO] Generating the kubeconfig file for kubelet on 192.168.10.11 ...
Cluster "kubernetes" set.
User "system:node:k8s-node1" set.
Context "default" created.
Switched to context "default".
[192.168.10.12] 2019-10-30 22:12:49 [INFO] Generating the kubeconfig file for kubelet on 192.168.10.12 ...
Cluster "kubernetes" set.
User "system:node:k8s-node2" set.
Context "default" created.
Switched to context "default".
[192.168.10.13] 2019-10-30 22:12:52 [INFO] Generating the kubeconfig file for kubelet on 192.168.10.13 ...
Cluster "kubernetes" set.
User "system:node:k8s-node3" set.
Context "default" created.
Switched to context "default".
[192.168.10.11] 2019-10-30 22:12:56 [INFO] Generating the kubeconfig file for kubectl on 192.168.10.11 ...
Cluster "kubernetes" set.
User "admin" set.
Context "kubernetes" created.
Switched to context "kubernetes".
[192.168.10.12] 2019-10-30 22:12:59 [INFO] Generating the kubeconfig file for kubectl on 192.168.10.12 ...
Cluster "kubernetes" set.
User "admin" set.
Context "kubernetes" created.
Switched to context "kubernetes".
[192.168.10.13] 2019-10-30 22:13:02 [INFO] Generating the kubeconfig file for kubectl on 192.168.10.13 ...
Cluster "kubernetes" set.
User "admin" set.
Context "kubernetes" created.
Switched to context "kubernetes".
2019-10-30 22:13:04 [INFO] [kube-kit init cert] completed successfully!
2019-10-30 22:13:04 [INFO] [kube-kit init cert] used total time: 1m5s
2019-10-30 22:13:04 [INFO] [kube-kit init all] completed successfully!
2019-10-30 22:13:04 [INFO] [kube-kit init all] used total time: 6m14s
```

</p></details>

### Subcommand `deploy`

``` bash
$ ./kube-kit deploy all
```

<details><summary>:eyes: click me to show/hide long messages :eyes:</summary><p>

``` text
2019-10-30 22:13:36 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:13:41 [TITLE] Starting to execute the command `kube-kit deploy all` ...
2019-10-30 22:13:41 [INFO] Deploying all the components for kubernetes cluster ...
2019-10-30 22:13:41 [INFO] `kube-kit deploy all` will start from <etcd>, because all the options before <etcd> have been executed successfully!
2019-10-30 22:13:43 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:13:48 [TITLE] Starting to execute the command `kube-kit deploy etcd` ...
2019-10-30 22:13:49 [INFO] Deploying the etcd secure cluster for kube-apiserver, flannel and calico ...
[192.168.10.11] 2019-10-30 22:13:50 [INFO] Installing etcd-3.3.11 on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:13:50 [INFO] Installing etcd-3.3.11 on 192.168.10.13 ...
[192.168.10.12] 2019-10-30 22:13:50 [INFO] Installing etcd-3.3.11 on 192.168.10.12 ...
[192.168.10.11] 2019-10-30 22:13:55 [DEBUG] Starting etcd.service on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:13:55 [DEBUG] Starting etcd.service on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:13:55 [DEBUG] Starting etcd.service on 192.168.10.13 ...
2019-10-30 22:13:57 [INFO] [kube-kit deploy etcd] completed successfully!
2019-10-30 22:13:57 [INFO] [kube-kit deploy etcd] used total time: 14.1s
2019-10-30 22:13:58 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:14:04 [TITLE] Starting to execute the command `kube-kit deploy docker` ...
2019-10-30 22:14:04 [INFO] Deploying the docker-ce-19.03.2 on all machines ...
[192.168.10.11] 2019-10-30 22:14:05 [INFO] Installing docker-ce-19.03.2 on 192.168.10.11 ...
[192.168.10.12] 2019-10-30 22:14:05 [INFO] Installing docker-ce-19.03.2 on 192.168.10.12 ...
[192.168.10.13] 2019-10-30 22:14:05 [INFO] Installing docker-ce-19.03.2 on 192.168.10.13 ...
2019-10-30 22:15:20 [DEBUG] Loading preloaded images on 192.168.10.11 ...
2019-10-30 22:15:20 [DEBUG] Loading preloaded images on 192.168.10.12 ...
2019-10-30 22:15:20 [DEBUG] Loading preloaded images on 192.168.10.13 ...
2019-10-30 22:21:21 [INFO] [kube-kit deploy docker] completed successfully!
2019-10-30 22:21:21 [INFO] [kube-kit deploy docker] used total time: 7m22s
2019-10-30 22:21:23 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:21:28 [TITLE] Starting to execute the command `kube-kit deploy proxy` ...
2019-10-30 22:21:28 [INFO] Deploying the reverse-proxy for all the exposed services ...
[192.168.10.11] 2019-10-30 22:21:29 [INFO] Installing nginx on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:21:29 [INFO] Installing nginx on 192.168.10.13 ...
[192.168.10.12] 2019-10-30 22:21:29 [INFO] Installing nginx on 192.168.10.12 ...
[192.168.10.11] 2019-10-30 22:21:35 [INFO] Installing keepalived on 192.168.10.11 ...
[192.168.10.13] 2019-10-30 22:21:35 [INFO] Installing keepalived on 192.168.10.13 ...
[192.168.10.12] 2019-10-30 22:21:36 [INFO] Installing keepalived on 192.168.10.12 ...
2019-10-30 22:21:46 [INFO] [kube-kit deploy proxy] completed successfully!
2019-10-30 22:21:46 [INFO] [kube-kit deploy proxy] used total time: 22.9s
2019-10-30 22:21:47 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:21:51 [TITLE] Starting to execute the command `kube-kit deploy master` ...
2019-10-30 22:21:55 [INFO] Deploying the kubernetes master components ...
2019-10-30 22:22:08 [INFO] [kube-kit deploy master] completed successfully!
2019-10-30 22:22:08 [INFO] [kube-kit deploy master] used total time: 21.4s
2019-10-30 22:22:10 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:22:15 [TITLE] Starting to execute the command `kube-kit deploy node` ...
2019-10-30 22:22:17 [INFO] Deploying the kubernetes node components ...
2019-10-30 22:22:18 [DEBUG] Waiting at most 100 seconds until all nodes are in Ready status ...
2019-10-30 22:22:44 [INFO] Setting master role for all kubernetes masters ...
node/k8s-node1 labeled
node/k8s-node2 labeled
node/k8s-node3 labeled
2019-10-30 22:22:47 [INFO] Setting node role for all kubernetes nodes ...
node/k8s-node2 labeled
node/k8s-node3 labeled
node/k8s-node1 labeled
2019-10-30 22:22:49 [INFO] Setting cputype and gputype for all kubernetes nodes ...
node/k8s-node2 labeled
node/k8s-node1 labeled
node/k8s-node3 labeled
2019-10-30 22:22:50 [INFO] [kube-kit deploy node] completed successfully!
2019-10-30 22:22:50 [INFO] [kube-kit deploy node] used total time: 40.3s
2019-10-30 22:22:52 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:22:56 [TITLE] Starting to execute the command `kube-kit deploy crontab` ...
2019-10-30 22:22:56 [INFO] Deploying the Crontab jobs on all hosts ...
2019-10-30 22:23:03 [INFO] Setting crontab for all the k8s masters ...
2019-10-30 22:23:03 [INFO] Setting crontab for all the k8s nodes ...
2019-10-30 22:23:04 [INFO] [kube-kit deploy crontab] completed successfully!
2019-10-30 22:23:04 [INFO] [kube-kit deploy crontab] used total time: 12.0s
2019-10-30 22:23:05 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:23:10 [TITLE] Starting to execute the command `kube-kit deploy calico` ...
2019-10-30 22:23:10 [INFO] Deploying the CNI plugin(calico) for kubernetes cluster ...
2019-10-30 22:23:10 [DEBUG] Waiting at most 600 seconds until all the pods of daemonset/calico-node in the namespace kube-system are deleted ...
2019-10-30 22:23:10 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/calico-kube-controllers in the namespace kube-system are deleted ...
configmap/calico-config created
secret/calico-etcd-secrets created
serviceaccount/calico-node created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
serviceaccount/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
deployment.apps/calico-kube-controllers created
2019-10-30 22:23:12 [DEBUG] Waiting at most 600 seconds until all the pods of daemonset/calico-node in the namespace kube-system are ready ...
2019-10-30 22:23:34 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/calico-kube-controllers in the namespace kube-system are ready ...
2019-10-30 22:23:35 [INFO] [kube-kit deploy calico] completed successfully!
2019-10-30 22:23:35 [INFO] [kube-kit deploy calico] used total time: 29.8s
2019-10-30 22:23:37 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:23:41 [TITLE] Starting to execute the command `kube-kit deploy coredns` ...
2019-10-30 22:23:41 [INFO] Deploying the CoreDNS addon for kubernetes cluster ...
2019-10-30 22:23:42 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/coredns in the namespace kube-system are deleted ...
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
configmap/coredns created
deployment.apps/coredns created
service/coredns created
2019-10-30 22:23:43 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/coredns in the namespace kube-system are ready ...
2019-10-30 22:23:59 [INFO] [kube-kit deploy coredns] completed successfully!
2019-10-30 22:23:59 [INFO] [kube-kit deploy coredns] used total time: 22.3s
2019-10-30 22:24:00 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:24:05 [TITLE] Starting to execute the command `kube-kit deploy heketi` ...
2019-10-30 22:24:05 [INFO] Deploying the Heketi service to manage glusterfs cluster automatically ...
[192.168.10.13] 2019-10-30 22:24:08 [WARN] Trying to wipe the device /dev/sdc on 192.168.10.13 now ...
[192.168.10.13] 2019-10-30 22:24:14 [WARN] Trying to wipe the device /dev/sdd on 192.168.10.13 now ...
[192.168.10.13] 2019-10-30 22:24:17 [WARN] Trying to wipe the device /dev/sde on 192.168.10.13 now ...
[192.168.10.12] 2019-10-30 22:24:20 [WARN] Trying to wipe the device /dev/sdc on 192.168.10.12 now ...
[192.168.10.12] 2019-10-30 22:24:23 [WARN] Trying to wipe the device /dev/sdd on 192.168.10.12 now ...
[192.168.10.11] 2019-10-30 22:24:25 [WARN] Trying to wipe the device /dev/sdc on 192.168.10.11 now ...
2019-10-30 22:24:32 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/heketi in the namespace kube-system are deleted ...
deployment.apps/heketi created
service/heketi created
2019-10-30 22:24:32 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/heketi in the namespace kube-system are ready ...
[192.168.10.11] 2019-10-30 22:24:51 [INFO] Generating a topology file of heketi cluster for glusterfs ...
[192.168.10.11] 2019-10-30 22:24:52 [INFO] Loading the topology of glusterfs cluster into heketi ...
Creating cluster ... ID: 66689762ebc548e1d1a7a45a7e1bfb16
	Allowing file volumes on cluster.
	Allowing block volumes on cluster.
	Creating node 192.168.30.13 ... ID: df10f31e9c1cbe4f339f305be08305e0
		Adding device /dev/sdc ... OK
		Adding device /dev/sdd ... OK
		Adding device /dev/sde ... OK
	Creating node 192.168.30.12 ... ID: f624170b58d09697f6097d9d76fd8018
		Adding device /dev/sdc ... OK
		Adding device /dev/sdd ... OK
	Creating node 192.168.30.11 ... ID: 9a5461246ef23ccd4e614a03ba54b95e
		Adding device /dev/sdc ... OK
storageclass.storage.k8s.io/glusterfs-replicate-3 created
2019-10-30 22:25:07 [INFO] [kube-kit deploy heketi] completed successfully!
2019-10-30 22:25:07 [INFO] [kube-kit deploy heketi] used total time: 1m6s
2019-10-30 22:25:08 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:25:12 [TITLE] Starting to execute the command `kube-kit deploy harbor` ...
2019-10-30 22:25:12 [INFO] Deploying the harbor docker private image repertory ...
2019-10-30 22:25:14 [DEBUG] Loading all the harbor images on 192.168.10.13 ...
2019-10-30 22:25:14 [DEBUG] Loading all the harbor images on 192.168.10.12 ...
2019-10-30 22:25:14 [DEBUG] Loading all the harbor images on 192.168.10.11 ...
namespace/harbor-system created
persistentvolumeclaim/harbor-storage created
deployment.apps/registry created
service/registry created
deployment.apps/db created
service/db created
deployment.apps/adminserver created
service/adminserver created
deployment.apps/redis created
service/redis created
deployment.apps/jobservice created
service/jobservice created
deployment.apps/ui created
service/ui created
deployment.apps/nginx created
service/nginx created
2019-10-30 22:31:10 [DEBUG] Waiting at most 300s until harbor ui is ready ...
2019-10-30 22:33:03 [DEBUG] Waiting at most 300s until we can docker login to harbor ...
Create project 'kube-system' successfully.
2019-10-30 22:33:06 [INFO] Copying /root/kube-kit/binaries/harbor/library-images.tar.gz to 192.168.10.10 ...
[192.168.10.11] 2019-10-30 22:33:14 [INFO] Trying to login to 192.168.10.10:30050 using admin ...
Login Succeeded
[192.168.10.11] 2019-10-30 22:33:14 [INFO] Uncompressing /tmp/library-images.tar.gz ...
library-images/
library-images/netshoot:latest.tar
library-images/busybox:1.31.0.tar
library-images/nginx:1.11.13.tar
[192.168.10.11] 2019-10-30 22:33:18 [DEBUG] Pushing the image: 192.168.10.10:30050/library/busybox:1.31.0 ...
[192.168.10.11] 2019-10-30 22:33:23 [DEBUG] Pushing the image: 192.168.10.10:30050/library/nginx:1.11.13 ...
[192.168.10.11] 2019-10-30 22:34:12 [DEBUG] Pushing the image: 192.168.10.10:30050/library/netshoot:latest ...
2019-10-30 22:34:54 [INFO] Copying /root/kube-kit/binaries/harbor/k8s-addons-images.tar.gz to 192.168.10.10 ...
[192.168.10.11] 2019-10-30 22:35:07 [INFO] Trying to login to 192.168.10.10:30050 using admin ...
Login Succeeded
[192.168.10.11] 2019-10-30 22:35:07 [INFO] Uncompressing /tmp/k8s-addons-images.tar.gz ...
k8s-addons-images/
k8s-addons-images/defaultbackend:1.4.tar
k8s-addons-images/nginx-ingress-controller:0.26.1.tar
[192.168.10.11] 2019-10-30 22:35:11 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/defaultbackend:1.4 ...
[192.168.10.11] 2019-10-30 22:35:24 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/nginx-ingress-controller:0.26.1 ...
2019-10-30 22:37:09 [INFO] Copying /root/kube-kit/binaries/harbor/preloaded-images.tar.gz to 192.168.10.10 ...
[192.168.10.11] 2019-10-30 22:37:16 [INFO] Trying to login to 192.168.10.10:30050 using admin ...
Login Succeeded
[192.168.10.11] 2019-10-30 22:37:17 [INFO] Uncompressing /tmp/preloaded-images.tar.gz ...
preloaded-images/
preloaded-images/calico-cni:v3.9.1.tar
preloaded-images/calico-kube-controllers:v3.9.1.tar
preloaded-images/calico-node:v3.9.1.tar
preloaded-images/calico-pod2daemon-flexvol:v3.9.1.tar
preloaded-images/coredns:1.6.4.tar
preloaded-images/heketi:v9.0.0.tar
preloaded-images/pause-amd64:3.1.tar
[192.168.10.11] 2019-10-30 22:37:26 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/pause-amd64:3.1 ...
[192.168.10.11] 2019-10-30 22:37:45 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/calico-pod2daemon-flexvol:v3.9.1 ...
[192.168.10.11] 2019-10-30 22:38:01 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/coredns:1.6.4 ...
[192.168.10.11] 2019-10-30 22:38:26 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/calico-kube-controllers:v3.9.1 ...
[192.168.10.11] 2019-10-30 22:38:42 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/calico-cni:v3.9.1 ...
[192.168.10.11] 2019-10-30 22:39:22 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/calico-node:v3.9.1 ...
[192.168.10.11] 2019-10-30 22:40:16 [DEBUG] Pushing the image: 192.168.10.10:30050/kube-system/heketi:v9.0.0 ...
2019-10-30 22:41:33 [INFO] [kube-kit deploy harbor] completed successfully!
2019-10-30 22:41:33 [INFO] [kube-kit deploy harbor] used total time: 16m25s
2019-10-30 22:41:35 [TITLE] Starting to parse all the configurations of kube-kit ...
2019-10-30 22:41:40 [TITLE] Starting to execute the command `kube-kit deploy ingress` ...
2019-10-30 22:41:40 [INFO] Deploying the nginx ingress controller addon for kubernetes cluster ...
namespace/ingress-nginx created
configmap/nginx-configuration created
configmap/tcp-services created
configmap/udp-services created
serviceaccount/nginx-ingress-serviceaccount created
clusterrole.rbac.authorization.k8s.io/nginx-ingress-clusterrole created
role.rbac.authorization.k8s.io/nginx-ingress-role created
rolebinding.rbac.authorization.k8s.io/nginx-ingress-role-nisa-binding created
clusterrolebinding.rbac.authorization.k8s.io/nginx-ingress-clusterrole-nisa-binding created
deployment.apps/nginx-ingress-controller created
service/ingress-nginx created
2019-10-30 22:41:41 [DEBUG] Waiting at most 600 seconds until all the pods of deployment/nginx-ingress-controller in the namespace ingress-nginx are ready ...
2019-10-30 22:41:52 [INFO] [kube-kit deploy ingress] completed successfully!
2019-10-30 22:41:52 [INFO] [kube-kit deploy ingress] used total time: 17.5s
2019-10-30 22:41:52 [INFO] [kube-kit deploy all] completed successfully!
2019-10-30 22:41:52 [INFO] [kube-kit deploy all] used total time: 28m16s
```

</p></details>
