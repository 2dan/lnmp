#!/usr/bin/env bash
set -o pipefail
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root privileges are required." >&2
    exit 1
fi

cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${cur_dir}" || exit 1
. lnmp.conf
. include/main.sh
. include/init.sh
Get_Dist_Name

action=${1:-}
addon=${2:-}
requested_version=${3:-latest}
requested_php_prefix=${4:-${PHP_PREFIX:-}}
sourceguardian_license_acceptance=${5:-}
if [[ "${addon}" =~ ^(sourceguardian|sg)$ ]]; then
    if [ "${requested_version}" = '--accept-sourceguardian-license' ]; then
        sourceguardian_license_acceptance=${requested_version}
        requested_version=latest
        requested_php_prefix=${PHP_PREFIX:-}
    elif [ "${requested_php_prefix}" = '--accept-sourceguardian-license' ] && [ -z "${sourceguardian_license_acceptance}" ]; then
        sourceguardian_license_acceptance=${requested_php_prefix}
        requested_php_prefix=${PHP_PREFIX:-}
    fi
fi

usage()
{
    cat <<'EOF'
Usage:
  ./addons.sh install|upgrade <addon> [version|latest] [php-prefix]
  ./addons.sh uninstall <addon> [version|latest] [php-prefix]
  ./addons.sh install|upgrade sourceguardian latest [php-prefix] --accept-sourceguardian-license
  ./addons.sh list

Addons with selectable versions:
  phpredis apcu imagick imagemagick memcached memcache swoole imap
  exif fileinfo ldap bz2 sodium opcache (version follows selected PHP)
  imap uses the PHP source version on PHP 7.4-8.2 and PECL on PHP 8.3+
  redis (Redis server version; phpredis uses its own current default)
  ioncube (vendor's current loader bundle)
  sourceguardian (official current loader bundle, or a local vendor archive)

Examples:
  ./addons.sh upgrade phpredis 6.3.0 /usr/local/php7.4
  ./addons.sh install swoole 6.2.2 /usr/local/php8.5
  ./addons.sh upgrade redis 8.10.0 /usr/local/php
  ./addons.sh install sourceguardian --accept-sourceguardian-license
  ./addons.sh install sourceguardian latest /usr/local/php8.5 --accept-sourceguardian-license
  ./addons.sh install sourceguardian /root/loaders.linux-x86_64.tar.gz /usr/local/php8.5
EOF
}

validate_version()
{
    [[ "$1" =~ ^[0-9]+([.][0-9]+){1,3}([A-Za-z0-9.-]+)?$ ]]
}

version_at_least()
{
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

select_php()
{
    local candidates=() path index=1 choice
    if [ -n "${requested_php_prefix}" ]; then
        case "${requested_php_prefix}" in
            /usr/local/php|/usr/local/php7.4|/usr/local/php8.0|/usr/local/php8.1|/usr/local/php8.2|/usr/local/php8.3|/usr/local/php8.4|/usr/local/php8.5) ;;
            *) Echo_Red "Unsupported PHP prefix: ${requested_php_prefix}"; return 1 ;;
        esac
        [ -x "${requested_php_prefix}/bin/php-config" ] || { Echo_Red "PHP is not installed at ${requested_php_prefix}."; return 1; }
        candidates=("${requested_php_prefix}")
    else
        for path in /usr/local/php /usr/local/php7.4 /usr/local/php8.0 /usr/local/php8.1 /usr/local/php8.2 /usr/local/php8.3 /usr/local/php8.4 /usr/local/php8.5; do
            [ -x "${path}/bin/php-config" ] && candidates+=("${path}")
        done
    fi
    [ "${#candidates[@]}" -gt 0 ] || { Echo_Red "No supported PHP installation found."; return 1; }
    if [ "${#candidates[@]}" -gt 1 ]; then
        echo "Select a PHP installation:"
        for path in "${candidates[@]}"; do
            echo "${index}: ${path} ($(${path}/bin/php-config --version))"
            index=$((index + 1))
        done
        read -r -p "Choice: " choice
        [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#candidates[@]}" ] || return 1
        PHP_Path=${candidates[choice-1]}
    else
        PHP_Path=${candidates[0]}
    fi
    Cur_PHP_Version=$(${PHP_Path}/bin/php-config --version)
    version_at_least "${Cur_PHP_Version}" 7.4.33 || { Echo_Red "PHP ${Cur_PHP_Version} is below the supported floor 7.4.33."; return 1; }
    PHPFPM_Initd=/etc/init.d/php-fpm
    [ "${PHP_Path}" != /usr/local/php ] && PHPFPM_Initd="/etc/init.d/php-fpm${Cur_PHP_Version%.*}"
    install -d -m 0755 "${PHP_Path}/conf.d"
}

restart_php()
{
    if [ -x "${PHPFPM_Initd}" ]; then
        "${PHPFPM_Initd}" restart
    else
        Echo_Yellow "Extension installed; restart the matching PHP service manually."
    fi
}

install_extension_dependencies()
{
    local extension=$1 packages=()
    case "${PM:-}" in
        yum)
            case "${extension}" in
                ldap) packages=(openldap-devel) ;;
                sodium) packages=(libsodium-devel) ;;
                memcached) packages=(libmemcached-awesome-devel libmemcached-devel) ;;
                imap) packages=(libc-client-devel krb5-devel openssl-devel) ;;
            esac
            if [ "${extension}" = memcached ]; then
                for package in "${packages[@]}"; do
                    yum -y install "${package}" && break
                done
            elif [ "${#packages[@]}" -gt 0 ]; then
                yum -y install "${packages[@]}"
            fi
            ;;
        apt)
            case "${extension}" in
                ldap) packages=(libldap2-dev) ;;
                sodium) packages=(libsodium-dev) ;;
                memcached) packages=(libmemcached-dev) ;;
                imap) packages=(libc-client-dev libkrb5-dev libssl-dev) ;;
            esac
            [ "${#packages[@]}" -eq 0 ] || apt-get --no-install-recommends install -y "${packages[@]}"
            ;;
    esac
}

