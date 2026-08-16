#!/usr/bin/env bash

Add_Iptables_Rules()
{
    # Preserve the administrator's firewall backend and policy. Only expose HTTP(S).
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=http || return 1
        firewall-cmd --permanent --add-service=https || return 1
        firewall-cmd --reload || return 1
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
        ufw allow 80/tcp || return 1
        ufw allow 443/tcp || return 1
    elif command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        Echo_Yellow 'HTTP(S) rules were added to the active iptables ruleset; persistence remains under administrator control.'
    else
        Echo_Yellow 'No supported active firewall manager was detected; no firewall policy was changed.'
    fi
}

Install_BBR_Tool()
{
    if [ -s "${cur_dir}/tools/bbr.sh" ]; then
        \cp "${cur_dir}/tools/bbr.sh" /usr/local/sbin/lnmp-bbr
        chmod 0755 /usr/local/sbin/lnmp-bbr
    fi
    if [ -s "${cur_dir}/tools/install_acme.sh" ]; then
        \cp "${cur_dir}/tools/install_acme.sh" /usr/local/sbin/lnmp-install-acme
        chmod 0755 /usr/local/sbin/lnmp-install-acme
    fi
}

Install_Log_Rotation()
{
    install -m 0750 "${cur_dir}/tools/cut_nginx_logs.sh" /usr/local/sbin/lnmp-logrotate
    (crontab -l 2>/dev/null | grep -v -E 'lnmp-logrotate|cut_nginx_logs'; echo '5 0 * * * /usr/local/sbin/lnmp-logrotate >/dev/null 2>&1') | crontab -
}

