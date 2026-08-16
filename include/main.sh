#!/usr/bin/env bash

DB_Info=('retired' 'retired' 'retired' 'MySQL 5.7.44' 'MySQL 8.0.46' 'MySQL 8.4.11' 'MySQL 9.7.1 LTS' 'retired' 'retired' 'MariaDB 10.6.27' 'MariaDB 10.11.18' 'MariaDB 11.4.12' 'MariaDB 11.8.8' 'MariaDB 12.3.2 LTS')
PHP_Info=('retired' 'retired' 'retired' 'retired' 'retired' 'retired' 'retired' 'retired' 'retired' 'PHP 7.4.33' 'PHP 8.0.30' 'PHP 8.1.34' 'PHP 8.2.33' 'PHP 8.3.33' 'PHP 8.4.24' 'PHP 8.5.9')

Database_Glibc_At_Least()
{
    local required=$1 actual
    actual=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
    [ -n "${actual}" ] && [ "$(printf '%s\n' "${required}" "${actual}" | sort -V | head -n1)" = "${required}" ]
}

Select_Database_Package_Mode()
{
    local product=$1 version=$2 requested_mode=${3:-${DB_Install_Mode:-auto}}
    local binary_supported=n reason='no matching official generic binary is configured'

    # Keep compatibility with existing unattended installations that export Bin=y/n.
    if [ -n "${Bin:-}" ]; then
        case "${Bin}" in
            y|Y|yes|YES) requested_mode=binary ;;
            n|N|no|NO) requested_mode=source ;;
            *) Echo_Red "Invalid legacy Bin value: ${Bin}"; return 1 ;;
        esac
    fi
    case "${requested_mode}" in
        auto|AUTO|Auto) requested_mode=auto ;;
        binary|BINARY|Binary) requested_mode=binary ;;
        source|SOURCE|Source) requested_mode=source ;;
        *) Echo_Red 'DB_Install_Mode must be auto, binary or source.'; return 1 ;;
    esac

    if [ "${requested_mode}" = source ]; then
        Bin=n
        DB_Install_Resolved_Mode=source
        Echo_Yellow "Database package mode: source build requested for ${product} ${version}."
        return 0
    fi

    case "${product}:${version}" in
        mysql:5.7.*)
            if [ "${DB_ARCH}" != x86_64 ]; then
                reason='MySQL 5.7 generic binary support is limited to x86_64'
            elif ! Database_Glibc_At_Least 2.12; then
                reason='MySQL 5.7 generic binaries require glibc 2.12 or newer'
            else
                binary_supported=y
            fi
            ;;
        mysql:8.0.*|mysql:8.4.*|mysql:9.7.*)
            if [[ ! "${DB_ARCH}" =~ ^(x86_64|aarch64)$ ]]; then
                reason="MySQL ${version%.*} has no configured generic binary for ${DB_ARCH}"
            elif ! Database_Glibc_At_Least 2.28; then
                reason="MySQL ${version%.*} generic binaries require glibc 2.28 or newer"
            else
                binary_supported=y
            fi
            ;;
        mariadb:10.6.*|mariadb:10.11.*|mariadb:11.4.*|mariadb:11.8.*|mariadb:12.3.*)
            if [ "${DB_ARCH}" != x86_64 ]; then
                reason='the verified MariaDB systemd binary set is x86_64-only'
            elif ! Database_Glibc_At_Least 2.19; then
                reason='MariaDB systemd binary tarballs require glibc 2.19 or newer'
            else
                binary_supported=y
            fi
            ;;
        *) reason="${product} ${version} is outside the supported binary policy" ;;
    esac

    if [ "${binary_supported}" = y ]; then
        Bin=y
        DB_Install_Resolved_Mode=binary
        Echo_Green "Database package mode: verified official generic binary for ${product} ${version}."
        return 0
    fi
    if [ "${requested_mode}" = binary ]; then
        Echo_Red "A binary install was required, but ${reason}."
        return 1
    fi

    Bin=n
    DB_Install_Resolved_Mode=source
    Echo_Yellow "Automatic database package fallback: ${reason}; using a source build."
    return 0
}

