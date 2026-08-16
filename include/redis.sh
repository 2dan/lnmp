#!/usr/bin/env bash

Install_Redis()
{
    local extension_backup='' redis_stage=''
    echo "====== Installing Redis ======"
    echo "Install ${Redis_Stable_Ver} Stable Version..."
    Press_Start

    Addons_Get_PHP_Ext_Dir
    zend_ext="${zend_ext_dir}redis.so"
    if [ -s "${zend_ext}" ]; then
        install -d -m 0700 /root/lnmp-backups
        extension_backup="/root/lnmp-backups/redis.so.$(date +%Y%m%d%H%M%S).$$"
        \cp -a "${zend_ext}" "${extension_backup}" || return 1
    fi
    cd "${cur_dir}/src" || return 1
    installed_redis_version=''
    [ -x /usr/local/redis/bin/redis-server ] && installed_redis_version=$(/usr/local/redis/bin/redis-server --version | sed -n 's/.*v=\([0-9.]*\).*/\1/p')
    if [ "redis-${installed_redis_version}" = "${Redis_Stable_Ver}" ]; then
        echo "${Redis_Stable_Ver} server is already installed."
    else
        if ! command -v gcc >/dev/null 2>&1; then
            Echo_Red "GCC is required to build Redis."
            return 1
        fi
        Redis_GCC_Major=$(gcc -dumpversion | cut -d. -f1)
        if [ "${Redis_GCC_Major}" -lt 8 ]; then
            Echo_Red "Redis ${Redis_Stable_Ver} requires a modern compiler; GCC 8 or newer is required by this build."
            return 1
        fi
        Download_Files "https://download.redis.io/releases/${Redis_Stable_Ver}.tar.gz" "${Redis_Stable_Ver}.tar.gz" || return 1
        Tar_Cd "${Redis_Stable_Ver}.tar.gz" "${Redis_Stable_Ver}" || return 1

        Get_OS_Bit
        if [ "${Is_ARM}" = "y" ]; then
            sed -i 's/FINAL_LIBS=-lm/FINAL_LIBS=-lm -latomic/' src/Makefile
        fi
        redis_stage="${cur_dir}/src/redis-stage.$$"
        rm -rf -- "${redis_stage}"
        if [[ "${Is_64bit}" = "y" || "${Is_ARM}" = "y" ]]; then
            make PREFIX="${redis_stage}" install || return 1
        else
            make CFLAGS="-march=i686" PREFIX="${redis_stage}" install || return 1
        fi
        "${redis_stage}/bin/redis-server" --version | grep -Fq "v=${Redis_Stable_Ver#redis-}" || {
            rm -rf -- "${redis_stage}"
            Echo_Red "The staged Redis binary failed its version check."
            return 1
        }
        [ -n "${installed_redis_version}" ] && /etc/init.d/redis stop 2>/dev/null || true
        install -d -m 0755 /usr/local/redis/bin
        install -m 0755 "${redis_stage}/bin/"* /usr/local/redis/bin/ || return 1
        rm -rf -- "${redis_stage}"
        getent group redis >/dev/null 2>&1 || groupadd --system redis
        id redis >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin --gid redis redis
        mkdir -p /usr/local/redis/etc /var/lib/redis /var/log/redis /run/redis
        chown redis:redis /var/lib/redis /var/log/redis /run/redis
        chmod 750 /var/lib/redis /var/log/redis /run/redis
        [ -f /usr/local/redis/etc/redis.conf ] || \cp redis.conf /usr/local/redis/etc/redis.conf
        sed -i 's/daemonize no/daemonize yes/g' /usr/local/redis/etc/redis.conf
        sed -i 's/^bind .*/bind 127.0.0.1 -::1/' /usr/local/redis/etc/redis.conf
        sed -i 's/^protected-mode .*/protected-mode yes/' /usr/local/redis/etc/redis.conf
        sed -i 's#^pidfile .*#pidfile /run/redis/redis.pid#' /usr/local/redis/etc/redis.conf
        sed -i 's#^dir .*#dir /var/lib/redis#' /usr/local/redis/etc/redis.conf
        sed -i 's#^logfile .*#logfile /var/log/redis/redis.log#' /usr/local/redis/etc/redis.conf
        chmod 640 /usr/local/redis/etc/redis.conf
        chown root:redis /usr/local/redis/etc/redis.conf
        cd ../
        rm -rf -- "${cur_dir}/src/${Redis_Stable_Ver}"

    fi

    if [ -d "${PHPRedis_Ver}" ]; then
        rm -rf -- "${PHPRedis_Ver}"
    fi

    Download_Files "https://pecl.php.net/get/${PHPRedis_Ver}.tgz" "${PHPRedis_Ver}.tgz" || return 1
    Tar_Cd "${PHPRedis_Ver}.tgz" "${PHPRedis_Ver}" || return 1
    "${PHP_Path}/bin/phpize" || return 1
    ./configure --with-php-config="${PHP_Path}/bin/php-config" || return 1
    if ! Make_Install; then
        [ -z "${extension_backup}" ] || \cp -a "${extension_backup}" "${zend_ext}"
        return 1
    fi
    [ -s "${zend_ext}" ] || { Echo_Red "phpredis shared library was not installed."; return 1; }
    "${PHP_Path}/bin/php" --no-php-ini -d "extension=${zend_ext}" -m | grep -Fxqi redis || {
        [ -z "${extension_backup}" ] || \cp -a "${extension_backup}" "${zend_ext}"
        Echo_Red "phpredis failed its PHP load test; the existing INI file was not changed."
        return 1
    }
    [ -z "${extension_backup}" ] || rm -f -- "${extension_backup}"
    cd "${cur_dir}/src" || return 1
    rm -rf -- "${PHPRedis_Ver}"

    cat >"${PHP_Path}/conf.d/007-redis.ini"<<EOF
extension = "redis.so"
EOF

    \cp ${cur_dir}/init.d/init.d.redis /etc/init.d/redis
    \cp ${cur_dir}/init.d/redis.service /etc/systemd/system/redis.service
    chmod +x /etc/init.d/redis
    echo "Add to auto startup..."
    StartUp redis
    Restart_PHP
    StartOrStop start redis

    if [ -s "${zend_ext}" ] && [ -s /usr/local/redis/bin/redis-server ] && \
       [ "$(/usr/local/redis/bin/redis-cli -h 127.0.0.1 ping 2>/dev/null)" = PONG ]; then
        Echo_Green "====== Redis install completed ======"
        Echo_Green "Redis installed successfully, enjoy it!"
    else
        Echo_Red "Redis install failed!"
        return 1
    fi
}

Uninstall_Redis()
{
    echo "You will uninstall Redis..."
    Press_Start
    rm -f -- "${PHP_Path}/conf.d/007-redis.ini"
    Restart_PHP
    Remove_StartUp redis
    echo "Delete Redis files..."
    rm -rf -- /usr/local/redis
    rm -f /etc/init.d/redis /etc/systemd/system/redis.service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport 6379 -j DROP >/dev/null 2>&1 && iptables -D INPUT -p tcp --dport 6379 -j DROP
        if [ "$PM" = "yum" ]; then
            service iptables save
            service iptables reload
        elif [ "$PM" = "apt" ]; then
            if [ -s /etc/init.d/netfilter-persistent ]; then
                /etc/init.d/netfilter-persistent save
                /etc/init.d/netfilter-persistent reload
            else
                /etc/init.d/iptables-persistent save
                /etc/init.d/iptables-persistent reload
            fi
        fi
    fi
    Echo_Green "Uninstall Redis completed."
}
