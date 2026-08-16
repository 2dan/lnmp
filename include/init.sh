#!/usr/bin/env bash

Set_Timezone()
{
    Echo_Blue "Setting timezone..."
    rm -f -- /etc/localtime
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

CentOS_InstallNTP()
{
    if [ "${CheckMirror}" != "n" ]; then
        if command -v ntpdate >/dev/null 2>&1; then
            ntpdate -u pool.ntp.org
        elif command -v chronyd >/dev/null 2>&1; then
            chronyd -d -q "server pool.ntp.org iburst"
        else
            yum info ntpdate && check_ntp="y"
            if [ "${check_ntp}" = "y" ]; then
                Echo_Blue "[+] Installing ntp..."
                yum install -y ntpdate
                ntpdate -u pool.ntp.org
            else
                Echo_Blue "[+] Installing chrony..."
                yum install chrony -y
                chronyd -d -q "server pool.ntp.org iburst"
            fi
        fi
    fi
    date
    start_time=$(date +%s)
}

Deb_InstallNTP()
{
    if [ "${CheckMirror}" != "n" ]; then
        apt-get update -y
        [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
        Echo_Blue "[+] Installing ntp..."
        apt-get install -y ntpdate
        ntpdate -u pool.ntp.org
    fi
    date
    start_time=$(date +%s)
}

CentOS_Remove_Conflicting_Packages()
{
    Echo_Blue "[-] Yum remove packages..."
    if [[ "${DBSelect}" != "0" ]]; then
        yum -y remove mysql-server mysql mysql-libs mariadb-server mariadb mariadb-libs
        rpm -qa|grep mysql
        if [ $? -ne 0 ]; then
            rpm -e mysql mysql-libs --nodeps
            rpm -e mariadb mariadb-libs --nodeps
        fi
    fi
    rpm -qa|grep php
    rpm -e php-mysql php-cli php-gd php-common php --nodeps

    Remove_Error_Libcurl

    yum -y remove php*
    yum clean all
}

Deb_Remove_Conflicting_Packages()
{
    local mysql_conf_backup
    Echo_Blue "[-] apt-get remove packages..."
    apt-get update -y
    [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
    for removepackages in php5 php5-common php5-cgi php5-cli php5-mysql php5-curl php5-gd;
    do apt-get purge -y $removepackages; done
    if [[ "${DBSelect}" != "0" ]]; then
        if echo "${Ubuntu_Version}" | grep -Eqi "^2[0-7]\."; then
            dpkg -l |grep mysql
            dpkg --force-all -P mysql-server
            dpkg --force-all -P mariadb-client mariadb-server mariadb-common libmariadbd-dev
            if [ -d /etc/mysql ]; then
                mysql_conf_backup="/root/lnmp-backups/etc-mysql-$(date +%Y%m%d-%H%M%S)"
                install -d -m 0700 /root/lnmp-backups
                mv -- /etc/mysql "${mysql_conf_backup}" || {
                    Echo_Red "Unable to preserve /etc/mysql; refusing to remove the existing database packages."
                    return 1
                }
                Echo_Yellow "Existing database configuration preserved at ${mysql_conf_backup}."
            fi
            for removepackages in mysql-server mariadb-server;
            do apt-get purge -y $removepackages; done
        else
            dpkg -l |grep mysql
            dpkg --force-all -P mysql-server mysql-common libmysqlclient15off libmysqlclient15-dev libmysqlclient18 libmysqlclient18-dev libmysqlclient20 libmysqlclient-dev libmysqlclient21
            dpkg --force-all -P mariadb-client mariadb-server mariadb-common libmariadbd-dev
            for removepackages in mysql-client mysql-server mysql-common mariadb-client mariadb-server mariadb-common;
            do apt-get purge -y $removepackages; done
        fi
    fi
    dpkg -l |grep php
    dpkg -P php5 php5-common php5-cli php5-cgi php5-mysql php5-curl php5-gd
    apt-get autoremove -y && apt-get clean
}

Disable_Selinux()
{
    if command -v getenforce >/dev/null 2>&1; then
        selinux_mode=$(getenforce 2>/dev/null)
        if [ "${selinux_mode}" != "Disabled" ]; then
            Echo_Yellow "SELinux is ${selinux_mode}; the installer will not disable this host security control."
        fi
    fi
}

Xen_Hwcap_Setting()
{
    if [ -s /etc/ld.so.conf.d/libc6-xen.conf ]; then
        sed -i 's/hwcap 1 nosegneg/hwcap 0 nosegneg/g' /etc/ld.so.conf.d/libc6-xen.conf
    fi
}

Check_Hosts()
{
    if grep -Eqi '^127.0.0.1[[:space:]]*localhost' /etc/hosts; then
        echo "Hosts: ok."
    else
        echo "127.0.0.1 localhost.localdomain localhost" >> /etc/hosts
    fi
    if [ "${CheckMirror}" != "n" ]; then
        if ! getent ahosts nginx.org >/dev/null 2>&1; then
            echo "DNS resolution...fail"
            Echo_Red "DNS resolution failed. The installer will not overwrite /etc/resolv.conf; fix the host DNS configuration and retry."
            return 1
        else
            echo "DNS resolution...ok"
        fi
    fi
}

RHEL_Modify_Source()
{
    Get_RHEL_Version
    echo "Keeping the administrator-configured RHEL repositories; cross-distribution repository replacement is disabled."
}

Ubuntu_Modify_Source()
{
    echo "Keeping the administrator-configured Ubuntu repositories; EOL archive substitution is disabled."
}

CentOS6_Modify_Source()
{
    if echo "${CentOS_Version}" | grep -Eqi "^[4-7]"; then
        Echo_Red "This CentOS release is end of life and is not supported by this hardened build."
        exit 1
    fi
}

CentOS8_Modify_Source()
{
    if echo "${CentOS_Version}" | grep -Eqi "^8" && [ "${isCentosStream}" != "y" ]; then
        Echo_Red "CentOS Linux 8 is end of life and is not supported by this hardened build. Use CentOS Stream, AlmaLinux or Rocky Linux."
        exit 1
    fi
}

Modify_Source()
{
    if [ "${DISTRO}" = "RHEL" ]; then
        if subscription-manager status; then
            Echo_Blue "RHEL subscription exists on the system, skip setting up third-party sources."
            Get_RHEL_Version
            if echo "${RHEL_Version}" | grep -Eqi "^[89]|^10"; then
                subscription-manager repos --enable codeready-builder-for-rhel-${RHEL_Version}-${DB_ARCH}-rpms
            fi
        else
            RHEL_Modify_Source
        fi
    elif [ "${DISTRO}" = "Ubuntu" ]; then
        Ubuntu_Modify_Source
    elif [ "${DISTRO}" = "CentOS" ]; then
        CentOS6_Modify_Source
        CentOS8_Modify_Source
    fi
}

Check_PowerTools()
{
    if ! yum -v repolist all|grep "PowerTools"; then
        Echo_Red "PowerTools repository not found!"
    fi
    repo_id=$(yum repolist all|grep -Ei "PowerTools"|head -n 1|awk '{print $1}')
}

Check_Codeready()
{
    repo_id=$(yum repolist all|grep -E "CodeReady"|head -n 1|awk '{print $1}')
    [ -z "${repo_id}" ] && repo_id="ol8_codeready_builder"
}

CentOS_Dependent()
{
    Echo_Blue "[+] Yum installing dependent packages..."
    for packages in make cmake gcc gcc-c++ gcc-g77 kernel-headers glibc-headers flex bison file libtool libtool-libs autoconf patch wget crontabs libjpeg libjpeg-devel libjpeg-turbo-devel libpng libpng-devel libpng10 libpng10-devel gd gd-devel libxml2 libxml2-devel zlib zlib-devel glib2 glib2-devel unzip tar bzip2 bzip2-devel libzip-devel libevent libevent-devel ncurses ncurses-devel curl curl-devel libcurl libcurl-devel e2fsprogs e2fsprogs-devel krb5 krb5-devel libidn libidn-devel openssl openssl-devel pcre-devel pcre2-devel gettext gettext-devel ncurses-devel gmp-devel pspell-devel unzip libcap diffutils ca-certificates net-tools libc-client-devel psmisc libXpm-devel git-core c-ares-devel libicu-devel libxslt libxslt-devel xz expat-devel libaio-devel rpcgen libtirpc-devel perl cyrus-sasl-devel sqlite-devel oniguruma-devel lsof re2c pkg-config libarchive hostname ncurses-libs numactl-devel libxcrypt libwebp-devel gnutls-devel initscripts iproute libxcrypt-compat git;
    do yum -y install $packages; done

    yum -y update nss

    if echo "${CentOS_Version}" | grep -Eqi "^8" || echo "${RHEL_Version}" | grep -Eqi "^8" || echo "${Rocky_Version}" | grep -Eqi "^8" || echo "${Alma_Version}" | grep -Eqi "^8" || echo "${Anolis_Version}" | grep -Eqi "^8" || echo "${OpenCloudOS_Version}" | grep -Eqi "^8"; then
        Check_PowerTools
        if [ "${repo_id}" != "" ]; then
            echo "Installing packages in PowerTools repository..."
            for c8packages in rpcgen re2c oniguruma-devel;
            do dnf --enablerepo=${repo_id} install ${c8packages} -y; done
        fi
        dnf install libarchive -y

        dnf install gcc-toolset-10 -y
    fi

    if echo "${CentOS_Version} ${Alma_Version} ${Rocky_Version}" | grep -Eqi '(^|[[:space:]])(9|10)([.]|[[:space:]]|$)'; then
        dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
        if dnf repolist --enabled | grep -Eqi '^crb([[:space:]]|$)'; then
            for crb_package in oniguruma-devel libzip-devel libtirpc-devel libxcrypt-compat;
            do dnf --enablerepo=crb install "${crb_package}" -y; done
        else
            Echo_Yellow "CRB is not enabled; enable the distribution-provided CRB repository if a development package is unavailable."
        fi
        if [[ "${Bin}" != "y" && "${DBSelect}" = "5" ]]; then
            dnf install gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils gcc-toolset-12-annobin-annocheck gcc-toolset-12-annobin-plugin-gcc -y
        fi
    fi

    if [ "${DISTRO}" = "Oracle" ] && echo "${Oracle_Version}" | grep -Eqi "^8"; then
        Check_Codeready
        for o8packages in rpcgen re2c oniguruma-devel;
        do dnf --enablerepo=${repo_id} install ${o8packages} -y; done
        dnf install libarchive -y
    fi

    if [ "${DISTRO}" = "Oracle" ] && echo "${Oracle_Version}" | grep -Eqi "^9"; then
        Check_Codeready
        dnf --enablerepo=${repo_id} install libtirpc-devel -y
        if [[ "${Bin}" != "y" && "${DBSelect}" = "5" ]]; then
            dnf install gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils gcc-toolset-12-annobin-annocheck gcc-toolset-12-annobin-plugin-gcc -y
        fi
    fi

    if echo "${CentOS_Version}" | grep -Eqi "^7" || echo "${RHEL_Version}" | grep -Eqi "^7"  || echo "${Aliyun_Version}" | grep -Eqi "^2" || echo "${Alibaba_Version}" | grep -Eqi "^2" || echo "${Oracle_Version}" | grep -Eqi "^7" || echo "${Anolis_Version}" | grep -Eqi "^7"; then
        if [ "${DISTRO}" = "Oracle" ]; then
            yum -y install oracle-epel-release
            yum -y --enablerepo=*EPEL* install oniguruma-devel
        else
            yum -y install epel-release
        fi
        yum -y install oniguruma oniguruma-devel
        if [ "${CheckMirror}" = "n" ]; then
            rpm -ivh ${cur_dir}/src/oniguruma-6.8.2-2.el7.x86_64.rpm ${cur_dir}/src/oniguruma-devel-6.8.2-2.el7.x86_64.rpm
        fi
    fi

    if [ "${DISTRO}" = "Fedora" ] || echo "${CentOS_Version}" | grep -Eqi "^9" || echo "${Alma_Version}" | grep -Eqi "^9" || echo "${Rocky_Version}" | grep -Eqi "^9" || echo "${Amazon_Version}" | grep -Eqi "^202[3-9]" || echo "${OpenCloudOS_Version}" | grep -Eqi "^9"; then
        dnf install chkconfig -y
    fi

    if [ "${DISTRO}" = "UOS" ]; then
        Check_PowerTools
        if [ "${repo_id}" != "" ]; then
            echo "Installing packages in PowerTools repository..."
            for uospackages in rpcgen re2c oniguruma-devel;
            do dnf --enablerepo=${repo_id} install ${uospackages} -y; done
        fi
    fi

}

Deb_Dependent()
{
    local packages
    packages=(
        debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf automake re2c
        wget cron bzip2 xz-utils gzip unzip tar file flex bison m4 gawk binutils diffutils patch git
        pkg-config ca-certificates psmisc lsof iproute2 e2fsprogs
        libc6-dev libbz2-dev libncurses-dev libtool libltdl-dev libevent-dev libssl-dev zlib1g-dev
        libsasl2-dev libglib2.0-dev libjpeg-dev libpng-dev libwebp-dev libxpm-dev libkrb5-dev
        libcurl4-openssl-dev libpcre2-dev libpq-dev libxml2-dev libxslt1-dev libcap-dev
        libc-ares-dev libicu-dev libexpat1-dev libaio-dev libtirpc-dev rpcsvc-proto
        libsqlite3-dev libonig-dev libtinfo-dev libnuma-dev libgnutls28-dev libzip-dev
        libgmp-dev libsodium-dev libldap2-dev libreadline-dev libsystemd-dev liblz4-dev libzstd-dev
    )
    Echo_Blue "[+] Apt-get installing dependent packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || apt-get update --allow-releaseinfo-change || return 1
    apt-get -fy install || return 1
    apt-get --no-install-recommends install -y "${packages[@]}" || return 1
    if [ "${Enable_PHP_Imap:-n}" = y ]; then
        apt-get --no-install-recommends install -y libc-client-dev || {
            Echo_Red "The distribution does not provide libc-client-dev required by the selected legacy IMAP build."
            return 1
        }
    fi
}

Check_Download()
{
    Echo_Blue "[+] Downloading files..."
    cd "${cur_dir}/src" || return 1
    Download_Files "https://ftp.gnu.org/gnu/libiconv/${Libiconv_Ver}.tar.gz" "${Libiconv_Ver}.tar.gz" || return 1
    Download_Files "https://nginx.org/download/${Nginx_Ver}.tar.gz" "${Nginx_Ver}.tar.gz" || return 1
    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        Mysql_Ver_Short=${Mysql_Ver#mysql-}
        Mysql_Ver_Short=${Mysql_Ver_Short%.*}
        if [[ "${Bin}" = y && "${DBSelect}" = 4 ]]; then
            local mysql_archive="${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz"
            Download_Files "https://cdn.mysql.com/Downloads/MySQL-${Mysql_Ver_Short}/${mysql_archive}" "${mysql_archive}" ||
                Download_Files "https://cdn.mysql.com/archives/mysql-${Mysql_Ver_Short}/${mysql_archive}" "${mysql_archive}" || return 1
        elif [[ "${Bin}" = "y" && "${DBSelect}" = "5" ]]; then
            local mysql_archive="${Mysql_Ver}-linux-glibc2.28-${DB_ARCH}.tar.xz"
            Download_Files "https://cdn.mysql.com/Downloads/MySQL-8.0/${mysql_archive}" "${mysql_archive}" ||
                Download_Files "https://cdn.mysql.com/archives/mysql-8.0/${mysql_archive}" "${mysql_archive}" || return 1
        elif [[ "${Bin}" = "y" && "${DBSelect}" = "6" ]]; then
            local mysql_archive="${Mysql_Ver}-linux-glibc2.28-${DB_ARCH}.tar.xz"
            Download_Files "https://cdn.mysql.com/Downloads/MySQL-8.4/${mysql_archive}" "${mysql_archive}" ||
                Download_Files "https://cdn.mysql.com/archives/mysql-8.4/${mysql_archive}" "${mysql_archive}" || return 1
        elif [[ "${Bin}" = "y" && "${DBSelect}" = "7" ]]; then
            local mysql_archive="${Mysql_Ver}-linux-glibc2.28-${DB_ARCH}.tar.xz"
            Download_Files "https://cdn.mysql.com/Downloads/MySQL-9.7/${mysql_archive}" "${mysql_archive}" ||
                Download_Files "https://cdn.mysql.com/archives/mysql-9.7/${mysql_archive}" "${mysql_archive}" || return 1
        else
            local mysql_archive="${Mysql_Ver}.tar.gz"
            Download_Files "https://cdn.mysql.com/Downloads/MySQL-${Mysql_Ver_Short}/${mysql_archive}" "${mysql_archive}" ||
                Download_Files "https://cdn.mysql.com/archives/mysql-${Mysql_Ver_Short}/${mysql_archive}" "${mysql_archive}" || return 1
        fi
    elif [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        if [ "${Bin}" = "y" ]; then
            MariaDB_FileName="${Mariadb_Ver}-linux-systemd-${DB_ARCH}"
            Download_Files "https://archive.mariadb.org/${Mariadb_Ver}/bintar-linux-systemd-x86_64/${MariaDB_FileName}.tar.gz" "${MariaDB_FileName}.tar.gz" || return 1
        else
            Download_Files "https://archive.mariadb.org/${Mariadb_Ver}/source/${Mariadb_Ver}.tar.gz" "${Mariadb_Ver}.tar.gz" || return 1
        fi
    fi
    Download_Files "https://www.php.net/distributions/${Php_Ver}.tar.bz2" "${Php_Ver}.tar.bz2" || return 1
    PhpMyAdmin_Ver_Short=$(printf '%s' "${PhpMyAdmin_Ver}" | cut -d- -f2)
    Download_Files "https://files.phpmyadmin.net/phpMyAdmin/${PhpMyAdmin_Ver_Short}/${PhpMyAdmin_Ver}.tar.xz" "${PhpMyAdmin_Ver}.tar.xz" || return 1
}

Make_Install()
{
    make -j `grep 'processor' /proc/cpuinfo | wc -l`
    if [ $? -ne 0 ]; then
        make
    fi
    make install
}

PHP_Make_Install()
{
    make ZEND_EXTRA_LIBS='-liconv' -j `grep 'processor' /proc/cpuinfo | wc -l`
    if [ $? -ne 0 ]; then
        make ZEND_EXTRA_LIBS='-liconv'
    fi
    make install
}

Install_Libiconv()
{
    Echo_Blue "[+] Installing ${Libiconv_Ver}"
    Tar_Cd ${Libiconv_Ver}.tar.gz ${Libiconv_Ver}
    ./configure --enable-static
    Make_Install
    cd "${cur_dir}/src/" || return 1
    rm -rf -- "${cur_dir}/src/${Libiconv_Ver}"
}

Install_Legacy_OpenSSL()
{
    local prefix=/usr/local/openssl-1.1
    if [ -x "${prefix}/bin/openssl" ] && "${prefix}/bin/openssl" version | grep -Fq 'OpenSSL 1.1.1w'; then
        return 0
    fi
    Echo_Yellow "Installing isolated OpenSSL 1.1.1w for EOL PHP 7.4/8.0 or MySQL 5.7 source compatibility only."
    cd "${cur_dir}/src" || return 1
    Download_Files "https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/${Openssl_Legacy_PHP_Ver}.tar.gz" "${Openssl_Legacy_PHP_Ver}.tar.gz" || return 1
    Tar_Cd "${Openssl_Legacy_PHP_Ver}.tar.gz" "${Openssl_Legacy_PHP_Ver}" || return 1
    ./config --prefix="${prefix}" --openssldir="${prefix}/ssl" --libdir=lib shared zlib || return 1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" || return 1
    make install_sw || return 1
    cd "${cur_dir}/src" || return 1
    rm -rf -- "${cur_dir}/src/${Openssl_Legacy_PHP_Ver}"
}

Install_Legacy_PHP_Curl()
{
    local prefix=/usr/local/curl-legacy openssl_prefix=/usr/local/openssl-1.1
    if [ -x "${prefix}/bin/curl" ] && "${prefix}/bin/curl" --version | head -n1 | grep -Fq '8.21.0'; then
        return 0
    fi
    Install_Legacy_OpenSSL || return 1
    Echo_Yellow "Installing isolated curl 8.21.0 for EOL PHP 7.4/8.0 compatibility."
    cd "${cur_dir}/src" || return 1
    Download_Files "https://curl.se/download/${Curl_Legacy_PHP_Ver}.tar.xz" "${Curl_Legacy_PHP_Ver}.tar.xz" || return 1
    Tar_Cd "${Curl_Legacy_PHP_Ver}.tar.xz" "${Curl_Legacy_PHP_Ver}" || return 1
    PKG_CONFIG_PATH="${openssl_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    CPPFLAGS="-I${openssl_prefix}/include" \
    LDFLAGS="-L${openssl_prefix}/lib -Wl,-rpath,${openssl_prefix}/lib" \
        ./configure --prefix="${prefix}" --with-openssl="${openssl_prefix}" --with-zlib \
        --disable-static --enable-shared --disable-ldap --disable-ldaps --without-libpsl --without-libssh2 || return 1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" || return 1
    make install || return 1
    cd "${cur_dir}/src" || return 1
    rm -rf -- "${cur_dir}/src/${Curl_Legacy_PHP_Ver}"
}

Install_Freetype()
{
    Download_Files https://download.savannah.gnu.org/releases/freetype/${Freetype_New_Ver}.tar.xz ${Freetype_New_Ver}.tar.xz
    Echo_Blue "[+] Installing ${Freetype_New_Ver}"
    Tar_Cd ${Freetype_New_Ver}.tar.xz ${Freetype_New_Ver}
    ./configure --prefix=/usr/local/freetype --enable-freetype-config
    Make_Install

    [[ -d /usr/lib/pkgconfig ]] && \cp /usr/local/freetype/lib/pkgconfig/freetype2.pc /usr/lib/pkgconfig/
    cat > /etc/ld.so.conf.d/freetype.conf<<EOF
/usr/local/freetype/lib
EOF
    ldconfig
    ln -sf /usr/local/freetype/include/freetype2/* /usr/include/
    cd "${cur_dir}/src/" || return 1
    rm -rf -- "${cur_dir}/src/${Freetype_New_Ver}"
}

Install_Pcre()
{
    if command -v pcre2-config >/dev/null 2>&1 && pcre2-config --version | grep -Eqi '^10\.'; then
        Nginx_With_Pcre="--with-pcre-jit"
    else
        Echo_Blue "[+] Installing ${Pcre_Ver}"
        cd "${cur_dir}/src" || return 1
        Download_Files https://github.com/PCRE2Project/pcre2/releases/download/${Pcre_Ver}/${Pcre_Ver}.tar.bz2 ${Pcre_Ver}.tar.bz2
        Tar_Cd ${Pcre_Ver}.tar.bz2
        Nginx_With_Pcre="--with-pcre=${cur_dir}/src/${Pcre_Ver} --with-pcre-jit"
    fi
}


Download_Boost()
{
    Echo_Blue "[+] Download or use exist boost..."
    if [ "${DBSelect}" = "4" ] || echo "${mysql_version}" | grep -Eqi '^5.7.'; then
        if [ -s "${cur_dir}/src/${Boost_Ver}.tar.bz2" ]; then
            [[ -d "${cur_dir}/src/${Boost_Ver}" ]] && rm -rf -- "${cur_dir}/src/${Boost_Ver}"
            Validate_Archive "${cur_dir}/src/${Boost_Ver}.tar.bz2" || return 1
            tar jxf "${cur_dir}/src/${Boost_Ver}.tar.bz2" -C "${cur_dir}/src"
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/${Boost_Ver}"
        else
            cd "${cur_dir}/src/" || return 1
            Download_Files https://archives.boost.io/release/1.59.0/source/${Boost_Ver}.tar.bz2 ${Boost_Ver}.tar.bz2
            Validate_Archive "${cur_dir}/src/${Boost_Ver}.tar.bz2" || return 1
            tar jxf "${cur_dir}/src/${Boost_Ver}.tar.bz2"
            cd -
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/${Boost_Ver}"
        fi
    elif [[ "${DBSelect}" =~ ^[567]$ ]] || echo "${mysql_version}" | grep -Eqi '^(8|9)\.'; then
        Get_Boost_Ver=$(grep 'SET(BOOST_PACKAGE_NAME' cmake/boost.cmake |grep -oP '\d+(\_\d+){2}')
        if [ -s "${cur_dir}/src/boost_${Get_Boost_Ver}.tar.bz2" ]; then
            [[ -d "${cur_dir}/src/boost_${Get_Boost_Ver}" ]] && rm -rf -- "${cur_dir}/src/boost_${Get_Boost_Ver}"
            Validate_Archive "${cur_dir}/src/boost_${Get_Boost_Ver}.tar.bz2" || return 1
            tar jxf "${cur_dir}/src/boost_${Get_Boost_Ver}.tar.bz2" -C "${cur_dir}/src"
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/boost_${Get_Boost_Ver}"
        else
            local boost_release
            boost_release=${Get_Boost_Ver//_/.}
            cd "${cur_dir}/src" || return 1
            Download_Files "https://archives.boost.io/release/${boost_release}/source/boost_${Get_Boost_Ver}.tar.bz2" "boost_${Get_Boost_Ver}.tar.bz2" publisher-tls || return 1
            Validate_Archive "${cur_dir}/src/boost_${Get_Boost_Ver}.tar.bz2" || return 1
            tar jxf "${cur_dir}/src/boost_${Get_Boost_Ver}.tar.bz2" -C "${cur_dir}/src" || return 1
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/boost_${Get_Boost_Ver}"
        fi
    fi
}

Install_Boost()
{
    Echo_Blue "[+] Download or use exist boost..."
    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        if [ -d "${cur_dir}/src/${Mysql_Ver}/boost" ]; then
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/${Mysql_Ver}/boost"
        else
            Download_Boost
        fi
    elif echo "${mysql_version}" | grep -Eqi '^5\.7\.' || echo "${mysql_version}" | grep -Eqi '^(8|9)\.'; then
        if [ -d "${cur_dir}/src/mysql-${mysql_version}/boost" ]; then
            MySQL_WITH_BOOST="-DWITH_BOOST=${cur_dir}/src/mysql-${mysql_version}/boost"
        else
            Download_Boost
        fi
    fi
}

Activate_MySQL97_Compiler()
{
    local gcc_major
    if ! { [ "${DBSelect:-}" = 7 ] || echo "${mysql_version:-}" | grep -Eq '^9\.7\.'; }; then
        return 0
    fi
    gcc_major=$(gcc -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)
    [ "${gcc_major:-0}" -ge 10 ] && return 0
    if [ -f /opt/rh/gcc-toolset-12/enable ]; then
        . /opt/rh/gcc-toolset-12/enable
    elif [ -f /opt/rh/gcc-toolset-10/enable ]; then
        . /opt/rh/gcc-toolset-10/enable
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get --no-install-recommends install -y gcc-10 g++-10 || return 1
        export CC=gcc-10 CXX=g++-10
    fi
    gcc_major=$(${CC:-gcc} -dumpfullversion -dumpversion 2>/dev/null | cut -d. -f1)
    if [ "${gcc_major:-0}" -lt 10 ]; then
        Echo_Red 'MySQL 9.7 source builds require GCC 10 or newer; use the official generic binary on this host.'
        return 1
    fi
}

Install_Openssl_New()
{
    local openssl_version="${Openssl_New_Ver#openssl-}"
    if [ ! -x /usr/local/openssl3/bin/openssl ] || ! /usr/local/openssl3/bin/openssl version | grep -Fq "OpenSSL ${openssl_version}"; then
        Echo_Blue "[+] Installing ${Openssl_New_Ver}"
        cd "${cur_dir}/src" || return 1
        Download_Files https://www.openssl.org/source/${Openssl_New_Ver}.tar.gz ${Openssl_New_Ver}.tar.gz
        [[ -d "${Openssl_New_Ver}" ]] && rm -rf -- "${Openssl_New_Ver}"
        Tar_Cd ${Openssl_New_Ver}.tar.gz ${Openssl_New_Ver}
        ./config -fPIC --prefix=/usr/local/openssl3 --openssldir=/usr/local/openssl3
        Make_Install
        cd "${cur_dir}/src/" || return 1
        rm -rf -- "${cur_dir}/src/${Openssl_New_Ver}"
    fi
}

Install_Libzip()
{
    if echo "${CentOS_Version}" | grep -Eqi "^7"  || echo "${RHEL_Version}" | grep -Eqi "^7"  || echo "${Aliyun_Version}" | grep -Eqi "^2" || echo "${Alibaba_Version}" | grep -Eqi "^2" || echo "${Oracle_Version}" | grep -Eqi "^7" || echo "${Anolis_Version}" | grep -Eqi "^7"; then
        if [ ! -s /usr/local/lib/libzip.so ]; then
            Echo_Blue "[+] Installing ${Libzip_Ver}"
            cd "${cur_dir}/src" || return 1
            Download_Files https://libzip.org/download/${Libzip_Ver}.tar.xz ${Libzip_Ver}.tar.xz
            Tar_Cd ${Libzip_Ver}.tar.xz ${Libzip_Ver}
            mkdir build && cd build
            if command -v cmake3 >/dev/null 2>&1; then
                cmake3 .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
            else
                cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
            fi
            Make_Install
            cd "${cur_dir}/src/" || return 1
            rm -rf -- "${cur_dir}/src/${Libzip_Ver}"
        fi
        export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
        ldconfig
    fi
}

CentOS_Lib_Opt()
{
    if [ "${Is_64bit}" = "y" ] ; then
        ln -sf /usr/lib64/libpng.* /usr/lib/
        ln -sf /usr/lib64/libjpeg.* /usr/lib/
    fi

    ulimit -v unlimited

    if [ `grep -L "/lib"    '/etc/ld.so.conf'` ]; then
        echo "/lib" >> /etc/ld.so.conf
    fi

    if [ `grep -L '/usr/lib'    '/etc/ld.so.conf'` ]; then
        echo "/usr/lib" >> /etc/ld.so.conf
        #echo "/usr/lib/openssl/engines" >> /etc/ld.so.conf
    fi

    if [ -d "/usr/lib64" ] && [ `grep -L '/usr/lib64'    '/etc/ld.so.conf'` ]; then
        echo "/usr/lib64" >> /etc/ld.so.conf
        #echo "/usr/lib64/openssl/engines" >> /etc/ld.so.conf
    fi

    if [ `grep -L '/usr/local/lib'    '/etc/ld.so.conf'` ]; then
        echo "/usr/local/lib" >> /etc/ld.so.conf
    fi

    ldconfig

    if command -v systemd-detect-virt >/dev/null 2>&1 && [[ "$(systemd-detect-virt)" = "lxc" ]]; then
        cat >>/etc/security/limits.conf<<eof
* soft nofile 65535
* hard nofile 65535
eof
    else
        cat >>/etc/security/limits.conf<<eof
* soft nproc 65535
* hard nproc 65535
* soft nofile 65535
* hard nofile 65535
eof
    fi

    echo "fs.file-max=65535" >> /etc/sysctl.conf

    if echo "${Fedora_Version}" | grep -Eqi "3[0-9]" && [ ! -d "/etc/init.d" ]; then
        ln -sf /etc/rc.d/init.d /etc/init.d
    fi

    if [ -s /usr/lib64/libtinfo.so.6 ]; then
        ln -sf /usr/lib64/libtinfo.so.6 /usr/lib64/libtinfo.so.5
    elif [ -s /usr/lib/libtinfo.so.6 ]; then
        ln -sf /usr/lib/libtinfo.so.6 /usr/lib/libtinfo.so.5
    fi

    if [ -s /usr/lib64/libncurses.so.6 ]; then
        ln -sf /usr/lib64/libncurses.so.6 /usr/lib64/libncurses.so.5
    elif [ -s /usr/lib/libncurses.so.6 ]; then
        ln -sf /usr/lib/libncurses.so.6 /usr/lib/libncurses.so.5
    fi
}

Deb_Lib_Opt()
{
    if [ "${Is_64bit}" = "y" ]; then
        ln -sf /usr/lib/x86_64-linux-gnu/libpng* /usr/lib/
        ln -sf /usr/lib/x86_64-linux-gnu/libjpeg* /usr/lib/
    else
        ln -sf /usr/lib/i386-linux-gnu/libpng* /usr/lib/
        ln -sf /usr/lib/i386-linux-gnu/libjpeg* /usr/lib/
        ln -sf /usr/include/i386-linux-gnu/asm /usr/include/asm
    fi

    if [ -d "/usr/lib/arm-linux-gnueabihf" ]; then
        ln -sf /usr/lib/arm-linux-gnueabihf/libpng* /usr/lib/
        ln -sf /usr/lib/arm-linux-gnueabihf/libjpeg* /usr/lib/
        ln -sf /usr/include/arm-linux-gnueabihf/curl /usr/include/
    fi

    ulimit -v unlimited

    if [ `grep -L "/lib"    '/etc/ld.so.conf'` ]; then
        echo "/lib" >> /etc/ld.so.conf
    fi

    if [ `grep -L '/usr/lib'    '/etc/ld.so.conf'` ]; then
        echo "/usr/lib" >> /etc/ld.so.conf
    fi

    if [ -d "/usr/lib64" ] && [ `grep -L '/usr/lib64'    '/etc/ld.so.conf'` ]; then
        echo "/usr/lib64" >> /etc/ld.so.conf
    fi

    if [ `grep -L '/usr/local/lib'    '/etc/ld.so.conf'` ]; then
        echo "/usr/local/lib" >> /etc/ld.so.conf
    fi

    if [ -d /usr/include/x86_64-linux-gnu/curl ]; then
        ln -sf /usr/include/x86_64-linux-gnu/curl /usr/include/
    elif [ -d /usr/include/i386-linux-gnu/curl ]; then
        ln -sf /usr/include/i386-linux-gnu/curl /usr/include/
    fi

    if [ -d /usr/include/arm-linux-gnueabihf/curl ]; then
        ln -sf /usr/include/arm-linux-gnueabihf/curl /usr/include/
    fi

    if [ -d /usr/include/aarch64-linux-gnu/curl ]; then
        ln -sf /usr/include/aarch64-linux-gnu/curl /usr/include/
    fi

    ldconfig

    cat >>/etc/security/limits.conf<<eof
* soft nproc 65535
* hard nproc 65535
* soft nofile 65535
* hard nofile 65535
eof

    echo "fs.file-max=65535" >> /etc/sysctl.conf
}

Remove_Error_Libcurl()
{
    if [ -s /usr/local/lib/libcurl.so ]; then
        rm -f /usr/local/lib/libcurl*
    fi
}

Add_Swap()
{

    Disk_Avail=$(($(df -mP /var | tail -1 | awk '{print $4}' | sed s/[[:space:]]//g)/1024))

    DD_Count='1024'
    if [[ "${MemTotal}" -lt 1024 ]]; then
        DD_Count='1024'
        if [[ "${Disk_Avail}" -lt 5 ]]; then
            Enable_Swap='n'
        fi
    elif [[ "${MemTotal}" -ge 1024 && "${MemTotal}" -le 2048 ]]; then
        DD_Count='2048'
        if [[ "${Disk_Avail}" -lt 13 ]]; then
            Enable_Swap='n'
        fi
    elif [[ "${MemTotal}" -ge 2048 && "${MemTotal}" -le 4096 ]]; then
        DD_Count='4096'
        if [[ "${Disk_Avail}" -lt 17 ]]; then
            Enable_Swap='n'
        fi
    elif [[ "${MemTotal}" -ge 4096 && "${MemTotal}" -le 16384 ]]; then
        DD_Count='8192'
        if [[ "${Disk_Avail}" -lt 19 ]]; then
            Enable_Swap='n'
        fi
    elif [[ "${MemTotal}" -ge 16384 ]]; then
        DD_Count='8192'
        if [[ "${Disk_Avail}" -lt 27 ]]; then
            Enable_Swap='n'
        fi
    fi
    Swap_Total=$(awk '/SwapTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)
    if [[ "${Enable_Swap}" = "y" && "${Swap_Total}" -le 512 && ! -s /var/swapfile ]]; then
        echo "Add Swap file..."
        [ $(cat /proc/sys/vm/swappiness) -eq 0 ] && sysctl vm.swappiness=10
        dd if=/dev/zero of=/var/swapfile bs=1M count=${DD_Count}
        chmod 0600 /var/swapfile
        echo "Enable Swap..."
        /sbin/mkswap /var/swapfile
        /sbin/swapon /var/swapfile
        if [ $? -eq 0 ]; then
            [ `grep -L '/var/swapfile'    '/etc/fstab'` ] && echo "/var/swapfile swap swap defaults 0 0" >>/etc/fstab
            /sbin/swapon -s
        else
            rm -f /var/swapfile
            echo "Add Swap Failed!"
        fi
    fi
}