Add_LNMP_Startup()
{
    echo "Add Startup and Starting LNMP..."
    \cp ${cur_dir}/conf/lnmp /bin/lnmp
    chmod +x /bin/lnmp
    Install_BBR_Tool
    Install_Log_Rotation
    StartUp nginx
    StartOrStop start nginx
    if [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        StartUp mariadb
        StartOrStop start mariadb
        sed -i 's#/etc/init.d/mysql#/etc/init.d/mariadb#' /bin/lnmp
    elif [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        StartUp mysql
        StartOrStop start mysql
    elif [ "${DBSelect}" = "0" ]; then
        sed -i 's#/etc/init.d/mysql.*##' /bin/lnmp
    fi
    StartUp php-fpm
    StartOrStop start php-fpm
}

Check_Nginx_Files()
{
    isNginx=""
    echo "============================== Check install =============================="
    echo "Checking ..."
    if [[ -s /usr/local/nginx/conf/nginx.conf && -s /usr/local/nginx/sbin/nginx ]]; then
        Echo_Green "Nginx: OK"
        isNginx="ok"
    else
        Echo_Red "Error: Nginx install failed."
    fi
}

Check_DB_Files()
{
    isDB=""
    if [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        if [[ -s /usr/local/mariadb/bin/mysql && -s /usr/local/mariadb/bin/mysqld_safe && -s /etc/my.cnf ]]; then
            Echo_Green "MariaDB: OK"
            isDB="ok"
        else
            Echo_Red "Error: MariaDB install failed."
        fi
    elif [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        if [[ -s /usr/local/mysql/bin/mysql && -s /usr/local/mysql/bin/mysqld_safe && -s /etc/my.cnf ]]; then
            Echo_Green "MySQL: OK"
            isDB="ok"
        else
            Echo_Red "Error: MySQL install failed."
        fi
    elif [ "${DBSelect}" = "0" ]; then
        Echo_Green "Do not install MySQL/MariaDB."
        isDB="ok"
    fi
}

Check_PHP_Files()
{
    isPHP=""
    if [[ -s /usr/local/php/sbin/php-fpm && -s /usr/local/php/etc/php.ini && -s /usr/local/php/bin/php ]]; then
        Echo_Green "PHP: OK"
        Echo_Green "PHP-FPM: OK"
        isPHP="ok"
    else
        Echo_Red "Error: PHP install failed."
    fi
}

Clean_DB_Src_Dir()
{
    echo "Clean database src directory..."
    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        rm -rf -- "${cur_dir}/src/${Mysql_Ver}"
    elif [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        rm -rf -- "${cur_dir}/src/${Mariadb_Ver}"
    fi
    if [[ "${DBSelect}" = "4" ]]; then
        [[ -d "${cur_dir}/src/${Boost_Ver}" ]] && rm -rf -- "${cur_dir}/src/${Boost_Ver}"
    fi
}

Clean_PHP_Src_Dir()
{
    echo "Clean PHP src directory..."
    rm -rf -- "${cur_dir}/src/${Php_Ver}"
}

Clean_Web_Src_Dir()
{
    echo "Clean Web Server src directory..."
    rm -rf -- "${cur_dir}/src/${Nginx_Ver}"
    [[ -d "${cur_dir}/src/${Openssl_New_Ver}" ]] && rm -rf -- "${cur_dir}/src/${Openssl_New_Ver}"
    [[ -d "${cur_dir}/src/${Pcre_Ver}" ]] && rm -rf -- "${cur_dir}/src/${Pcre_Ver}"
    [[ -d "${cur_dir}/src/${LuaNginxModule}" ]] && rm -rf -- "${cur_dir}/src/${LuaNginxModule}"
    [[ -d "${cur_dir}/src/${NgxDevelKit}" ]] && rm -rf -- "${cur_dir}/src/${NgxDevelKit}"
    [[ -d "${cur_dir}/src/${NgxFancyIndex_Ver}" ]] && rm -rf -- "${cur_dir}/src/${NgxFancyIndex_Ver}"
}

Print_Sucess_Info()
{
    Clean_Web_Src_Dir
    echo "+------------------------------------------------------------------------+"
    echo "|          LNMP V${LNMP_Ver} for ${DISTRO} Linux Server, Written by Licess          |"
    echo "+------------------------------------------------------------------------+"
    echo "|              Independent hardened maintenance build                    |"
    echo "+------------------------------------------------------------------------+"
    echo "|    lnmp status manage: lnmp {start|stop|reload|restart|kill|status}    |"
    echo "+------------------------------------------------------------------------+"
    echo "|  phpMyAdmin path: /root/.lnmp-phpmyadmin-path (mode 600)               |"
    echo "|  Diagnostic PHP pages are disabled by default for security.            |"
    echo "+------------------------------------------------------------------------+"
    echo "|  Add VirtualHost: lnmp vhost add                                       |"
    echo "+------------------------------------------------------------------------+"
    echo "|  Default directory: ${Default_Website_Dir}                              |"
    if [ "${DBSelect}" != "0" ]; then
        echo "+------------------------------------------------------------------------+"
        if [ -s /root/.lnmp-db-root-password ]; then
            echo "|  Generated DB password: /root/.lnmp-db-root-password (mode 600)        |"
        else
            echo "|  Database root password is intentionally hidden from this log.         |"
        fi
    fi
    echo "+------------------------------------------------------------------------+"
    lnmp status
    if command -v ss >/dev/null 2>&1; then
        ss -ntl
    else
        netstat -ntl
    fi
    stop_time=$(date +%s)
    echo "Install lnmp takes $(((stop_time-start_time)/60)) minutes."
    Echo_Green "Install lnmp V${LNMP_Ver} completed! enjoy it."
}

Print_Failed_Info()
{
    if [ -s /bin/lnmp ]; then
        rm -f /bin/lnmp
    fi
    Echo_Red "Sorry, Failed to install LNMP!"
    Echo_Red "Review /root/lnmp-install.log for the failing command."
}

Check_LNMP_Install()
{
    Check_Nginx_Files
    Check_DB_Files
    Check_PHP_Files
    if [[ "${isNginx}" = "ok" && "${isDB}" = "ok" && "${isPHP}" = "ok" ]]; then
        Print_Sucess_Info
    else
        Print_Failed_Info
    fi
}