default_pecl_version()
{
    case "$1" in
        redis) echo 6.3.0 ;;
        apcu) echo 5.1.28 ;;
        imagick) echo 3.8.1 ;;
        memcached) echo 3.4.0 ;;
        memcache) echo 8.2 ;;
        swoole)
            if version_at_least "${Cur_PHP_Version}" 8.1.0; then echo 6.2.2; else echo 5.1.8; fi
            ;;
        imap) echo 1.0.3 ;;
        *) return 1 ;;
    esac
}

install_imagemagick()
{
    local version=$1 archive source_dir
    [ "${version}" != latest ] || version=7.1.2-29
    validate_version "${version}" || { Echo_Red "Invalid ImageMagick version: ${version}"; return 1; }
    archive="ImageMagick-${version}.tar.gz"
    source_dir="ImageMagick-${version}"
    cd "${cur_dir}/src" || return 1
    Download_Files "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${version}.tar.gz" "${archive}" publisher-tls || return 1
    Tar_Cd "${archive}" "${source_dir}" || return 1
    ./configure --prefix=/usr/local/imagemagick --disable-static --with-modules --without-perl || return 1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" || return 1
    make install || return 1
    printf '%s\n' /usr/local/imagemagick/lib > /etc/ld.so.conf.d/imagemagick.conf
    ldconfig
    rm -rf -- "${cur_dir}/src/${source_dir}"
    Echo_Green "ImageMagick ${version} installed."
}

