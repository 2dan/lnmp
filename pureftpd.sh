#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script!"
    exit 1
fi
clear
echo "+----------------------------------------------------------+"
echo "|          Pureftpd for LNMP,  Written by Licess           |"
echo "+----------------------------------------------------------+"
echo "|This script is a tool to install pureftpd for LNMP        |"
echo "+----------------------------------------------------------+"
echo "|       Independent hardened maintenance build             |"
echo "+----------------------------------------------------------+"
echo "|Usage: ./pureftpd.sh                                      |"
echo "+----------------------------------------------------------+"
cur_dir=$(pwd)
action=$1

. lnmp.conf
. include/main.sh
. include/init.sh

Get_Dist_Name

Install_Pureftpd()
{
    Press_Install

    Echo_Blue "Installing dependent packages..."
    if [ "$PM" = "yum" ]; then
        for packages in make gcc gcc-c++ gcc-g77 openssl openssl-devel bzip2;
        do yum -y install $packages; done
    elif [ "$PM" = "apt" ]; then
        apt-get update -y
        [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
        for packages in build-essential gcc g++ make openssl libssl-dev bzip2;
        do apt-get --no-install-recommends install -y $packages; done
    fi
    Echo_Blue "Download files..."
    cd "${cur_dir}/src" || return 1
    Download_Files "https://download.pureftpd.org/pure-ftpd/releases/${Pureftpd_Ver}.tar.bz2" "${Pureftpd_Ver}.tar.bz2"
    if [ $? -ne 0 ]; then
        Download_Files "https://download.pureftpd.org/pure-ftpd/releases/obsolete/${Pureftpd_Ver}.tar.bz2" "${Pureftpd_Ver}.tar.bz2" || return 1
    fi

    Echo_Blue "Installing pure-ftpd..."
    Tar_Cd "${Pureftpd_Ver}.tar.bz2" "${Pureftpd_Ver}" || return 1
    ./configure --prefix=/usr/local/pureftpd CFLAGS=-O2 --with-puredb --with-quotas --with-cookie --with-virtualhosts --with-diraliases --with-sysquotas --with-ratios --with-altlog --with-paranoidmsg --with-shadow --with-welcomemsg --with-throttling --with-uploadscript --with-language=english --with-rfc2640 --with-ftpwho --with-tls || return 1

    Make_Install || return 1

    Echo_Blue "Copy configure files..."
    install -d -m 0750 /usr/local/pureftpd/etc
    \cp "${cur_dir}/conf/pure-ftpd.conf" /usr/local/pureftpd/etc/pure-ftpd.conf
    if [ ! -s /usr/local/pureftpd/etc/pure-ftpd.pem ]; then
        ftp_cert_name=$(hostname -f 2>/dev/null || hostname)
        ftp_cert_name=${ftp_cert_name//[^A-Za-z0-9.-]/}
        [ -n "${ftp_cert_name}" ] || ftp_cert_name=localhost
        umask 077
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -sha256 -nodes -days 825 \
            -subj "/CN=${ftp_cert_name}" -keyout /usr/local/pureftpd/etc/.pure-ftpd.key \
            -out /usr/local/pureftpd/etc/.pure-ftpd.crt || return 1
        { cat /usr/local/pureftpd/etc/.pure-ftpd.key; cat /usr/local/pureftpd/etc/.pure-ftpd.crt; } \
            > /usr/local/pureftpd/etc/pure-ftpd.pem || return 1
        rm -f -- /usr/local/pureftpd/etc/.pure-ftpd.key /usr/local/pureftpd/etc/.pure-ftpd.crt
        chmod 0600 /usr/local/pureftpd/etc/pure-ftpd.pem
        Echo_Yellow "Pure-FTPd requires TLS. Replace its self-signed certificate with a trusted PEM when available."
    fi
    if [ -L /etc/init.d/pureftpd ]; then
        rm -f /etc/init.d/pureftpd
    fi
    \cp ${cur_dir}/init.d/init.d.pureftpd /etc/init.d/pureftpd
    \cp ${cur_dir}/init.d/pureftpd.service /etc/systemd/system/pureftpd.service
    chmod +x /etc/init.d/pureftpd
    touch /usr/local/pureftpd/etc/pureftpd.passwd
    touch /usr/local/pureftpd/etc/pureftpd.pdb

    StartUp pureftpd

    cd ..
    rm -rf -- "${cur_dir}/src/${Pureftpd_Ver}"

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=ftp || return 1
        firewall-cmd --permanent --add-port=20000-30000/tcp || return 1
        firewall-cmd --reload || return 1
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
        ufw allow 21/tcp || return 1
        ufw allow 20000:30000/tcp || return 1
    elif command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport 21 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 21 -j ACCEPT
        iptables -C INPUT -p tcp --dport 20000:30000 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 20000:30000 -j ACCEPT
        Echo_Yellow "FTP rules were added to the active iptables ruleset; persistence remains under administrator control."
    else
        Echo_Yellow "No active supported firewall manager was found; FTP ports were not opened."
    fi

    if [ ! -s /bin/lnmp ]; then
        \cp ${cur_dir}/conf/lnmp /bin/lnmp
        chmod +x /bin/lnmp
    fi
    id -u www
    if [ $? -ne 0 ]; then
        groupadd www
        useradd -s /sbin/nologin -g www www
    fi

    if [[ -s /usr/local/pureftpd/sbin/pure-ftpd && -s /usr/local/pureftpd/etc/pure-ftpd.conf && -s /etc/init.d/pureftpd ]]; then
        Echo_Blue "Starting pureftpd..."
        /etc/init.d/pureftpd start
        Echo_Green "+----------------------------------------------------------------------+"
        Echo_Green "| Install Pure-FTPd completed,enjoy it!"
        Echo_Green "| =>use command: lnmp ftp {add|list|del|show} to manage FTP users."
        Echo_Green "+----------------------------------------------------------------------+"
        Echo_Green "| Independent hardened maintenance build"
        Echo_Green "+----------------------------------------------------------------------+"
    else
        Echo_Red "Pureftpd install failed!"
    fi
}

Uninstall_Pureftpd()
{
    if [ ! -f /usr/local/pureftpd/sbin/pure-ftpd ]; then
        Echo_Red "Pureftpd was not installed!"
        exit 1
    fi
    echo "Stop pureftpd..."
    /etc/init.d/pureftpd stop
    echo "Remove service..."
    Remove_StartUp pureftpd
    echo "Delete files..."
    rm -f /etc/init.d/pureftpd
    rm -rf -- /usr/local/pureftpd
    echo "Pureftpd uninstall completed."
}

if [ "${action}" = "uninstall" ]; then
    Uninstall_Pureftpd
else
    Install_Pureftpd 2>&1 | tee /root/pureftpd-install.log
fi