Database_Selection()
{
    local db_choice db_product db_version
    if [ -z "${DBSelect:-}" ]; then
        Echo_Yellow "Supported databases (MySQL 5.7 is the compatibility floor):"
        echo "1: ${DB_Info[3]}"
        echo "2: ${DB_Info[4]}"
        echo "3: ${DB_Info[5]} (Default)"
        echo "4: ${DB_Info[6]}"
        echo "5: ${DB_Info[9]}"
        echo "6: ${DB_Info[10]}"
        echo "7: ${DB_Info[11]}"
        echo "8: ${DB_Info[12]}"
        echo "9: ${DB_Info[13]}"
        echo "0: Do not install a database"
        read -r -p "Enter your choice (0-9, default 3): " db_choice
        case "${db_choice:-3}" in
            1) DBSelect=4 ;;
            2) DBSelect=5 ;;
            3) DBSelect=6 ;;
            4) DBSelect=7 ;;
            5) DBSelect=10 ;;
            6) DBSelect=11 ;;
            7) DBSelect=12 ;;
            8) DBSelect=13 ;;
            9) DBSelect=14 ;;
            0) DBSelect=0 ;;
            *) Echo_Red "Unsupported database selection."; return 1 ;;
        esac
    else
        case "${DBSelect}" in
            mysql-5.7|mysql5.7) DBSelect=4 ;;
            mysql-8.0|mysql8.0) DBSelect=5 ;;
            mysql-8.4|mysql8.4) DBSelect=6 ;;
            mysql-9.7|mysql9.7) DBSelect=7 ;;
            mariadb-10.6) DBSelect=10 ;;
            mariadb-10.11) DBSelect=11 ;;
            mariadb-11.4) DBSelect=12 ;;
            mariadb-11.8) DBSelect=13 ;;
            mariadb-12.3) DBSelect=14 ;;
            0|4|5|6|7|10|11|12|13|14) ;;
            *) Echo_Red "Unsupported database. Minimum supported versions are MySQL 5.7 and MariaDB 10.6."; return 1 ;;
        esac
    fi

    if [ "${DBSelect}" = "0" ]; then
        echo "Database installation disabled."
        return 0
    fi

    echo "You will install ${DB_Info[DBSelect-1]}"
    db_version=$(printf '%s\n' "${DB_Info[DBSelect-1]}" | awk '{print $2}')
    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        db_product=mysql
    else
        db_product=mariadb
    fi
    Select_Database_Package_Mode "${db_product}" "${db_version}" "${DB_Install_Mode:-auto}" || return 1

    if [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        MySQL_Bin=/usr/local/mariadb/bin/mysql
        MySQL_Config=/usr/local/mariadb/bin/mysql_config
        MySQL_Dir=/usr/local/mariadb
    else
        MySQL_Bin=/usr/local/mysql/bin/mysql
        MySQL_Config=/usr/local/mysql/bin/mysql_config
        MySQL_Dir=/usr/local/mysql
    fi

    if [ -z "${DB_Root_Password:-}" ]; then
        read -r -s -p "Database root password (blank generates one): " DB_Root_Password
        echo
        if [ -z "${DB_Root_Password}" ]; then
            DB_Root_Password=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
            umask 077
            printf '%s\n' "${DB_Root_Password}" > /root/.lnmp-db-root-password
        fi
    fi

    if [ -z "${InstallInnodb:-}" ]; then
        read -r -p "Tune both InnoDB and MyISAM? [Y/n; n = MyISAM-only tuning]: " InstallInnodb
    fi
    case "${InstallInnodb:-y}" in
        [nN]|[nN][oO])
            InstallInnodb=n
            Echo_Yellow "MyISAM-only tuning selected. MySQL 5.7+ still keeps mandatory InnoDB available."
            ;;
        *) InstallInnodb=y ;;
    esac
    return 0
}

PHP_Selection()
{
    local php_choice
    if [ -z "${PHPSelect:-}" ]; then
        Echo_Yellow "Supported PHP versions (7.4.33 is the compatibility floor):"
        echo "1: ${PHP_Info[9]} (legacy compatibility)"
        echo "2: ${PHP_Info[10]}"
        echo "3: ${PHP_Info[11]}"
        echo "4: ${PHP_Info[12]}"
        echo "5: ${PHP_Info[13]}"
        echo "6: ${PHP_Info[14]}"
        echo "7: ${PHP_Info[15]} (Default)"
        read -r -p "Enter your choice (1-7, default 7): " php_choice
        case "${php_choice:-7}" in
            1) PHPSelect=10 ;;
            2) PHPSelect=11 ;;
            3) PHPSelect=12 ;;
            4) PHPSelect=13 ;;
            5) PHPSelect=14 ;;
            6) PHPSelect=15 ;;
            7) PHPSelect=16 ;;
            *) Echo_Red "Unsupported PHP selection."; return 1 ;;
        esac
    else
        case "${PHPSelect}" in
            php-7.4|7.4) PHPSelect=10 ;;
            php-8.0|8.0) PHPSelect=11 ;;
            php-8.1|8.1) PHPSelect=12 ;;
            php-8.2|8.2) PHPSelect=13 ;;
            php-8.3|8.3) PHPSelect=14 ;;
            php-8.4|8.4) PHPSelect=15 ;;
            php-8.5|8.5) PHPSelect=16 ;;
            10|11|12|13|14|15|16) ;;
            *) Echo_Red "Unsupported PHP version. PHP 7.4.33 is the minimum."; return 1 ;;
        esac
    fi
    echo "You will install ${PHP_Info[PHPSelect-1]}"
    return 0
}