install_pecl_extension()
{
    local package=$1 version=$2 ini_name=${3:-$1} archive source_dir
    local extension_name=$1 extension_dir destination backup ini_file ini_temp ini_backup
    local configure_args=()
    [ "${version}" != latest ] || version=$(default_pecl_version "${package}")
    validate_version "${version}" || { Echo_Red "Invalid extension version: ${version}"; return 1; }
    if [ "${package}" = imap ] && ! version_at_least "${Cur_PHP_Version}" 8.3.0; then
        Echo_Red "PECL imap ${version} requires PHP 8.3+. Use the PHP-bundled imap module with older PHP builds."
        return 1
    fi
    if [ "${package}" = swoole ] && [[ "${version}" == 6.* ]] && ! version_at_least "${Cur_PHP_Version}" 8.1.0; then
        Echo_Red "Swoole 6.x requires PHP 8.1+; choose Swoole 5.1.8 for PHP 7.4/8.0."
        return 1
    fi
    install_extension_dependencies "${package}" || return 1

    archive="${package}-${version}.tgz"
    source_dir="${package}-${version}"
    cd "${cur_dir}/src" || return 1
    Download_Files "https://pecl.php.net/get/${archive}" "${archive}" publisher-tls || return 1
    Tar_Cd "${archive}" "${source_dir}" || return 1
    "${PHP_Path}/bin/phpize" || return 1
    case "${package}" in
        redis) configure_args+=(--enable-redis) ;;
        apcu) configure_args+=(--enable-apcu) ;;
        imagick) [ -d /usr/local/imagemagick ] && configure_args+=(--with-imagick=/usr/local/imagemagick) ;;
        memcached) configure_args+=(--disable-memcached-sasl) ;;
        swoole) configure_args+=(--enable-openssl --enable-sockets --enable-mysqlnd) ;;
        imap) configure_args+=(--with-imap --with-imap-ssl --with-kerberos) ;;
    esac
    ./configure --with-php-config="${PHP_Path}/bin/php-config" "${configure_args[@]}" || return 1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" || return 1
    extension_dir=$("${PHP_Path}/bin/php-config" --extension-dir) || return 1
    destination="${extension_dir}/${extension_name}.so"
    backup="${destination}.lnmp-backup.$$"
    if [ -f "${destination}" ]; then
        cp -p -- "${destination}" "${backup}" || return 1
    else
        backup=''
    fi
    if ! make install; then
        [ -z "${backup}" ] || mv -f -- "${backup}" "${destination}"
        return 1
    fi
    if ! "${PHP_Path}/bin/php" --no-php-ini -d "extension=${destination}" -m | grep -Fxqi "${extension_name}"; then
        if [ -n "${backup}" ]; then
            mv -f -- "${backup}" "${destination}"
        else
            rm -f -- "${destination}"
        fi
        Echo_Red "The new ${package} module failed its isolated PHP load test; the previous module was restored."
        return 1
    fi
    ini_file="${PHP_Path}/conf.d/020-${ini_name}.ini"
    ini_backup="${ini_file}.lnmp-backup.$$"
    if [ -f "${ini_file}" ]; then
        cp -p -- "${ini_file}" "${ini_backup}" || {
            if [ -n "${backup}" ]; then mv -f -- "${backup}" "${destination}"; else rm -f -- "${destination}"; fi
            return 1
        }
    else
        ini_backup=''
    fi
    ini_temp=$(mktemp "${PHP_Path}/conf.d/.020-${ini_name}.XXXXXX") || {
        if [ -n "${backup}" ]; then mv -f -- "${backup}" "${destination}"; else rm -f -- "${destination}"; fi
        [ -z "${ini_backup}" ] || rm -f -- "${ini_backup}"
        return 1
    }
    printf 'extension=%s.so\n' "${extension_name}" > "${ini_temp}"
    chmod 0644 "${ini_temp}"
    if ! mv -f -- "${ini_temp}" "${ini_file}"; then
        rm -f -- "${ini_temp}"
        if [ -n "${backup}" ]; then mv -f -- "${backup}" "${destination}"; else rm -f -- "${destination}"; fi
        [ -z "${ini_backup}" ] || rm -f -- "${ini_backup}"
        return 1
    fi
    rm -rf -- "${cur_dir}/src/${source_dir}"
    if ! restart_php; then
        if [ -n "${backup}" ]; then mv -f -- "${backup}" "${destination}"; else rm -f -- "${destination}"; fi
        if [ -n "${ini_backup}" ]; then mv -f -- "${ini_backup}" "${ini_file}"; else rm -f -- "${ini_file}"; fi
        restart_php >/dev/null 2>&1 || true
        return 1
    fi
    [ -z "${backup}" ] || rm -f -- "${backup}"
    [ -z "${ini_backup}" ] || rm -f -- "${ini_backup}"
    Echo_Green "${package} ${version} installed for PHP ${Cur_PHP_Version}."
}

