#!/usr/bin/env bash

Install_Multiplephp()
{
    local choice php_version php_short prefix service_file systemd_file curl_option='--with-curl'
    local configure_env=()
    echo "Supported additional PHP versions:"
    echo "1: 7.4.33  2: 8.0.30  3: 8.1.34  4: 8.2.33"
    echo "5: 8.3.33  6: 8.4.24  7: 8.5.9"
    read -r -p "Choice (1-7): " choice
    case "${choice}" in
        1) php_version=7.4.33 ;;
        2) php_version=8.0.30 ;;
        3) php_version=8.1.34 ;;
        4) php_version=8.2.33 ;;
        5) php_version=8.3.33 ;;
        6) php_version=8.4.24 ;;
        7) php_version=8.5.9 ;;
        *) Echo_Red "Unsupported PHP selection."; return 1 ;;
    esac
    php_short=${php_version%.*}
    prefix="/usr/local/php${php_short}"
    Php_Ver="php-${php_version}"
    if [[ "${php_version}" == 7.4.* || "${php_version}" == 8.0.* ]]; then
        Install_Legacy_PHP_Curl || return 1
        curl_option='--with-curl=/usr/local/curl-legacy'
        configure_env=(env
            "PKG_CONFIG_PATH=/usr/local/curl-legacy/lib/pkgconfig:/usr/local/openssl-1.1/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
            'CPPFLAGS=-I/usr/local/curl-legacy/include -I/usr/local/openssl-1.1/include'
            'LDFLAGS=-L/usr/local/curl-legacy/lib -L/usr/local/openssl-1.1/lib -Wl,-rpath,/usr/local/curl-legacy/lib -Wl,-rpath,/usr/local/openssl-1.1/lib')
    fi

    cd "${cur_dir}/src" || return 1
    Download_Files "https://www.php.net/distributions/${Php_Ver}.tar.bz2" "${Php_Ver}.tar.bz2" || return 1
    Install_Libzip
    Tar_Cd "${Php_Ver}.tar.bz2" "${Php_Ver}" || return 1
    if [ -d "${prefix}/etc" ]; then
        install -d -m 0700 /root/lnmp-backup
        tar -czf "/root/lnmp-backup/php${php_short}-config-$(date +%Y%m%d%H%M%S).tar.gz" -C "${prefix}" etc
    fi
    # shellcheck disable=SC2086
    "${configure_env[@]}" ./configure --prefix="${prefix}" --with-config-file-path="${prefix}/etc" \
        --with-config-file-scan-dir="${prefix}/conf.d" --enable-fpm --with-fpm-user=www --with-fpm-group=www \
        --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-iconv=/usr/local \
        --with-freetype=/usr/local/freetype --with-jpeg --with-webp --with-zlib --enable-xml \
        --disable-rpath --enable-bcmath --enable-shmop --enable-sysvsem ${curl_option} --enable-mbregex \
        --enable-mbstring --enable-intl --enable-pcntl --enable-ftp --enable-gd --with-openssl \
        --enable-sockets --with-zip --enable-soap --with-gettext --enable-fileinfo --enable-opcache \
        --with-xsl ${PHP_Modules_Options} || return 1
    PHP_Make_Install || return 1

    install -d -m 0755 "${prefix}/etc" "${prefix}/conf.d"
    install -d -m 0750 -o www -g www "${prefix}/var/log" "${prefix}/var/run"
    \cp php.ini-production "${prefix}/etc/php.ini"
    sed -i 's/short_open_tag =.*/short_open_tag = Off/' "${prefix}/etc/php.ini"
    sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "${prefix}/etc/php.ini"
    sed -i 's/expose_php =.*/expose_php = Off/' "${prefix}/etc/php.ini"
    printf '\nerror_log = %s/var/log/php-error.log\n' "${prefix}" >> "${prefix}/etc/php.ini"
    cat >"${prefix}/etc/php-fpm.conf" <<EOF
[global]
pid = ${prefix}/var/run/php-fpm.pid
error_log = ${prefix}/var/log/php-fpm.log
log_level = notice

[www]
listen = /usr/local/php${php_short}/var/run/php-fpm.sock
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
slowlog = ${prefix}/var/log/slow.log
clear_env = yes
security.limit_extensions = .php
EOF
    cat >"/usr/local/nginx/conf/enable-php${php_short}.conf" <<EOF
location ~ [^/]\.php(/|$)
{
    try_files \$uri =404;
    fastcgi_pass unix:/usr/local/php${php_short}/var/run/php-fpm.sock;
    fastcgi_index index.php;
    include fastcgi.conf;
}
EOF
    service_file="/etc/init.d/php-fpm${php_short}"
    \cp "${cur_dir}/src/${Php_Ver}/sapi/fpm/init.d.php-fpm" "${service_file}"
    chmod 0755 "${service_file}"
    systemd_file="/etc/systemd/system/php-fpm${php_short}.service"
    sed "s#/usr/local/php#${prefix}#g; s#php-fpm.service#php-fpm${php_short}.service#g" \
        "${cur_dir}/init.d/php-fpm.service" > "${systemd_file}"
    if declare -F Tune_PHP_FPM >/dev/null 2>&1; then Tune_PHP_FPM "${prefix}"; fi
    systemctl daemon-reload 2>/dev/null || true
    StartUp "php-fpm${php_short}"
    StartOrStop restart "php-fpm${php_short}"
    Echo_Green "PHP ${php_version} installed at ${prefix}."
}