Configure_Build_Defaults()
{
    MySQLMAOpt=''
    NginxMAOpt=''
}

Dispaly_Selection()
{
    Database_Selection || exit 1
    PHP_Selection || exit 1
    Configure_Build_Defaults
}

Wait_For_Package_Manager()
{
    local attempt
    for attempt in $(seq 1 24); do
        if ! pgrep -x yum >/dev/null 2>&1 && ! pgrep -x dnf >/dev/null 2>&1 && \
           ! pgrep -x apt >/dev/null 2>&1 && ! pgrep -x apt-get >/dev/null 2>&1 && \
           ! pgrep -x dpkg >/dev/null 2>&1; then
            return 0
        fi
        [ "${attempt}" -eq 1 ] && Echo_Yellow 'Another package manager is active; waiting up to 120 seconds without killing it or deleting lock files.'
        sleep 5
    done
    Echo_Red 'The package manager is still active. Finish it cleanly, then rerun the installer.'
    return 1
}

Press_Install()
{
    if [ -z "${LNMP_Auto:-}" ]; then
        echo ""
        Echo_Green "Press any key to install...or Press Ctrl+c to cancel"
        OLDCONFIG=`stty -g`
        stty -icanon -echo min 1 time 0
        dd count=1 2>/dev/null
        stty ${OLDCONFIG}
    fi
    . include/version.sh
    Wait_For_Package_Manager || exit 1
}

Press_Start()
{
    echo ""
    Echo_Green "Press any key to start...or Press Ctrl+c to cancel"
    OLDCONFIG=`stty -g`
    stty -icanon -echo min 1 time 0
    dd count=1 2>/dev/null
    stty ${OLDCONFIG}
}

Install_LSB()
{
    echo "[+] Installing lsb..."
    if [ "$PM" = "yum" ]; then
        yum -y install redhat-lsb
    elif [ "$PM" = "apt" ]; then
        apt-get update
        apt-get --no-install-recommends install -y lsb-release
    fi
}

Get_Dist_Version()
{
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRO_Version=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO_Version="$DISTRIB_RELEASE"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_Version="$VERSION_ID"
    fi
    if [[ "${DISTRO}" = "" || "${DISTRO_Version}" = "" ]]; then
        if command -v python2 >/dev/null 2>&1; then
            DISTRO_Version=$(python2 -c 'import platform; print platform.linux_distribution()[1]')
        elif command -v python3 >/dev/null 2>&1; then
            DISTRO_Version=$(python3 -c 'import platform; print(platform.linux_distribution()[1])')
        else
            Install_LSB
            DISTRO_Version=`lsb_release -rs`
        fi
    fi
    printf -v "${DISTRO}_Version" '%s' "${DISTRO_Version}"
}