install_bundled_extension()
{
    local extension=$1 expected_php_version=$2 archive source_root source_path ini_directive=extension
    local configure_flags=()
    if [ "${expected_php_version}" != latest ] && [ "${expected_php_version}" != "${Cur_PHP_Version}" ]; then
        Echo_Red "${extension} follows PHP; requested version must be ${Cur_PHP_Version}."
        return 1
    fi
    if "${PHP_Path}/bin/php" -m | grep -Fxqi "${extension}"; then
        Echo_Green "${extension} is already built into PHP ${Cur_PHP_Version}."
        return 0
    fi
    case "${extension}" in
        exif) configure_flags+=(--enable-exif) ;;
        fileinfo) configure_flags+=(--enable-fileinfo) ;;
        ldap) configure_flags+=(--with-ldap) ;;
        bz2) configure_flags+=(--with-bz2) ;;
        sodium) configure_flags+=(--with-sodium) ;;
        opcache) configure_flags+=(--enable-opcache); ini_directive=zend_extension ;;
        imap) configure_flags+=(--with-imap --with-imap-ssl --with-kerberos) ;;
        *) return 1 ;;
    esac
    install_extension_dependencies "${extension}" || return 1
    archive="php-${Cur_PHP_Version}.tar.bz2"
    source_root="php-${Cur_PHP_Version}"
    source_path="${source_root}/ext/${extension}"
    cd "${cur_dir}/src" || return 1
    Download_Files "https://www.php.net/distributions/${archive}" "${archive}" publisher-tls || return 1
    Tar_Cd "${archive}" "${source_path}" || return 1
    "${PHP_Path}/bin/phpize" || return 1
    ./configure --with-php-config="${PHP_Path}/bin/php-config" "${configure_flags[@]}" || return 1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" && make install || return 1
    printf '%s=%s.so\n' "${ini_directive}" "${extension}" > "${PHP_Path}/conf.d/020-${extension}.ini"
    rm -rf -- "${cur_dir}/src/${source_root}"
    restart_php
    Echo_Green "${extension} from PHP ${Cur_PHP_Version} installed."
}

uninstall_extension()
{
    local name=$1 module_name=$1 ini_name=$1
    [ "${name}" = phpredis ] && module_name=redis && ini_name=redis
    rm -f "${PHP_Path}/conf.d/020-${ini_name}.ini"
    rm -f "$(${PHP_Path}/bin/php-config --extension-dir)/${module_name}.so"
    restart_php
}

uninstall_redis_server()
{
    StartOrStop stop redis 2>/dev/null || true
    Remove_StartUp redis 2>/dev/null || true
    rm -f /etc/init.d/redis /etc/systemd/system/redis.service
    rm -rf -- /usr/local/redis/bin
    systemctl daemon-reload 2>/dev/null || true
    Echo_Green "Redis binaries and service removed. Configuration and data were preserved in /usr/local/redis/etc and /var/lib/redis."
}

uninstall_ioncube_loader()
{
    rm -f "${PHP_Path}/conf.d/001-ioncube.ini"
    restart_php
    Echo_Green "ionCube was disabled for PHP ${Cur_PHP_Version}; shared vendor loader files were preserved."
}

uninstall_sourceguardian_loader()
{
    rm -f "${PHP_Path}/conf.d/001-sourceguardian.ini"
    restart_php
    Echo_Green "SourceGuardian was disabled for PHP ${Cur_PHP_Version}; the vendor loader file was preserved."
}

