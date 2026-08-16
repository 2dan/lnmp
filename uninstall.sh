#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root privileges are required." >&2
    exit 1
fi

cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${cur_dir}" || exit 1
. lnmp.conf
. include/main.sh

Check_DB
Check_Stack
if [ "${Get_Stack}" != lnmp ]; then
    Echo_Red 'A complete LNMP installation was not detected.'
    exit 1
fi

cat <<EOF
The following LNMP runtime paths will be removed after the database is moved to /root:
  /usr/local/nginx
  /usr/local/php and installed /usr/local/phpX.Y instances
  ${MySQL_Dir}
  /etc/my.cnf and LNMP service files
  /bin/lnmp and /usr/local/sbin/lnmp-* helpers

Website data under ${Default_Website_Dir} will be preserved.
EOF
Press_Start

lnmp stop 2>/dev/null || true
Remove_StartUp nginx
Remove_StartUp php-fpm
if [ "${DB_Name}" != None ]; then
    Remove_StartUp "${DB_Name}"
    backup_dir="/root/databases_backup_$(date +%Y%m%d%H%M%S)"
    if [ "${DB_Name}" = mysql ]; then
        Validate_Install_Path "${MySQL_Data_Dir}" 'MySQL data directory' || exit 1
        [ ! -d "${MySQL_Data_Dir}" ] || mv -- "${MySQL_Data_Dir}" "${backup_dir}"
    else
        Validate_Install_Path "${MariaDB_Data_Dir}" 'MariaDB data directory' || exit 1
        [ ! -d "${MariaDB_Data_Dir}" ] || mv -- "${MariaDB_Data_Dir}" "${backup_dir}"
    fi
    Echo_Green "Database files were moved to ${backup_dir}."
fi

chattr -i "${Default_Website_Dir}/.user.ini" 2>/dev/null || true
for php_dir in /usr/local/php /usr/local/php7.4 /usr/local/php8.0 /usr/local/php8.1 /usr/local/php8.2 /usr/local/php8.3 /usr/local/php8.4 /usr/local/php8.5; do
    [ -d "${php_dir}" ] || continue
    php_branch=${php_dir#/usr/local/php}
    [ -z "${php_branch}" ] || Remove_StartUp "php-fpm${php_branch}" 2>/dev/null || true
    rm -rf -- "${php_dir}"
    [ -z "${php_branch}" ] || rm -f -- "/etc/init.d/php-fpm${php_branch}" "/etc/systemd/system/php-fpm${php_branch}.service"
done

rm -rf -- /usr/local/nginx /usr/local/zend
if [ "${DB_Name}" != None ]; then
    rm -rf -- "/usr/local/${DB_Name}"
    rm -f -- "/etc/init.d/${DB_Name}" "/etc/systemd/system/${DB_Name}.service"
fi

if [ -x /usr/local/acme.sh/acme.sh ]; then
    /usr/local/acme.sh/acme.sh --uninstall || true
    rm -rf -- /usr/local/acme.sh
fi

rm -f -- /etc/my.cnf /etc/init.d/nginx /etc/init.d/php-fpm \
    /etc/systemd/system/nginx.service /etc/systemd/system/php-fpm.service \
    /bin/lnmp /usr/local/sbin/lnmp-bbr /usr/local/sbin/lnmp-install-acme \
    /usr/local/sbin/lnmp-logrotate
systemctl daemon-reload 2>/dev/null || true
Echo_Green 'LNMP uninstall completed; website files and the database backup were preserved.'