Get_Dist_Name()
{
    if grep -Eqi "Alibaba" /etc/issue || grep -Eq "Alibaba Cloud Linux" /etc/*-release; then
        DISTRO='Alibaba'
        PM='yum'
    elif grep -Eqi "Aliyun" /etc/issue || grep -Eq "Aliyun Linux" /etc/*-release; then
        DISTRO='Aliyun'
        PM='yum'
    elif grep -Eqi "Amazon Linux" /etc/issue || grep -Eq "Amazon Linux" /etc/*-release; then
        DISTRO='Amazon'
        PM='yum'
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        DISTRO='Fedora'
        PM='yum'
    elif grep -Eqi "Oracle Linux" /etc/issue || grep -Eq "Oracle Linux" /etc/*-release; then
        DISTRO='Oracle'
        PM='yum'
    elif grep -Eqi "rockylinux" /etc/issue || grep -Eq "Rocky Linux" /etc/*-release; then
        DISTRO='Rocky'
        PM='yum'
    elif grep -Eqi "almalinux" /etc/issue || grep -Eq "AlmaLinux" /etc/*-release; then
        DISTRO='Alma'
        PM='yum'
    elif grep -Eqi "openEuler" /etc/issue || grep -Eq "openEuler" /etc/*-release; then
        DISTRO='openEuler'
        PM='yum'
    elif grep -Eqi "Anolis OS" /etc/issue || grep -Eq "Anolis OS" /etc/*-release; then
        DISTRO='Anolis'
        PM='yum'
    elif grep -Eqi "Kylin Linux Advanced Server" /etc/issue || grep -Eq "Kylin Linux Advanced Server" /etc/*-release; then
        DISTRO='Kylin'
        PM='yum'
    elif grep -Eqi "OpenCloudOS" /etc/issue || grep -Eq "OpenCloudOS" /etc/*-release; then
        DISTRO='OpenCloudOS'
        PM='yum'
    elif grep -Eqi "Huawei Cloud EulerOS" /etc/issue || grep -Eq "Huawei Cloud EulerOS" /etc/*-release; then
        DISTRO='HCE'
        PM='yum'
    elif grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        DISTRO='CentOS'
        PM='yum'
        if grep -Eq "CentOS Stream" /etc/*-release; then
            isCentosStream='y'
        fi
    elif grep -Eqi "Red Hat Enterprise Linux" /etc/issue || grep -Eq "Red Hat Enterprise Linux" /etc/*-release; then
        DISTRO='RHEL'
        PM='yum'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        DISTRO='Ubuntu'
        PM='apt'
    elif grep -Eqi "Raspbian" /etc/issue || grep -Eq "Raspbian" /etc/*-release; then
        DISTRO='Raspbian'
        PM='apt'
    elif grep -Eqi "Deepin" /etc/issue || grep -Eq "Deepin" /etc/*-release; then
        DISTRO='Deepin'
        PM='apt'
    elif grep -Eqi "Mint" /etc/issue || grep -Eq "Mint" /etc/*-release; then
        DISTRO='Mint'
        PM='apt'
    elif grep -Eqi "Kali" /etc/issue || grep -Eq "Kali" /etc/*-release; then
        DISTRO='Kali'
        PM='apt'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        DISTRO='Debian'
        PM='apt'
    elif grep -Eqi "UnionTech OS|UOS" /etc/issue || grep -Eq "UnionTech OS|UOS" /etc/*-release; then
        DISTRO='UOS'
        if command -v apt >/dev/null 2>&1; then
            PM='apt'
        elif command -v yum >/dev/null 2>&1; then
            PM='yum'
        fi
    elif grep -Eqi "Kylin Linux Desktop" /etc/issue || grep -Eq "Kylin Linux Desktop" /etc/*-release; then
        DISTRO='Kylin'
        PM='apt'
    else
        DISTRO='unknow'
    fi
    Get_OS_Bit
}

Get_RHEL_Version()
{
    Get_Dist_Name
    if [ "${DISTRO}" = "RHEL" ]; then
        if grep -Eqi "release 5." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 5"
            RHEL_Ver='5'
        elif grep -Eqi "release 6." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 6"
            RHEL_Ver='6'
        elif grep -Eqi "release 7." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 7"
            RHEL_Ver='7'
        elif grep -Eqi "release 8." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 8"
            RHEL_Ver='8'
        elif grep -Eqi "release 9." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 9"
            RHEL_Ver='9'
        elif grep -Eqi "release 10." /etc/redhat-release; then
            echo "Current Version: RHEL Ver 10"
            RHEL_Ver='10'
        fi
        RHEL_Version="$(cat /etc/redhat-release | sed 's/.*release\ //' | sed 's/\ .*//')"
    fi
}

Get_OS_Bit()
{
    if [[ `getconf WORD_BIT` = '32' && `getconf LONG_BIT` = '64' ]] ; then
        Is_64bit='y'
        ARCH='x86_64'
        DB_ARCH='x86_64'
    else
        Is_64bit='n'
        ARCH='i386'
        DB_ARCH='i686'
    fi

    if uname -m | grep -Eqi "arm|aarch64"; then
        Is_ARM='y'
        if uname -m | grep -Eqi "armv7|armv6"; then
            ARCH='armhf'
        elif uname -m | grep -Eqi "aarch64"; then
            ARCH='aarch64'
            DB_ARCH='aarch64'
        else
            ARCH='arm'
        fi
    fi
}