download_sourceguardian_latest()
{
    local acceptance=$1 machine archive_name previous_dir download_status
    if [ "${acceptance}" != '--accept-sourceguardian-license' ]; then
        Echo_Red 'SourceGuardian requires acceptance of its Loader licence before downloading.'
        Echo_Red 'Read: https://www.sourceguardian.com/termsloaders.html'
        Echo_Red 'Then rerun with the final argument: --accept-sourceguardian-license'
        return 1
    fi
    [ "$(uname -s)" = Linux ] || { Echo_Red 'Automatic SourceGuardian download is supported only on Linux.'; return 1; }
    machine=$(uname -m)
    case "${machine}" in
        x86_64|amd64) archive_name='loaders.linux-x86_64.tar.gz' ;;
        armv7l|armv7*|armhf) archive_name='loaders.linux-armhf.tar.gz' ;;
        aarch64|arm64) archive_name='loaders.linux-aarch64.tar.gz' ;;
        *) Echo_Red "SourceGuardian has no supported automatic Linux loader bundle for architecture ${machine}."; return 1 ;;
    esac

    SG_DOWNLOAD_DIR=$(mktemp -d "${cur_dir}/src/sourceguardian-download.XXXXXX") || return 1
    previous_dir=${PWD}
    cd "${SG_DOWNLOAD_DIR}" || { rm -rf -- "${SG_DOWNLOAD_DIR}"; SG_DOWNLOAD_DIR=''; return 1; }
    Echo_Yellow 'Downloading confirms that you have read and accepted the SourceGuardian Loader licence.'
    Download_Files "https://www.sourceguardian.com/loaders/download/${archive_name}" "${archive_name}" && \
        Download_Files "https://www.sourceguardian.com/loaders/download/${archive_name}.md5" "${archive_name}.md5" publisher-tls
    download_status=$?
    if ! cd "${previous_dir}"; then
        cd "${cur_dir}" 2>/dev/null || true
        rm -rf -- "${SG_DOWNLOAD_DIR}"
        SG_DOWNLOAD_DIR=''
        return 1
    fi
    if [ "${download_status}" -ne 0 ]; then
        rm -rf -- "${SG_DOWNLOAD_DIR}"
        SG_DOWNLOAD_DIR=''
        return 1
    fi
    SG_DOWNLOADED_ARCHIVE="${SG_DOWNLOAD_DIR}/${archive_name}"
}

