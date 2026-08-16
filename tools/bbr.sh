#!/usr/bin/env bash

set -u

BBR_SYSCTL_FILE=/etc/sysctl.d/99-lnmp-bbr.conf
BBR_MODULE_FILE=/etc/modules-load.d/99-lnmp-bbr.conf

require_root()
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: this command must be run as root." >&2
        exit 1
    fi
}

show_status()
{
    echo "kernel: $(uname -r)"
    echo "available: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)"
    echo "active: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    echo "qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    if lsmod 2>/dev/null | grep -q '^tcp_bbr '; then
        echo "module: loaded"
    else
        echo "module: built-in or not loaded"
    fi
}

enable_bbr()
{
    require_root
    if [ "$(uname -s)" != "Linux" ]; then
        echo "Error: BBR is only supported on Linux." >&2
        exit 1
    fi

    kernel_version=$(uname -r | cut -d- -f1)
    if [ "$(printf '%s\n' 4.9 "${kernel_version}" | sort -V | head -n1)" != "4.9" ]; then
        echo "Error: BBR requires Linux kernel 4.9 or newer (current: ${kernel_version})." >&2
        exit 1
    fi

    modprobe tcp_bbr 2>/dev/null || true
    if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | tr ' ' '\n' | grep -qx bbr; then
        echo "Error: tcp_bbr is not available in the running kernel." >&2
        exit 1
    fi

    install -d -m 0755 /etc/sysctl.d
    install -d -m 0755 /etc/modules-load.d
    temp_file=$(mktemp /etc/sysctl.d/.99-lnmp-bbr.conf.XXXXXX)
    module_temp_file=$(mktemp /etc/modules-load.d/.99-lnmp-bbr.conf.XXXXXX)
    trap 'rm -f "${temp_file:-}" "${module_temp_file:-}"' EXIT
    cat >"${temp_file}" <<'EOF'
# Managed by LNMP. BBR requires Linux 4.9 or newer.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    printf '%s\n' 'tcp_bbr' >"${module_temp_file}"
    chmod 0644 "${temp_file}"
    chmod 0644 "${module_temp_file}"
    mv -f "${temp_file}" "${BBR_SYSCTL_FILE}"
    mv -f "${module_temp_file}" "${BBR_MODULE_FILE}"
    trap - EXIT

    sysctl --system >/dev/null
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]; then
        echo "Error: BBR configuration was written but could not be activated." >&2
        exit 1
    fi
    echo "BBR has been enabled and persisted."
    show_status
}

case "${1:-enable}" in
    enable)
        enable_bbr
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: lnmp-bbr {enable|status}" >&2
        exit 1
        ;;
esac
