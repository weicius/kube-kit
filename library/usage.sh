#!/usr/bin/env bash
# vim: nu:noai:ts=4
# shellcheck shell=bash disable=SC1090,SC2034,SC2206,SC2207


function usage::kube_kit_help_msg() {
	cat <<-EOF

	Usage: ${0} <Subcommand> <Subcommand-Option> [Options]

	Options (can be anywhere):
	    -n|--no-records      Do not record the successful message of current subcommand

	Subcommand:
	    check                Check if requirements are satisfied
	    init                 Initialize the basic environment
	    deploy               Deploy the specified component
	    clean                Clean the specified component
	    update               Update the specified component

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
	    prometheus           Deploy the Prometheus monitoring for kubernetes cluster
	    heapster             Deploy the Heapster addon for kubernetes cluster
	    dashboard            Deploy the Dashboard addon for kubernetes cluster
	    efk                  Deploy the EFK logging addon for kubernetes cluster
	    all                  Deploy all the components for kubernetes cluster

	Options for 'clean':
	    master               Clean the kubernetes masters
	    node                 Clean the kubernetes nodes
	    all                  Clean all the components listed above

	Options for 'update':
	    cluster              Update all the components of kubernetes
	    node                 Add some NEW nodes into kubernetes cluster
	    heketi               Add some NEW nodes or NEW devices into heketi cluster

	EOF
}


function usage::kube_kit() {
    final_help_msg="$(usage::kube_kit_help_msg)"
    subcmds=($(usage::kube_kit_help_msg | grep -oP "(?<=Options for ')[^']+(?=')"))
    for subcmd in "${subcmds[@]}"; do
        subcmd_options=($(usage::kube_kit_help_msg |\
            sed -nr "/'${subcmd}':/,/^$/s/^\s+(\S+).*/\1/p" | paste -sd ' '))
        for option in "${subcmd_options[@]}"; do
            allowed_options=(${SUBCMD_OPTIONS[${subcmd}]})
            # if you delete/comment the option of subcmd in etc/cmd.ini, we need to
            # remove the help message of the command 'kube-kit ${subcmd} ${option}'
            util::element_in_array "${option}" "${allowed_options[@]}" && continue
            LOG warn "option '${option}' is NOT allowed by the subcmd '${subcmd}'"
            final_help_msg=$(echo -e "${final_help_msg}" |\
                             sed -r "/'${subcmd}':/,/^$/{/^\s+${option}/d}")
        done
    done
    echo -e "${final_help_msg}\n" && return "${1:-0}"
}


function usage::ssh::execute() {
    local exit_code="${1:-0}"

	cat <<-EOF

	ssh::execute is a library function which will execute a local function
	(defined in the local script) or raw commands on a remote Linux server

	Tips:
	    1. you can pass options and arguments to the function or raw command
	    2. your own functions in local scripts or raw commands can also call
	    any function which is defined in scripts in this directory:
	    ${__KUBE_KIT_DIR__}/library
	    3. your own functions in local scripts or raw commands can also use
	    any variable whose name starts with any prefix listed in the config
	    file: ${__KUBE_KIT_DIR__}/etc/env.prefix
	    4. your local scripts should end with a newline!
	    5. your local scripts should contain ONLY definitions of functions,
	    must NOT execute normal commands!
	    6. raw command MUST be surrounded by a pair of quotation mark(""|'')

	Usage of <ssh::execute> function:
	ssh::execute -h|--host ipv4_address \\
	             [-s|--script local_script1] \\
	             [-s|--script local_script2] \\
	             [-t|--timeout seconds] \\
	             [-q|--quiet] \\
	             -- [func] options_and_parameters_of_func_OR_raw_cmd

	Options:
	    -h, --host   *string  The ipv4 address of the remote Linux server
	    -s, --script  string  Local script where the function is defined
	    -t, --timeout    int  Force to exit this function if the timeout
	    -q, --quiet           The function won't print anything
	    -?, --help            Print current help messages

	EOF

    return "${exit_code}"
}