Download_Files()
{
    local URL="$1"
    local FileName="$2"
    local IntegrityPolicy="${3:-pinned}"
    local PartFile="${FileName}.part"
    local Host verify_status

    case "${URL}" in
        https://*) ;;
        *) Echo_Red "Refusing non-HTTPS download: ${URL}"; return 1 ;;
    esac
    Host=${URL#https://}
    Host=${Host%%/*}
    Host=${Host%%:*}
    case "${Host}" in
        archive.mariadb.org|archives.boost.io|cdn.mysql.com|curl.se|download.pureftpd.org|download.redis.io|download.savannah.gnu.org|downloads.ioncube.com|files.phpmyadmin.net|ftp.gnu.org|github.com|libzip.org|nginx.org|pecl.php.net|www.openssl.org|www.php.net|www.sourceguardian.com) ;;
        *) Echo_Red "Refusing download from unapproved host: ${Host}"; return 1 ;;
    esac
    case "${IntegrityPolicy}" in
        pinned|publisher-tls) ;;
        *) Echo_Red "Invalid download integrity policy: ${IntegrityPolicy}"; return 1 ;;
    esac
    if [[ -z "${FileName}" || "${FileName}" == */* || "${FileName}" == *..* ]]; then
        Echo_Red "Unsafe download filename: ${FileName}"
        return 1
    fi

    if [ -s "${FileName}" ]; then
        Verify_Download "${FileName}"
        verify_status=$?
        if [ "${verify_status}" -eq 0 ]; then
            echo "${FileName} [found and verified]"
            return 0
        fi
        if [ "${verify_status}" -eq 2 ] && [ "${IntegrityPolicy}" = publisher-tls ]; then
            Echo_Yellow "Refreshing unpinned publisher archive ${FileName}; cached copies are never trusted."
            rm -f -- "${FileName}"
        fi
    fi

    rm -f "${PartFile}"
    echo "Downloading ${FileName} from ${URL}..."
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 5 --retry 3 --connect-timeout 20 --output "${PartFile}" "${URL}"
    else
        wget --https-only --secure-protocol=TLSv1_2 --max-redirect=5 --timeout=30 --tries=3 --output-document="${PartFile}" "${URL}"
    fi
    if [ $? -ne 0 ] || [ ! -s "${PartFile}" ]; then
        rm -f "${PartFile}"
        Echo_Red "Download failed: ${URL}"
        return 1
    fi
    mv -f "${PartFile}" "${FileName}"
    Verify_Download "${FileName}"
    verify_status=$?
    if [ "${verify_status}" -eq 2 ] && [ "${IntegrityPolicy}" = publisher-tls ]; then
        Echo_Yellow "${FileName} is not pinned; accepted only from approved publisher ${Host} over verified TLS."
        return 0
    fi
    if [ "${verify_status}" -ne 0 ]; then
        rm -f -- "${FileName}"
        return 1
    fi
    return 0
}

