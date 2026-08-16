#!/usr/bin/env bash
set -u

# Atomic rotation for Nginx and all installed PHP-FPM instances.
retention_days=${LNMP_LOG_RETENTION_DAYS:-30}
case "${retention_days}" in
    ''|*[!0-9]*) echo "Invalid LNMP_LOG_RETENTION_DAYS." >&2; exit 2 ;;
esac

install -d -m 0755 /run/lock
exec 9>/run/lock/lnmp-logrotate.lock
if command -v flock >/dev/null 2>&1; then
    flock -n 9 || exit 0
fi
rotation_stamp=$(date +%Y%m%d)

rotate_service_logs()
{
    local log_dir=$1 pid_file=$2 archive_dir log_file relative safe_name target pid
    [ -d "${log_dir}" ] || return 0
    [ -r "${pid_file}" ] || return 0
    pid=$(cat "${pid_file}" 2>/dev/null)
    [[ "${pid}" =~ ^[0-9]+$ ]] || return 0
    kill -0 "${pid}" 2>/dev/null || return 0

    archive_dir="${log_dir}/archive"
    install -d -m 0750 "${archive_dir}"
    while IFS= read -r -d '' log_file; do
        [ -s "${log_file}" ] || continue
        relative=${log_file#"${log_dir}"/}
        safe_name=${relative//\//__}
        target="${archive_dir}/${safe_name}.${rotation_stamp}"
        [ -e "${target}" ] && target="${target}.$(date +%H%M%S)"
        mv -- "${log_file}" "${target}"
    done < <(find "${log_dir}" -type f -name '*.log' ! -path "${archive_dir}/*" -print0)

    # USR1 asks both Nginx and PHP-FPM masters to reopen logs without restart.
    kill -USR1 "${pid}" 2>/dev/null || true
    find "${archive_dir}" -type f ! -name '*.gz' -mtime +0 -exec gzip -9 -- {} \;
    find "${archive_dir}" -type f -mtime "+${retention_days}" -delete
}

rotate_service_logs /usr/local/nginx/logs /usr/local/nginx/logs/nginx.pid
while IFS= read -r -d '' php_dir; do
    rotate_service_logs "${php_dir}/var/log" "${php_dir}/var/run/php-fpm.pid"
done < <(find /usr/local -maxdepth 1 -type d -name 'php*' -print0 2>/dev/null)
