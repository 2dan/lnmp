#!/usr/bin/env bash

Upgrade_phpMyAdmin()
{
    phpMyAdmin_Version=""
    echo "You can get version number from https://www.phpmyadmin.net/downloads/"
    read -p "Please enter phpMyAdmin version you want, (example: 4.8.0 ): " phpMyAdmin_Version
    if [ "${phpMyAdmin_Version}" = "" ]; then
        echo "Error: You must enter a phpMyAdmin version!!"
        exit 1
    fi
    if ! echo "${phpMyAdmin_Version}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        Echo_Red "Error: invalid phpMyAdmin version format."
        exit 1
    fi
    if [ "$(printf '%s\n' "${phpMyAdmin_Version}" 5.2.0 | sort -V | head -n1)" != 5.2.0 ]; then
        Echo_Red "phpMyAdmin 5.2.0 is the minimum supported upgrade target."
        exit 1
    fi
    echo "+---------------------------------------------------------+"
    echo "|   You will upgrade phpMyAdmin version to ${phpMyAdmin_Version}"
    echo "+---------------------------------------------------------+"

    Press_Start

    echo "============================check files=================================="
    cd ${cur_dir}/src
    PMA_Archive="phpMyAdmin-${phpMyAdmin_Version}-all-languages.tar.xz"
    if ! Download_Files "https://files.phpmyadmin.net/phpMyAdmin/${phpMyAdmin_Version}/${PMA_Archive}" "${PMA_Archive}" publisher-tls; then
        Echo_Red "Error: invalid phpMyAdmin version or publisher download failed."
        exit 1
    fi
    echo "============================check files=================================="
    if [ -s /root/.lnmp-phpmyadmin-path ]; then
        Old_PMA_Name=$(tr -d '/\r\n' </root/.lnmp-phpmyadmin-path)
    else
        Old_PMA_Name=phpmyadmin
    fi
    if ! echo "${Old_PMA_Name}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
        Echo_Red "Error: invalid existing phpMyAdmin path."
        exit 1
    fi
    Old_PMA_Dir="${Default_Website_Dir}/${Old_PMA_Name}"
    if [ -d "${Old_PMA_Dir}" ]; then
        echo "Backup old phpMyAdmin outside the web root..."
        install -d -m 0700 /root/lnmp-backups
        mv "${Old_PMA_Dir}" "/root/lnmp-backups/${Old_PMA_Name}-${Upgrade_Date}"
    fi
    echo "Uncompress phpMyAdmin-${phpMyAdmin_Version}-all-languages.tar.xz ..."
    Tar_Cd "${PMA_Archive}" "phpMyAdmin-${phpMyAdmin_Version}-all-languages" || exit 1
    cd "${cur_dir}/src" || exit 1
    PMA_Dir_Name="pma_$(openssl rand -hex 8)" || exit 1
    [[ "${PMA_Dir_Name}" =~ ^pma_[0-9a-f]{16}$ ]] || exit 1
    PMA_Dir="${Default_Website_Dir}/${PMA_Dir_Name}"
    mv "phpMyAdmin-${phpMyAdmin_Version}-all-languages" "${PMA_Dir}"
    \cp "${cur_dir}/conf/config.inc.php" "${PMA_Dir}/config.inc.php"
    PMA_Blowfish=$(openssl rand -hex 32) || exit 1
    [[ "${PMA_Blowfish}" =~ ^[0-9a-f]{64}$ ]] || exit 1
    sed -i "s/__LNMP_GENERATED_BLOWFISH_SECRET__/${PMA_Blowfish}/g" "${PMA_Dir}/config.inc.php" || exit 1
    grep -Fq "${PMA_Blowfish}" "${PMA_Dir}/config.inc.php" || exit 1
    install -d -o www -g www -m 0700 /var/lib/phpmyadmin/tmp
    chown -R root:www "${PMA_Dir}"
    find "${PMA_Dir}" -type d -exec chmod 0750 {} \;
    find "${PMA_Dir}" -type f -exec chmod 0640 {} \;
    umask 077
    printf '/%s/\n' "${PMA_Dir_Name}" > /root/.lnmp-phpmyadmin-path
    Echo_Green "======== upgrade phpMyAdmin completed ======"
}