Verify_Download()
{
    local FileName="$1"
    local ChecksumFile="${cur_dir}/src/checksums.sha256"
    local MD5ChecksumFile="${cur_dir}/src/checksums.md5"
    local Expected
    local Actual

    [ -s "${FileName}" ] || return 1
    Expected=""
    if [ -s "${ChecksumFile}" ]; then
        Expected=$(awk -v name="${FileName}" '$2 == name {print $1; exit}' "${ChecksumFile}")
    fi
    if [ -n "${Expected}" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            Actual=$(sha256sum "${FileName}" | awk '{print $1}')
        else
            Actual=$(openssl dgst -sha256 "${FileName}" | awk '{print $NF}')
        fi
        if [ "${Actual}" != "${Expected}" ]; then
            Echo_Red "SHA-256 mismatch for ${FileName}. File removed."
            rm -f "${FileName}"
            return 1
        fi
        return 0
    fi
    if [ -s "${MD5ChecksumFile}" ]; then
        Expected=$(awk -v name="${FileName}" '$2 == name {print $1; exit}' "${MD5ChecksumFile}")
    fi
    if [ -z "${Expected}" ]; then
        Echo_Yellow "No pinned checksum is available for ${FileName}."
        return 2
    fi
    if command -v md5sum >/dev/null 2>&1; then
        Actual=$(md5sum "${FileName}" | awk '{print $1}')
    else
        Actual=$(openssl dgst -md5 "${FileName}" | awk '{print $NF}')
    fi
    if [ "${Actual}" != "${Expected}" ]; then
        Echo_Red "Publisher checksum mismatch for ${FileName}. File removed."
        rm -f "${FileName}"
        return 1
    fi
    return 0
}

Validate_Archive()
{
    local FileName=$1
    if ! tar tf "${FileName}" | awk '/(^\/|(^|\/)\.\.($|\/)|^[A-Za-z]:)/ { bad=1 } END { exit bad }'; then
        Echo_Red "Unsafe archive paths detected in ${FileName}."
        return 1
    fi
    if ! tar tvf "${FileName}" | awk '
        /^[bcp]/ { bad=1 }
        /^[lh]/ {
            marker=" -> "; pos=index($0, marker)
            if (!pos) { marker=" link to "; pos=index($0, marker) }
            if (pos) {
                target=substr($0, pos + length(marker))
                if (target ~ /^\// || target ~ /(^|\/)\.\.($|\/)/ || target ~ /^[A-Za-z]:/) bad=1
            }
        }
        END { exit bad }
    '; then
        Echo_Red "Unsafe archive link or special-file entry detected in ${FileName}."
        return 1
    fi
}

Tar_Cd()
{
    local FileName=$1
    local DirName=$2
    local extension=${FileName##*.}
    cd "${cur_dir}/src" || return 1
    Validate_Archive "${FileName}" || return 1
    [[ -d "${DirName}" ]] && rm -rf -- "${DirName}"
    echo "Uncompress ${FileName}..."
    if [ "$extension" == "gz" ] || [ "$extension" == "tgz" ]; then
        tar zxf "${FileName}" || return 1
    elif [ "$extension" == "bz2" ]; then
        tar jxf "${FileName}" || return 1
    elif [ "$extension" == "xz" ]; then
        tar Jxf "${FileName}" || return 1
    fi
    if [ -n "${DirName}" ]; then
        echo "cd ${DirName}..."
        cd "${DirName}" || return 1
    fi
}

Validate_Install_Path()
{
    local path=$1 label=${2:-Path} resolved
    if [[ -z "${path}" || "${path}" != /* || "${path}" =~ [^/A-Za-z0-9._@+-] ]]; then
        Echo_Red "${label} must be an absolute path containing only safe path characters."
        return 1
    fi
    resolved=$(readlink -m -- "${path}" 2>/dev/null) || return 1
    case "${resolved}" in
        /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/lib|/lib/*|/lib32|/lib32/*|/lib64|/lib64/*|/media|/mnt|/opt|/proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/srv|/sys|/sys/*|/tmp|/tmp/*|/usr|/usr/bin|/usr/bin/*|/usr/include|/usr/include/*|/usr/lib|/usr/lib/*|/usr/lib32|/usr/lib32/*|/usr/lib64|/usr/lib64/*|/usr/sbin|/usr/sbin/*|/var)
            Echo_Red "Refusing unsafe ${label}: ${resolved}"
            return 1
            ;;
    esac
    return 0
}

Check_LNMPConf()
{
    if [ ! -s "${cur_dir}/lnmp.conf" ]; then
        Echo_Red "lnmp.conf was not exsit!"
        exit 1
    fi
    if [[ "${Download_Mirror}" = "" || "${MySQL_Data_Dir}" = "" || "${MariaDB_Data_Dir}" = "" || "${Default_Website_Dir}" = "" ]]; then
        Echo_Red "Can't get values from lnmp.conf!"
        exit 1
    fi
    Validate_Install_Path "${MySQL_Data_Dir}" 'MySQL data directory' || exit 1
    Validate_Install_Path "${MariaDB_Data_Dir}" 'MariaDB data directory' || exit 1
    Validate_Install_Path "${Default_Website_Dir}" 'website directory' || exit 1
}

Print_APP_Ver()
{
    echo "You will install the LNMP stack."
    echo "${Nginx_Ver}"

    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        echo "${Mysql_Ver}"
    elif [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        echo "${Mariadb_Ver}"
    elif [ "${DBSelect}" = "0" ]; then
        echo "Do not install MySQL/MariaDB!"
    fi

    echo "${Php_Ver}"

    echo "Enable InnoDB: ${InstallInnodb}"
    echo "Print lnmp.conf infomation..."
    echo "Download Mirror: ${Download_Mirror}"
    echo "Nginx Additional Modules: ${Nginx_Modules_Options}"
    echo "PHP Additional Modules: ${PHP_Modules_Options}"
    if [ "${Enable_PHP_Fileinfo}" = "y" ]; then
        echo "enable PHP fileinfo."
    fi
    if [ "${Enable_Nginx_Lua}" = "y" ]; then
        echo "enable Nginx Lua."
    fi
    if [[ "${DBSelect}" =~ ^[4-7]$ ]]; then
        echo "Database Directory: ${MySQL_Data_Dir}"
    elif [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        echo "Database Directory: ${MariaDB_Data_Dir}"
    elif [ "${DBSelect}" = "0" ]; then
        echo "Do not install MySQL/MariaDB!"
    fi
    echo "Default Website Directory: ${Default_Website_Dir}"
}

Print_Sys_Info()
{
    echo "LNMP Version: ${LNMP_Ver}"
    local DistroVersionVar="${DISTRO}_Version"
    echo "${DISTRO} ${!DistroVersionVar}"
    cat /etc/issue
    cat /etc/*-release
    uname -a
    MemTotal=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)
    echo "Memory is: ${MemTotal} MB "
    df -h
    Check_Openssl
    Check_WSL
    Check_Docker
    if [ "${CheckMirror}" != "n" ]; then
        echo "Server Location: ${country}"
    fi
}

StartUp()
{
    init_name=$1
    echo "Add ${init_name} service at system startup..."
    [[ "${isWSL}" = "" ]] && Check_WSL
    [[ "${isDocker}" = "" ]] && Check_Docker
    if [ "${isWSL}" = "n" ] && [ "${isDocker}" = "n" ] && command -v systemctl >/dev/null 2>&1 && [[ -s /etc/systemd/system/${init_name}.service || -s /lib/systemd/system/${init_name}.service || -s /usr/lib/systemd/system/${init_name}.service ]]; then
        systemctl daemon-reload
        systemctl enable ${init_name}.service
    else
        if [ "$PM" = "yum" ]; then
            chkconfig --add ${init_name}
            chkconfig ${init_name} on
        elif [ "$PM" = "apt" ]; then
            update-rc.d -f ${init_name} defaults
        fi
    fi
}

Remove_StartUp()
{
    init_name=$1
    echo "Removing ${init_name} service at system startup..."
    [[ "${isWSL}" = "" ]] && Check_WSL
    [[ "${isDocker}" = "" ]] && Check_Docker
    if [ "${isWSL}" = "n" ] && [ "${isDocker}" = "n" ] && command -v systemctl >/dev/null 2>&1 && [[ -s /etc/systemd/system/${init_name}.service || -s /lib/systemd/system/${init_name}.service || -s /usr/lib/systemd/system/${init_name}.service ]]; then
        systemctl disable ${init_name}.service
    else
        if [ "$PM" = "yum" ]; then
            chkconfig ${init_name} off
            chkconfig --del ${init_name}
        elif [ "$PM" = "apt" ]; then
            update-rc.d -f ${init_name} remove
        fi
    fi
}

Check_CMPT()
{
    if [[ "${DBSelect}" = "5" && "${Bin}" != "y" ]]; then
        if echo "${Ubuntu_Version}" | grep -Eqi "^1[0-7]\." || echo "${Debian_Version}" | grep -Eqi "^[4-8]" || echo "${Raspbian_Version}" | grep -Eqi "^[4-8]" || echo "${CentOS_Version}" | grep -Eqi "^[4-7]"  || echo "${RHEL_Version}" | grep -Eqi "^[4-7]" || echo "${Fedora_Version}" | grep -Eqi "^2[0-3]"; then
            Echo_Red "MySQL 8.0 please use latest linux distributions!"
            exit 1
        fi
    fi
    if [[ "${PHPSelect}" =~ ^1[0-6]$ ]]; then
        if echo "${Ubuntu_Version}" | grep -Eqi "^1[0-7]\." || echo "${Debian_Version}" | grep -Eqi "^[4-8]" || echo "${Raspbian_Version}" | grep -Eqi "^[4-8]" || echo "${CentOS_Version}" | grep -Eqi "^[4-6]"  || echo "${RHEL_Version}" | grep -Eqi "^[4-6]" || echo "${Fedora_Version}" | grep -Eqi "^2[0-3]"; then
            Echo_Red "PHP 7.4 and PHP 8.* please use latest linux distributions!"
            exit 1
        fi
    fi
}

Color_Text()
{
  echo -e " \e[0;$2m$1\e[0m"
}

Echo_Red()
{
  echo $(Color_Text "$1" "31")
}

Echo_Green()
{
  echo $(Color_Text "$1" "32")
}

Echo_Yellow()
{
  echo $(Color_Text "$1" "33")
}

Echo_Blue()
{
  echo $(Color_Text "$1" "34")
}

Get_PHP_Ext_Dir()
{
    Cur_PHP_Version="`/usr/local/php/bin/php-config --version`"
    zend_ext_dir="`/usr/local/php/bin/php-config --extension-dir`/"
}

Check_Stack()
{
    if [[ -s /usr/local/php/sbin/php-fpm && -s /usr/local/php/etc/php-fpm.conf && -s /etc/init.d/php-fpm && -s /usr/local/nginx/sbin/nginx ]]; then
        Get_Stack="lnmp"
    else
        Get_Stack="unknow"
    fi
}

Check_DB()
{
    if [[ -s /usr/local/mariadb/bin/mysql && -s /usr/local/mariadb/bin/mysqld_safe && -s /etc/my.cnf ]]; then
        MySQL_Bin="/usr/local/mariadb/bin/mysql"
        MySQL_Config="/usr/local/mariadb/bin/mysql_config"
        MySQL_Dir="/usr/local/mariadb"
        Is_MySQL="n"
        DB_Name="mariadb"
    elif [[ -s /usr/local/mysql/bin/mysql && -s /usr/local/mysql/bin/mysqld_safe && -s /etc/my.cnf ]]; then
        MySQL_Bin="/usr/local/mysql/bin/mysql"
        MySQL_Config="/usr/local/mysql/bin/mysql_config"
        MySQL_Dir="/usr/local/mysql"
        Is_MySQL="y"
        DB_Name="mysql"
    else
        Is_MySQL="None"
        DB_Name="None"
    fi
}

Do_Query()
{
    local query_file
    local query_status
    query_file=$(mktemp /tmp/lnmp-mysql-query.XXXXXX) || return 1
    printf '%s\n' "$1" >"${query_file}"
    chmod 600 "${query_file}"
    Check_DB
    ${MySQL_Bin} --defaults-file="${LNMP_MYCNF}" <"${query_file}"
    query_status=$?
    rm -f "${query_file}"
    return ${query_status}
}

Make_TempMycnf()
{
    local escaped_password=${1//\\/\\\\}
    escaped_password=${escaped_password//\"/\\\"}
    umask 077
    if [ -n "${LNMP_MYCNF:-}" ]; then
        rm -f "${LNMP_MYCNF}"
    fi
    LNMP_MYCNF=$(mktemp /tmp/lnmp-mycnf.XXXXXX) || return 1
    trap 'TempMycnf_Clean' EXIT
    trap 'TempMycnf_Clean; exit 1' HUP INT TERM
    cat >"${LNMP_MYCNF}"<<EOF
[client]
user=root
password="${escaped_password}"
EOF
    chmod 600 "${LNMP_MYCNF}"
}

Set_Initial_DB_Root_Password()
{
    local client=$1 password=$2 sql_file escaped_password status
    escaped_password=${password//\\/\\\\}
    escaped_password=${escaped_password//\'/\'\'}
    umask 077
    sql_file=$(mktemp /tmp/lnmp-initial-password.XXXXXX) || return 1
    printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\nFLUSH PRIVILEGES;\n" \
        "${escaped_password}" >"${sql_file}"
    chmod 600 "${sql_file}"
    "${client}" --protocol=socket -u root <"${sql_file}"
    status=$?
    rm -f "${sql_file}"
    return "${status}"
}

Verify_DB_Password()
{
    Check_DB
    status=1
    while [ $status -eq 1 ]; do
        read -s -p "Enter current root password of Database (Password will not shown): " DB_Root_Password
        Make_TempMycnf "${DB_Root_Password}"
        Do_Query ""
        status=$?
    done
    echo "OK, MySQL root password correct."
}

TempMycnf_Clean()
{
    if [ -n "${LNMP_MYCNF:-}" ]; then
        rm -f "${LNMP_MYCNF}"
        LNMP_MYCNF=""
    fi
}

StartOrStop()
{
    local action=$1
    local service=$2
    [[ "${isWSL}" = "" ]] && Check_WSL
    [[ "${isDocker}" = "" ]] && Check_Docker
    if [ "${isWSL}" = "n" ] && [ "${isDocker}" = "n" ] && command -v systemctl >/dev/null 2>&1 && [[ -s /etc/systemd/system/${service}.service ]]; then
        systemctl ${action} ${service}.service
    else
        /etc/init.d/${service} ${action}
    fi
}

Check_WSL() {
    if [[ "$(< /proc/sys/kernel/osrelease)" == *[Mm]icrosoft* ]]; then
        echo "running on WSL"
        isWSL="y"
    else
        isWSL="n"
    fi
}

Check_Docker() {
    if [ -f /.dockerenv ]; then
        echo "running on Docker"
        isDocker="y"
    elif [ -f /proc/1/cgroup ] && grep -q docker /proc/1/cgroup; then
        echo "running on Docker"
        isDocker="y"
    elif [ -f /proc/self/cgroup ] && grep -q docker /proc/self/cgroup; then
        echo "running on Docker"
        isDocker="y"
    else
        isDocker="n"
    fi
}

Check_Openssl()
{
    if ! command -v openssl >/dev/null 2>&1; then
        Echo_Blue "[+] Installing openssl..."
        if [ "${PM}" = "yum" ]; then
            yum install -y openssl
        elif [ "${PM}" = "apt" ]; then
            apt-get update -y
            [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
            apt-get install -y openssl
        fi
    fi
    openssl version
    if openssl version | grep -Eqi "OpenSSL 3.*"; then
        isOpenSSL3='y'
    fi
}
