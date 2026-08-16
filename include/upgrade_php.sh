#!/usr/bin/env bash

Upgrade_PHP()
{
    local current_version target_version backup_dir
    [ -x /usr/local/php/bin/php-config ] || { Echo_Red "Main PHP installation not found."; return 1; }
    current_version=$(/usr/local/php/bin/php-config --version)
    read -r -p "Target PHP version [current ${current_version}]: " target_version
    [ -n "${target_version}" ] || target_version=${current_version}
    [[ "${target_version}" =~ ^[0-9]+([.][0-9]+){2}$ ]] || { Echo_Red "Invalid PHP version."; return 1; }
    if [ "$(printf '%s\n' "${target_version}" 7.4.33 | sort -V | head -n1)" != 7.4.33 ]; then
        Echo_Red "PHP 7.4.33 is the minimum supported version."
        return 1
    fi
    case "${target_version}" in
        7.4.*|8.0.*|8.1.*|8.2.*|8.3.*|8.4.*|8.5.*) ;;
        *) Echo_Red "Supported branches are PHP 7.4 and 8.0-8.5."; return 1 ;;
    esac

    backup_dir="/usr/local/php-backup-${Upgrade_Date}"
    install -d -m 0700 "${backup_dir}"
    \cp -a /usr/local/php/etc "${backup_dir}/"
    /etc/init.d/php-fpm stop 2>/dev/null || true
    Php_Ver="php-${target_version}"
    cd "${cur_dir}/src" || return 1
    Download_Files "https://www.php.net/distributions/${Php_Ver}.tar.bz2" "${Php_Ver}.tar.bz2" publisher-tls || return 1
    Check_PHP_Option
    Install_PHP_Supported || return 1
    if declare -F Tune_PHP_FPM >/dev/null 2>&1; then Tune_PHP_FPM /usr/local/php; fi
    /etc/init.d/php-fpm restart
    Echo_Green "PHP upgraded to ${target_version}; previous configuration is in ${backup_dir}."
    Echo_Yellow "Reinstall required third-party extensions with ./addons.sh upgrade <name> <version>."
}
