#!/usr/bin/env bash

Backup_MariaDB()
{
    umask 077
    echo "Starting backup all databases..."
    echo "If the database is large, the backup time will be longer."
    /usr/local/mariadb/bin/mysqldump --defaults-file="${LNMP_MYCNF}" --all-databases --routines --events --triggers --hex-blob > "/root/mariadb_all_backup${Upgrade_Date}.sql"
    if [ $? -eq 0 ]; then
        echo "MariaDB databases backup successfully.";
    else
        echo "MariaDB databases backup failed,Please backup databases manually!"
        exit 1
    fi
    lnmp stop

    mv /usr/local/mariadb /usr/local/oldmariadb${Upgrade_Date}
    mv /etc/init.d/mariadb /usr/local/oldmariadb${Upgrade_Date}/init.d.mariadb.bak.${Upgrade_Date}
    mv /etc/my.cnf /usr/local/oldmariadb${Upgrade_Date}/my.cnf.mariadb.bak.${Upgrade_Date}
    if [ "${MariaDB_Data_Dir}" != "/usr/local/mariadb/var" ]; then
        mv ${MariaDB_Data_Dir} ${MariaDB_Data_Dir}${Upgrade_Date}
    fi
}

Upgrade_MariaDB()
{
    Check_DB
    Validate_Install_Path "${MariaDB_Data_Dir}" 'MariaDB data directory' || exit 1
    if [ "${Is_MySQL}" = "y" ]; then
        Echo_Red "Current database was MySQL, Can't run MariaDB upgrade script."
        exit 1
    fi

    Verify_DB_Password

    cur_mariadb_version=`/usr/local/mariadb/bin/mysql_config --version`
    mariadb_version=""
    echo "Current MariaDB Version:${cur_mariadb_version}"
    echo "You can get version number from https://downloads.mariadb.org/"
    Echo_Yellow "Please enter MariaDB Version you want."
    read -p "(example: 12.3.2): " mariadb_version
    if [ "${mariadb_version}" = "" ]; then
        echo "Error: You must input MariaDB Version!!"
        exit 1
    fi
    if ! echo "${mariadb_version}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        Echo_Red "Error: invalid MariaDB version format."
        exit 1
    fi
    case "${mariadb_version}" in
        10.6.*|10.11.*|11.4.*|11.8.*|12.3.*) ;;
        *) Echo_Red "Supported MariaDB upgrade branches are 10.6, 10.11, 11.4, 11.8 and 12.3."; exit 1 ;;
    esac

    Select_Database_Package_Mode mariadb "${mariadb_version}" "${DB_Install_Mode:-auto}" || exit 1

    #do you want to install the InnoDB Storage Engine?
    echo "==========================="

    InstallInnodb="y"
    Echo_Yellow "Tune both InnoDB and MyISAM? Choose n for MyISAM-only tuning (InnoDB remains available)."
    read -r -p "(Default y): " InstallInnodb

    case "${InstallInnodb}" in
    [yY][eE][sS]|[yY])
        echo "You will install the InnoDB Storage Engine"
        InstallInnodb="y"
        ;;
    [nN][oO]|[nN])
        echo "MyISAM-only tuning selected; InnoDB remains available for system and existing tables."
        InstallInnodb="n"
        ;;
    *)
        echo "No input, The InnoDB Storage Engine will enable."
        InstallInnodb="y"
    esac

    echo "====================================================================="
    echo "You will upgrade MariaDB V${cur_mariadb_version} to V${mariadb_version}"
    echo "====================================================================="

    Press_Start

    echo "============================check files=================================="
    cd ${cur_dir}/src
    if [ "${Bin}" = "y" ]; then
        MariaDB_FileName="mariadb-${mariadb_version}-linux-systemd-${DB_ARCH}"
    else
        MariaDB_FileName="mariadb-${mariadb_version}"
    fi
    if [ "${Bin}" = "y" ]; then
        mariadb_url="https://archive.mariadb.org/mariadb-${mariadb_version}/bintar-linux-systemd-x86_64/${MariaDB_FileName}.tar.gz"
    else
        mariadb_url="https://archive.mariadb.org/mariadb-${mariadb_version}/source/${MariaDB_FileName}.tar.gz"
    fi
    if ! Download_Files "${mariadb_url}" "${MariaDB_FileName}.tar.gz" publisher-tls; then
        Echo_Red "Error: invalid version or publisher download failed."
        exit 1
    fi
    echo "============================check files=================================="

    Backup_MariaDB

    if [ "${Bin}" = "y" ]; then
        Echo_Blue "[+] Starting upgrade mariadb-${mariadb_version} Using Generic Binaries..."
        Tar_Cd "${MariaDB_FileName}.tar.gz" "${MariaDB_FileName}" || exit 1
        mkdir /usr/local/mariadb
        mv ${MariaDB_FileName}/* /usr/local/mariadb/
    else
        Echo_Blue "[+] Starting upgrade mariadb-${mariadb_version} Using Source code..."
        Tar_Cd "mariadb-${mariadb_version}.tar.gz" "mariadb-${mariadb_version}" || exit 1
        MariaDB_WITHSSL
        cmake -DCMAKE_INSTALL_PREFIX=/usr/local/mariadb -DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock -DEXTRA_CHARSETS=all -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DWITH_READLINE=1 -DENABLED_LOCAL_INFILE=OFF -DWITHOUT_TOKUDB=1
        Make_Install
    fi

    groupadd mariadb
    useradd -s /sbin/nologin -M -g mariadb mariadb

cat > /etc/my.cnf<<EOF
[client]
#password	= your_password
port		= 3306
socket		= /run/mysqld/mysqld.sock

[mysqld]
port		= 3306
socket		= /run/mysqld/mysqld.sock
user    = mariadb
basedir = /usr/local/mariadb
datadir = ${MariaDB_Data_Dir}
bind_address = 127.0.0.1
skip_name_resolve = ON
local_infile = OFF
log_error = ${MariaDB_Data_Dir}/mariadb.err
pid-file = ${MariaDB_Data_Dir}/mariadb.pid
skip-external-locking
key_buffer_size = 16M
max_allowed_packet = 1M
table_open_cache = 64
sort_buffer_size = 512K
net_buffer_length = 8K
read_buffer_size = 256K
read_rnd_buffer_size = 512K
myisam_sort_buffer_size = 8M
thread_cache_size = 8
query_cache_size = 8M
tmp_table_size = 16M

#skip-networking
max_connections = 500
max_connect_errors = 100
open_files_limit = 65535

log-bin=mysql-bin
binlog_format=mixed
server-id	= 1
expire_logs_days = 10

default_storage_engine = InnoDB
#innodb_file_per_table = 1
#innodb_data_home_dir = ${MariaDB_Data_Dir}
#innodb_data_file_path = ibdata1:10M:autoextend
#innodb_log_group_home_dir = ${MariaDB_Data_Dir}
#innodb_buffer_pool_size = 16M
#innodb_log_file_size = 5M
#innodb_log_buffer_size = 8M
#innodb_flush_log_at_trx_commit = 1
#innodb_lock_wait_timeout = 50

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[myisamchk]
key_buffer_size = 20M
sort_buffer_size = 20M
read_buffer = 2M
write_buffer = 2M

[mysqlhotcopy]
interactive-timeout

${MySQLMAOpt}
EOF
    if [ "${InstallInnodb}" = "y" ]; then
        sed -i 's/^#innodb/innodb/g' /etc/my.cnf
    else
        sed -i '/^default_storage_engine/d' /etc/my.cnf
        sed -i '/skip-external-locking/i\default_storage_engine = MyISAM' /etc/my.cnf
    fi
    MySQL_Opt
    if [ -d "${MariaDB_Data_Dir}" ]; then
        rm -rf -- "${MariaDB_Data_Dir:?}"/*
    else
        mkdir -p -- "${MariaDB_Data_Dir}"
    fi
    chown -R mariadb:mariadb /usr/local/mariadb
    Initialize_MariaDB_Data_Dir || return 1
    chown -R mariadb:mariadb -- "${MariaDB_Data_Dir}"
    \cp /usr/local/mariadb/support-files/mysql.server /etc/init.d/mariadb
    chmod 755 /etc/init.d/mariadb

    Mariadb_Sec_Setting
    /etc/init.d/mariadb start

    echo "Restore backup databases..."
    if ! /usr/local/mariadb/bin/mysql --defaults-file="${LNMP_MYCNF}" < "/root/mariadb_all_backup${Upgrade_Date}.sql"; then
        Echo_Red "Database restore failed; the backup and previous installation were preserved."
        return 1
    fi
    echo "Repair databases..."
    /usr/local/mariadb/bin/mysql_upgrade --defaults-file="${LNMP_MYCNF}" || return 1

    /etc/init.d/mariadb stop
    TempMycnf_Clean
    cd "${cur_dir}" || return 1
    rm -rf -- "${cur_dir}/src/mariadb-${mariadb_version}"

    lnmp start
    if [[ -s /usr/local/mariadb/bin/mysql && -s /usr/local/mariadb/bin/mysqld_safe && -s /etc/my.cnf ]]; then
        Echo_Green "======== upgrade MariaDB completed ======"
    else
        Echo_Red "======== upgrade MariaDB failed ======"
        Echo_Red "upgrade MariaDB log: /root/upgrade_mariadb${Upgrade_Date}.log"
        echo "You upload upgrade_mariadb${Upgrade_Date}.log to LNMP Forum for help."
    fi
}
