#!/usr/bin/env bash

# Unified PHP builder. This maintained branch intentionally supports only
# PHP 7.4.33 and newer; obsolete compatibility shims have been removed.

Check_PHP_Option()
{
    with_curl='--with-curl'
    with_openssl='--with-openssl'
    with_fileinfo='--enable-fileinfo'
    PHP_Buildin_Option=''
    [ "${Enable_PHP_Exif:-n}" = y ] && PHP_Buildin_Option+=" --enable-exif"
    [ "${Enable_PHP_Ldap:-n}" = y ] && PHP_Buildin_Option+=" --with-ldap"
    [ "${Enable_PHP_Bz2:-n}" = y ] && PHP_Buildin_Option+=" --with-bz2"
    [ "${Enable_PHP_Sodium:-n}" = y ] && PHP_Buildin_Option+=" --with-sodium"
}

Ln_PHP_Bin()
{
    ln -sf /usr/local/php/bin/php /usr/bin/php
    ln -sf /usr/local/php/bin/phpize /usr/bin/phpize
    [ -x /usr/local/php/bin/pear ] && ln -sf /usr/local/php/bin/pear /usr/bin/pear
    [ -x /usr/local/php/bin/pecl ] && ln -sf /usr/local/php/bin/pecl /usr/bin/pecl
    [ -x /usr/local/php/sbin/php-fpm ] && ln -sf /usr/local/php/sbin/php-fpm /usr/bin/php-fpm
}

Install_Composer()
{
    [ "${CheckMirror:-y}" = n ] && return 0
    local temp_dir installer signature expected actual status
    temp_dir=$(mktemp -d /tmp/lnmp-composer.XXXXXX) || return 1
    installer="${temp_dir}/composer-setup.php"
    signature="${temp_dir}/installer.sig"
    curl --fail --location --proto '=https' --proto-redir '=https' --max-redirs 5 --tlsv1.2 --connect-timeout 30 --max-time 120 \
        --output "${installer}" https://getcomposer.org/installer || { rm -rf -- "${temp_dir}"; return 1; }
    curl --fail --location --proto '=https' --proto-redir '=https' --max-redirs 5 --tlsv1.2 --connect-timeout 30 --max-time 30 \
        --output "${signature}" https://composer.github.io/installer.sig || { rm -rf -- "${temp_dir}"; return 1; }
    expected=$(tr -d '[:space:]' < "${signature}")
    actual=$(openssl dgst -sha384 "${installer}" | awk '{print $NF}')
    if [ -z "${expected}" ] || [ "${actual}" != "${expected}" ]; then
        rm -rf -- "${temp_dir}"
        Echo_Red "Composer installer signature verification failed."
        return 1
    fi
    /usr/local/php/bin/php "${installer}" --install-dir=/usr/local/bin --filename=composer
    status=$?
    rm -rf -- "${temp_dir}"
    return "${status}"
}