install_sourceguardian_archive()
{
    local archive=$1 checksum_file expected actual php_branch work_dir loader extension_dir destination output test_status
    if [ ! -f "${archive}" ]; then
        Echo_Red "SourceGuardian archive not found: ${archive}"
        return 1
    fi
    case "${archive}" in
        /*.tar.gz|/*.tgz|/*.tar.bz2) ;;
        *) Echo_Red 'SourceGuardian archive must be an absolute path ending in .tar.gz, .tgz or .tar.bz2.'; return 1 ;;
    esac
    checksum_file="${archive}.md5"
    [ -f "${checksum_file}" ] || {
        Echo_Red "Missing vendor checksum file: ${checksum_file}"
        return 1
    }
    expected=$(head -n1 "${checksum_file}" | awk '{print tolower($1)}')
    [[ "${expected}" =~ ^[0-9a-f]{32}$ ]] || { Echo_Red 'Invalid SourceGuardian MD5 file.'; return 1; }
    if command -v md5sum >/dev/null 2>&1; then
        actual=$(md5sum "${archive}" | awk '{print $1}')
    else
        actual=$(openssl dgst -md5 "${archive}" | awk '{print tolower($NF)}')
    fi
    [ "${actual}" = "${expected}" ] || { Echo_Red 'SourceGuardian vendor checksum mismatch.'; return 1; }
    Validate_Archive "${archive}" || return 1
    work_dir=$(mktemp -d "${cur_dir}/src/sourceguardian.XXXXXX") || return 1
    case "${archive}" in
        *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${work_dir}" || { rm -rf -- "${work_dir}"; return 1; } ;;
        *.tar.bz2) tar -xjf "${archive}" -C "${work_dir}" || { rm -rf -- "${work_dir}"; return 1; } ;;
    esac
    php_branch=${Cur_PHP_Version%.*}
    loader=$(find "${work_dir}" -type f -name "ixed.${php_branch}.lin" -print -quit)
    [ -n "${loader}" ] || {
        rm -rf -- "${work_dir}"
        Echo_Red "The vendor archive has no Linux loader for PHP ${php_branch}."
        return 1
    }
    extension_dir=$(${PHP_Path}/bin/php-config --extension-dir)
    destination="${extension_dir}/ixed.${php_branch}.lin"
    install -m 0644 "${loader}" "${destination}" || { rm -rf -- "${work_dir}"; return 1; }
    output=$(${PHP_Path}/bin/php --no-php-ini -d "extension=${destination}" \
        -r 'exit(function_exists("sg_load") ? 0 : 1);' 2>&1)
    test_status=$?
    if [ "${test_status}" -ne 0 ] || echo "${output}" | grep -Eqi 'unable to load|failed loading|undefined symbol'; then
        rm -f "${destination}"
        rm -rf -- "${work_dir}"
        Echo_Red "SourceGuardian loader validation failed: ${output}"
        return 1
    fi
    printf 'extension=%s\n' "${destination}" > "${PHP_Path}/conf.d/001-sourceguardian.ini"
    rm -rf -- "${work_dir}"
    restart_php
    Echo_Green "SourceGuardian ${php_branch} loader installed for PHP ${Cur_PHP_Version}."
}

install_sourceguardian()
{
    local archive=$1 install_status
    if [ "${archive}" != latest ]; then
        install_sourceguardian_archive "${archive}"
        return $?
    fi

    SG_DOWNLOAD_DIR=''
    SG_DOWNLOADED_ARCHIVE=''
    download_sourceguardian_latest "${sourceguardian_license_acceptance}" || return 1
    install_sourceguardian_archive "${SG_DOWNLOADED_ARCHIVE}"
    install_status=$?
    case "${SG_DOWNLOAD_DIR}" in
        "${cur_dir}/src/sourceguardian-download."*) rm -rf -- "${SG_DOWNLOAD_DIR}" ;;
    esac
    SG_DOWNLOAD_DIR=''
    SG_DOWNLOADED_ARCHIVE=''
    return "${install_status}"
}

install_redis_stack()
{
    local redis_version=$1
    [ "${redis_version}" != latest ] || redis_version=8.10.0
    validate_version "${redis_version}" || return 1
    Redis_Stable_Ver="redis-${redis_version}"
    PHPRedis_Ver='redis-6.3.0'
    Addons_Get_PHP_Ext_Dir() { Cur_PHP_Version=$(${PHP_Path}/bin/php-config --version); zend_ext_dir="$(${PHP_Path}/bin/php-config --extension-dir)/"; }
    Restart_PHP() { restart_php; }
    Press_Start() { :; }
    . include/redis.sh
    Install_Redis
}

install_ioncube()
{
    [ "${requested_version}" = latest ] || Echo_Yellow "ionCube publishes one current loader bundle; the requested label is verified by loader compatibility, not a versioned URL."
    . include/ionCube.sh
    Addons_Get_PHP_Ext_Dir() { Cur_PHP_Version=$(${PHP_Path}/bin/php-config --version); zend_ext_dir="$(${PHP_Path}/bin/php-config --extension-dir)/"; }
    Restart_PHP() { restart_php; }
    Press_Start() { :; }
    Get_OS_Bit
    Install_ionCube
}

case "${action}" in
    list)
        usage
        exit 0
        ;;
    install|upgrade|uninstall) ;;
    *) usage; exit 2 ;;
esac

case "${addon}" in
    phpredis|apcu|imagick|imagemagick|memcached|memcache|swoole|imap|exif|fileinfo|ldap|bz2|sodium|opcache|redis|ioncube|sourceguardian|sg) ;;
    eaccelerator|xcache)
        Echo_Red "${addon} is obsolete and is intentionally unsupported."
        exit 3
        ;;
    *) usage; exit 2 ;;
esac

select_php || exit 1
if [ "${action}" = uninstall ]; then
    case "${addon}" in
        redis) uninstall_redis_server ;;
        ioncube) uninstall_ioncube_loader ;;
        sourceguardian|sg) uninstall_sourceguardian_loader ;;
        imagemagick) Echo_Red "ImageMagick is shared by PHP versions; automatic removal is intentionally disabled."; exit 3 ;;
        *) uninstall_extension "${addon}" ;;
    esac
    exit $?
fi

case "${addon}" in
    phpredis) install_pecl_extension redis "${requested_version}" redis ;;
    imagick)
        [ -x /usr/local/imagemagick/bin/MagickWand-config ] || install_imagemagick latest || exit 1
        install_pecl_extension imagick "${requested_version}"
        ;;
    imagemagick) install_imagemagick "${requested_version}" ;;
    apcu|memcached|memcache|swoole) install_pecl_extension "${addon}" "${requested_version}" ;;
    imap)
        if version_at_least "${Cur_PHP_Version}" 8.3.0; then
            install_pecl_extension imap "${requested_version}"
        else
            install_bundled_extension imap "${requested_version}"
        fi
        ;;
    exif|fileinfo|ldap|bz2|sodium|opcache) install_bundled_extension "${addon}" "${requested_version}" ;;
    redis) install_redis_stack "${requested_version}" ;;
    ioncube) install_ioncube ;;
    sourceguardian|sg) install_sourceguardian "${requested_version}" ;;
esac