function usage::ssh::execute_parallel() {
    local exit_code="${1:-0}"

	cat <<-EOF

	ssh::execute_parallel is a wrapped function which will call ssh::execute
	on one or multiple Linux servers parallelly.

	Usage of <ssh::execute_parallel> function:
	    ssh::execute_parallel \\
	                 -h|--hosts host1 host2 ... hostn \\
	                 [-s|--script local_script1] \\
	                 [-s|--script local_script2] \\
	                 [-p|--parallel [2, ${MAX_SSH_PARALLEL}]] \\
	                 [-t|--timeout seconds] \\
	                 [-q|--quiet] \\
	                 -- [func] options_and_parameters_of_func_OR_raw_cmd

	Options:
	    -h, --hosts   *string  The ipv4 addresses (>=1) of the remote Linux servers
	                           Or use the defined groups: all, master, node or etcd
	    -s, --script   string  Local script file in which the function is defined
	    -p, --parallel    int  Execute func/rawcmd on N hosts everytime parallelly
	    -t, --timeout     int  Force to exit current function if the timeout exceed
	    -q, --quiet            The function won't print anything
	    -?, --help             Print current help messages and exit

	Notes:
	    1. Raw commands MUST be surrounded by a pair of quotation marks (""|'')
	    2. Parallel degree should be in the range: [2, ${MAX_SSH_PARALLEL}]!

	EOF

    return "${exit_code}"
}


function usage::scp::execute() {
    local exit_code="${1:-0}"

	cat <<-EOF

	scp::execute is a library function which can copy multiple local files or
	directories to another remote Linux server using scp command, vice versa.

	Usage of <scp::execute> function:
	    scp::execute -h|--host ipv4_address \\
	                 [-r|--reverse] \\
	                 -s|--source file_or_dir1 \\
	                 -s|--source file_or_dir2 \\
	                 -d|--destination file_or_dir

	Options:
	    -h, --host        *string  The ipv4 address of the remote server
	    -s, --source      *string  The source file or directory to be copied
	    -d, --destination *string  The destination to store the source files
	    -r, --reverse              Copy file or directory from remote server
	    -?, --help                 Print current help messages and exit

	Notes: The destination MUST be a directory if you have multiple sources!

	EOF

    return "${exit_code}"
}


function usage::scp::execute_parallel() {
    local exit_code="${1:-0}"

	cat <<-EOF

	scp::execute_parallel is a wrapped function which can enable user
	to call the function scp::execute on multiple hosts parallelly.

	Usage of <scp::execute_parallel> function:
	    scp::execute_parallel \\
	                 -h|--hosts host1 host2 ... hostn \\
	                 [-p|--parallel [2, ${MAX_SCP_PARALLEL}]] \\
	                 [-r|--reverse] \\
	                 -s|--source file_or_dir1 \\
	                 -s|--source file_or_dir2 \\
	                 -d|--destination file_or_dir

	Options:
	    -h, --hosts       *string  The ipv4 addresses (>=1) of remote hosts
	                               Or use groups: all, master, node or etcd
	    -s, --source      *string  The source file or directory to be copied
	    -d, --destination *string  The destination to store the source files
	    -p, --parallel        int  Copy N files/dires everytime parallelly
	    -r, --reverse              Copy file or directory from remote server
	    -?, --help                 Print current help messages and exit

	Notes:
	    1. Parallel degree should be in the range: [2, ${MAX_SCP_PARALLEL}]!
	    2. The destination MUST be a directory if you have multiple sources!

	EOF

    return "${exit_code}"
}


function usage::local_execute_parallel() {
    local exit_code="${1:-0}"

	cat <<-EOF

	local::execute_parallel is a util function which execute a local function parallelly
	in which function, you can check some complex conditions and then call ssh::execute
	or scp::execute many times to do complex things on multiple remote Linux servers.

	Usage of <local::execute_parallel> function:
	    local::execute_parallel -h|--hosts host1 host2 ... hostn \\
	                            -f|--function local_func \\
	                            [-p|--parallel [2, ${MAX_LOCAL_PARALLEL}]] \\
	                            -- options_and_parameters_for_the_local_func

	Options:
	    -h, --hosts    *string  The ipv4 addresses (>=1) of the remote Linux servers
	                            Or use the defined groups: all, master, node or etcd
	    -f, --function *string  The name of local function to be executed parallelly
	    -p, --parallel     int  Execute the function on N hosts everytime parallelly
	    -?, --help              Print current help messages and exit

	Notes:
	    1. Can use the built-in variables '\${HOST}' and '\${INDEX}' in your function
	    2. Parallel degree should be in the range: [2, ${MAX_LOCAL_PARALLEL}]!

	Examples:
	    function local_execute_parallel_test() {
	        # fails with the probability 33.3%
	        ((RANDOM % 3 == 1)) && return 1
	        LOG debug "INDEX: \${INDEX}; HOST: \${HOST}"
	        ssh::execute -h "\${HOST}" -- "hostname -I"
	    }

	    local::execute_parallel -h all \\
	                            -f local_execute_parallel_test \\
	                            -p 10 \\
	                            -- -a 1 -b 2 -c -d -e

	EOF

    return "${exit_code}"
}