Configure_PHP_Runtime()
{
    install -d -m 0755 /usr/local/php/etc /usr/local/php/conf.d
    install -d -m 0750 -o www -g www /usr/local/php/var/log /usr/local/php/var/run
    \cp php.ini-production /usr/local/php/etc/php.ini
    sed -i 's/post_max_size =.*/post_max_size = 64M/' /usr/local/php/etc/php.ini
    sed -i 's/upload_max_filesize =.*/upload_max_filesize = 64M/' /usr/local/php/etc/php.ini
    sed -i 's/;date.timezone =.*/date.timezone = Asia\/Shanghai/' /usr/local/php/etc/php.ini
    sed -i 's/short_open_tag =.*/short_open_tag = Off/' /usr/local/php/etc/php.ini
    sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' /usr/local/php/etc/php.ini
    sed -i 's/max_execution_time =.*/max_execution_time = 120/' /usr/local/php/etc/php.ini
    sed -i 's/expose_php =.*/expose_php = Off/' /usr/local/php/etc/php.ini
    sed -i 's/log_errors =.*/log_errors = On/' /usr/local/php/etc/php.ini
    if grep -q '^;error_log =' /usr/local/php/etc/php.ini; then
        sed -i 's#^;error_log =.*#error_log = /usr/local/php/var/log/php-error.log#' /usr/local/php/etc/php.ini
    else
        printf '\nerror_log = /usr/local/php/var/log/php-error.log\n' >> /usr/local/php/etc/php.ini
    fi
    sed -i 's/session.cookie_httponly =.*/session.cookie_httponly = 1/' /usr/local/php/etc/php.ini
    sed -i 's/session.use_strict_mode =.*/session.use_strict_mode = 1/' /usr/local/php/etc/php.ini
    sed -i 's/^;session.cookie_samesite.*/session.cookie_samesite = Lax/' /usr/local/php/etc/php.ini
    cat >/usr/local/php/conf.d/010-opcache.ini <<'EOF'
[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
EOF
}

Configure_PHP_FPM()
{
    cat >/usr/local/php/etc/php-fpm.conf <<'EOF'
[global]
pid = /usr/local/php/var/run/php-fpm.pid
error_log = /usr/local/php/var/log/php-fpm.log
log_level = notice
emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s

[www]
listen = /usr/local/php/var/run/php-fpm.sock
listen.backlog = 1024
listen.owner = www
listen.group = www
listen.mode = 0660
user = www
group = www
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
pm.max_requests = 1000
request_terminate_timeout = 120s
request_slowlog_timeout = 5s
slowlog = /usr/local/php/var/log/slow.log
catch_workers_output = yes
clear_env = yes
security.limit_extensions = .php
EOF
    \cp "${cur_dir}/src/${Php_Ver}/sapi/fpm/init.d.php-fpm" /etc/init.d/php-fpm
    \cp "${cur_dir}/init.d/php-fpm.service" /etc/systemd/system/php-fpm.service
    chmod 0755 /etc/init.d/php-fpm
}

Install_PHP_Supported()
{
    local php_version=${Php_Ver#php-} sapi_option curl_option='--with-curl'
    local configure_env=()
    if [ "$(printf '%s\n' "${php_version}" 7.4.33 | sort -V | head -n1)" != 7.4.33 ]; then
        Echo_Red "PHP ${php_version} is below the supported floor 7.4.33."
        return 1
    fi
    if [[ "${php_version}" == 7.4.* || "${php_version}" == 8.0.* ]]; then
        Install_Legacy_PHP_Curl || return 1
        curl_option='--with-curl=/usr/local/curl-legacy'
        configure_env=(env
            "PKG_CONFIG_PATH=/usr/local/curl-legacy/lib/pkgconfig:/usr/local/openssl-1.1/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
            'CPPFLAGS=-I/usr/local/curl-legacy/include -I/usr/local/openssl-1.1/include'
            'LDFLAGS=-L/usr/local/curl-legacy/lib -L/usr/local/openssl-1.1/lib -Wl,-rpath,/usr/local/curl-legacy/lib -Wl,-rpath,/usr/local/openssl-1.1/lib')
    fi
    Install_Libzip
    Echo_Blue "[+] Installing ${Php_Ver}"
    Tar_Cd "${Php_Ver}.tar.bz2" "${Php_Ver}" || return 1
    sapi_option='--enable-fpm --with-fpm-user=www --with-fpm-group=www'
    # shellcheck disable=SC2086
    "${configure_env[@]}" ./configure --prefix=/usr/local/php \
        --with-config-file-path=/usr/local/php/etc \
        --with-config-file-scan-dir=/usr/local/php/conf.d \
        ${sapi_option} --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-iconv=/usr/local --with-freetype=/usr/local/freetype --with-jpeg --with-webp \
        --with-zlib --enable-xml --disable-rpath --enable-bcmath --enable-shmop --enable-sysvsem \
        ${curl_option} --enable-mbregex --enable-mbstring --enable-intl --enable-pcntl --enable-ftp \
        --enable-gd --with-openssl --enable-sockets --with-zip --enable-soap --with-gettext \
        --enable-fileinfo --enable-opcache --with-xsl ${PHP_Buildin_Option} ${PHP_Modules_Options} || return 1
    PHP_Make_Install || return 1
    Ln_PHP_Bin
    Configure_PHP_Runtime
    Configure_PHP_FPM
    Install_Composer || Echo_Yellow "Composer installation skipped or failed; PHP itself is installed."
}

Install_PHP_74() { Install_PHP_Supported; }
Install_PHP_80() { Install_PHP_Supported; }
Install_PHP_81() { Install_PHP_Supported; }
Install_PHP_82() { Install_PHP_Supported; }
Install_PHP_83() { Install_PHP_Supported; }
Install_PHP_84() { Install_PHP_Supported; }
Install_PHP_85() { Install_PHP_Supported; }

LNMP_PHP_Opt()
{
    if declare -F Tune_PHP_FPM >/dev/null 2>&1; then
        Tune_PHP_FPM /usr/local/php
    fi
}

Creat_PHP_Tools()
{
    echo "Creating hardened default website..."
    rm -f "${Default_Website_Dir}/phpinfo.php" "${Default_Website_Dir}/p.php" "${Default_Website_Dir}/ocp.php"
    \cp "${cur_dir}/conf/index.html" "${Default_Website_Dir}/index.html"
    \cp "${cur_dir}/conf/lnmp.gif" "${Default_Website_Dir}/lnmp.gif"
    Tar_Cd "${PhpMyAdmin_Ver}.tar.xz" "${PhpMyAdmin_Ver}" || return 1
    cd "${cur_dir}/src" || return 1
    local pma_name pma_dir pma_blowfish
    pma_name="pma_$(openssl rand -hex 8)" || return 1
    [[ "${pma_name}" =~ ^pma_[0-9a-f]{16}$ ]] || return 1
    pma_dir="${Default_Website_Dir}/${pma_name}"
    mv "${PhpMyAdmin_Ver}" "${pma_dir}"
    \cp "${cur_dir}/conf/config.inc.php" "${pma_dir}/config.inc.php"
    pma_blowfish=$(openssl rand -hex 32) || return 1
    [[ "${pma_blowfish}" =~ ^[0-9a-f]{64}$ ]] || return 1
    sed -i "s/__LNMP_GENERATED_BLOWFISH_SECRET__/${pma_blowfish}/g" "${pma_dir}/config.inc.php" || return 1
    grep -Fq "${pma_blowfish}" "${pma_dir}/config.inc.php" || return 1
    install -d -o www -g www -m 0700 /var/lib/phpmyadmin/tmp
    chown -R root:www "${pma_dir}"
    find "${pma_dir}" -type d -exec chmod 0750 {} \;
    find "${pma_dir}" -type f -exec chmod 0640 {} \;
    umask 077
    printf '/%s/\n' "${pma_name}" > /root/.lnmp-phpmyadmin-path
}
