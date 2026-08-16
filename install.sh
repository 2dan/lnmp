#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script, please use root to install lnmp"
    exit 1
fi

cur_dir=$(pwd)
action=${1:-lnmp}

LNMP_Ver='2.3-hardened'
. lnmp.conf
. include/version.sh
. include/main.sh
. include/init.sh
. include/mysql.sh
. include/mariadb.sh
. include/php.sh
. include/nginx.sh
. include/end.sh
. include/only.sh
. include/multiplephp.sh
. include/tuning.sh

Get_Dist_Name

if [ "${DISTRO}" = "unknow" ]; then
    Echo_Red "Unable to get Linux distribution name, or do NOT support the current distribution."
    exit 1
fi

if [ "${action}" = "lnmp" ]; then
    if [ -f /bin/lnmp ]; then
        Echo_Red "You have installed LNMP!"
        echo -e "If you want to reinstall LNMP, please BACKUP your data.\nand run uninstall script: ./uninstall.sh before you install."
        exit 1
    fi
fi

Check_LNMPConf

clear
echo "+------------------------------------------------------------------------+"
echo "|          LNMP V${LNMP_Ver} for ${DISTRO} Linux Server, Written by Licess          |"
echo "+------------------------------------------------------------------------+"
echo "|             A tool to compile and install LNMP on Linux               |"
echo "+------------------------------------------------------------------------+"
echo "|              Independent hardened maintenance build                    |"
echo "+------------------------------------------------------------------------+"

Init_Install()
{
    Press_Install
    Print_APP_Ver
    Get_Dist_Version
    Print_Sys_Info
    Check_Hosts || exit 1
    Check_CMPT
    if [ "${CheckMirror}" != "n" ]; then
        Modify_Source
    fi
    Add_Swap
    Set_Timezone
    if [ "$PM" = "yum" ]; then
        CentOS_InstallNTP
        CentOS_Remove_Conflicting_Packages
        CentOS_Dependent
    elif [ "$PM" = "apt" ]; then
        Deb_InstallNTP
        Xen_Hwcap_Setting
        Deb_Remove_Conflicting_Packages
        Deb_Dependent
    fi
    Disable_Selinux
    Check_Download
    Install_Libiconv
    Install_Freetype
    Install_Pcre
    if [ "$PM" = "yum" ]; then
        CentOS_Lib_Opt
    elif [ "$PM" = "apt" ]; then
        Deb_Lib_Opt
    fi
    if [ "${DBSelect}" = "4" ]; then
        Install_MySQL_57
    elif [ "${DBSelect}" = "5" ]; then
        Install_MySQL_80
    elif [ "${DBSelect}" = "6" ]; then
        Install_MySQL_84
    elif [ "${DBSelect}" = "7" ]; then
        Install_MySQL_84
    elif [[ "${DBSelect}" =~ ^1[0-4]$ ]]; then
        Install_MariaDB_106
    fi
    TempMycnf_Clean
    Clean_DB_Src_Dir
    Check_PHP_Option
}

Install_PHP()
{
    if [ "${PHPSelect}" = "10" ]; then
        Install_PHP_74
    elif [ "${PHPSelect}" = "11" ]; then
        Install_PHP_80
    elif [ "${PHPSelect}" = "12" ]; then
        Install_PHP_81
    elif [ "${PHPSelect}" = "13" ]; then
        Install_PHP_82
    elif [ "${PHPSelect}" = "14" ]; then
        Install_PHP_83
    elif [ "${PHPSelect}" = "15" ]; then
        Install_PHP_84
    elif [ "${PHPSelect}" = "16" ]; then
        Install_PHP_85
    fi
    Clean_PHP_Src_Dir
}

LNMP_Stack()
{
    Init_Install
    Install_PHP
    LNMP_PHP_Opt
    Install_Nginx
    Apply_Runtime_Tuning
    Creat_PHP_Tools
    Add_Iptables_Rules
    Add_LNMP_Startup
    Check_LNMP_Install
}

case "${action}" in
    lnmp)
        Dispaly_Selection
        LNMP_Stack 2>&1 | tee /root/lnmp-install.log
        ;;
    nginx)
        Install_Only_Nginx 2>&1 | tee /root/nginx-install.log
        ;;
    db)
        Install_Only_Database
        ;;
    mphp)
        Install_Multiplephp
        ;;
    *)
        Echo_Red "Usage: $0 {lnmp|nginx|db|mphp}"
        ;;
esac

exit
