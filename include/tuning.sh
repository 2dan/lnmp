#!/usr/bin/env bash

# Hardware-aware tuning shared by fresh installs and explicit retuning.
# Values are intentionally conservative because LNMP services share one host.

Detect_Hardware_Profile()
{
    HW_CPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
    HW_MEM_MB=$(awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo)
    [ -z "${HW_MEM_MB}" ] && HW_MEM_MB=1024

    local cgroup_limit
    if [ -r /sys/fs/cgroup/memory.max ]; then
        cgroup_limit=$(cat /sys/fs/cgroup/memory.max)
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        cgroup_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
    fi
    if [[ "${cgroup_limit:-max}" =~ ^[0-9]+$ ]] && [ "${cgroup_limit}" -lt 9223372036854771712 ]; then
        cgroup_limit=$((cgroup_limit / 1024 / 1024))
        [ "${cgroup_limit}" -gt 0 ] && [ "${cgroup_limit}" -lt "${HW_MEM_MB}" ] && HW_MEM_MB=${cgroup_limit}
    fi

    HW_DISK_ROTATIONAL=0
    if find /sys/block -maxdepth 2 -name rotational -type f -exec grep -q '^1$' {} \; 2>/dev/null; then
        HW_DISK_ROTATIONAL=1
    fi
    export HW_CPU HW_MEM_MB HW_DISK_ROTATIONAL
}

Tune_Kernel()
{
    Detect_Hardware_Profile
    local backlog file_max swappiness
    backlog=$((HW_CPU * 4096))
    [ "${backlog}" -lt 4096 ] && backlog=4096
    [ "${backlog}" -gt 65535 ] && backlog=65535
    file_max=$((HW_CPU * 131072))
    [ "${file_max}" -lt 1048576 ] && file_max=1048576
    [ "${file_max}" -gt 8388608 ] && file_max=8388608
    [ "${HW_MEM_MB}" -ge 2048 ] && swappiness=10 || swappiness=20

    install -d -m 0755 /etc/sysctl.d
    cat >/etc/sysctl.d/90-lnmp-tuning.conf <<EOF
# Managed by LNMP. Re-run tools/tune.sh after changing server resources.
fs.file-max = ${file_max}
fs.inotify.max_user_watches = 524288
net.core.somaxconn = ${backlog}
net.core.netdev_max_backlog = ${backlog}
net.ipv4.tcp_max_syn_backlog = ${backlog}
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
vm.swappiness = ${swappiness}
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
vm.overcommit_memory = 1
EOF
    sysctl --system >/dev/null 2>&1 || Echo_Yellow "Some kernel parameters could not be applied in this environment."
}

Tune_Nginx()
{
    local nginx_conf=${1:-/usr/local/nginx/conf/nginx.conf}
    [ -f "${nginx_conf}" ] || return 0
    Detect_Hardware_Profile
    local total_connections worker_connections
    total_connections=$((HW_MEM_MB * 48))
    [ "${total_connections}" -lt 4096 ] && total_connections=4096
    [ "${total_connections}" -gt 200000 ] && total_connections=200000
    worker_connections=$((total_connections / HW_CPU))
    [ "${worker_connections}" -lt 1024 ] && worker_connections=1024
    [ "${worker_connections}" -gt 32768 ] && worker_connections=32768

    sed -i -E 's/^worker_processes[[:space:]]+[^;]+;/worker_processes auto;/' "${nginx_conf}"
    if grep -q '^worker_rlimit_nofile' "${nginx_conf}"; then
        sed -i -E 's/^worker_rlimit_nofile.*/worker_rlimit_nofile 262144;/' "${nginx_conf}"
    else
        sed -i '/^worker_processes/a worker_rlimit_nofile 262144;' "${nginx_conf}"
    fi
    sed -i -E "s/worker_connections[[:space:]]+[0-9]+;/worker_connections ${worker_connections};/" "${nginx_conf}"
    sed -i -E 's/^[[:space:]]*keepalive_timeout[[:space:]]+[^;]+;/        keepalive_timeout 30;/' "${nginx_conf}"
}

Tune_PHP_FPM()
{
    local php_prefix=${1:-/usr/local/php}
    local fpm_conf="${php_prefix}/etc/php-fpm.conf"
    [ -f "${fpm_conf}" ] || return 0
    Detect_Hardware_Profile
    local budget_mb max_children start_servers min_spare max_spare
    budget_mb=$((HW_MEM_MB * 25 / 100))
    [ "${budget_mb}" -lt 320 ] && budget_mb=320
    max_children=$((budget_mb / 64))
    [ "${max_children}" -lt 5 ] && max_children=5
    [ "${max_children}" -gt $((HW_CPU * 32)) ] && max_children=$((HW_CPU * 32))
    [ "${max_children}" -gt 256 ] && max_children=256
    start_servers=$((HW_CPU * 2))
    [ "${start_servers}" -lt 2 ] && start_servers=2
    [ "${start_servers}" -gt $((max_children / 2)) ] && start_servers=$((max_children / 2))
    [ "${start_servers}" -lt 1 ] && start_servers=1
    min_spare=${start_servers}
    max_spare=$((start_servers * 2))
    [ "${max_spare}" -gt "${max_children}" ] && max_spare=${max_children}

    sed -i -E "s/^pm.max_children.*/pm.max_children = ${max_children}/" "${fpm_conf}"
    sed -i -E "s/^pm.start_servers.*/pm.start_servers = ${start_servers}/" "${fpm_conf}"
    sed -i -E "s/^pm.min_spare_servers.*/pm.min_spare_servers = ${min_spare}/" "${fpm_conf}"
    sed -i -E "s/^pm.max_spare_servers.*/pm.max_spare_servers = ${max_spare}/" "${fpm_conf}"
    install -d -m 0750 -o www -g www "${php_prefix}/var/log" "${php_prefix}/var/run"
}

Tune_Database()
{
    [ -f /etc/my.cnf ] || return 0
    declare -F MySQL_Opt >/dev/null 2>&1 || return 0
    if grep -Eqi '^[[:space:]]*default_storage_engine[[:space:]]*=[[:space:]]*MyISAM' /etc/my.cnf; then
        InstallInnodb=n
    else
        InstallInnodb=y
    fi
    MySQL_Opt
}

Apply_Runtime_Tuning()
{
    local php_prefix
    Tune_Kernel
    [ -x /usr/local/nginx/sbin/nginx ] && Tune_Nginx /usr/local/nginx/conf/nginx.conf
    while IFS= read -r -d '' php_prefix; do
        [ -x "${php_prefix}/sbin/php-fpm" ] && Tune_PHP_FPM "${php_prefix}"
    done < <(find /usr/local -maxdepth 1 -type d -name 'php*' -print0 2>/dev/null)
    Tune_Database
}
