#!/usr/bin/env bash

Backup_MySQL()
{
    umask 077
    echo "Starting backup all databases..."
    echo "If the database is large, the backup time will be longer."
    /usr/local/mysql/bin/mysqldump --defaults-file="${LNMP_MYCNF}" --all-databases --routines --events --triggers --hex-blob > "/root/mysql_all_backup${Upgrade_Date}.sql"
    if [ $? -eq 0 ]; then
        echo "MySQL databases backup successfully.";
    else
        echo "MySQL databases backup failed,Please backup databases manually!"
        exit 1
    fi
    lnmp stop
    mv /usr/local/mysql /usr/local/oldmysql${Upgrade_Date}
    mv /etc/init.d/mysql /usr/local/oldmysql${Upgrade_Date}/init.d.mysql.bak.${Upgrade_Date}
    mv /etc/my.cnf /usr/local/oldmysql${Upgrade_Date}/my.cnf.bak.${Upgrade_Date}
    if [ "${MySQL_Data_Dir}" != "/usr/local/mysql/var" ]; then
        mv ${MySQL_Data_Dir} ${MySQL_Data_Dir}${Upgrade_Date}
    fi
}

Upgrade_MySQL57()
{
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Generic Binaries..."
        Tar_Cd ${mysql_src}
        mkdir /usr/local/mysql
        mv mysql-${mysql_version}-linux-glibc2.12-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Source code..."
        if [ "${isOpenSSL3}" = "y" ]; then
            Install_Openssl_New
            MySQL_WITH_SSL='-DWITH_SSL=/usr/local/openssl3'
        else
            MySQL_WITH_SSL=''
        fi
        Tar_Cd ${mysql_src} mysql-${mysql_version}
        Install_Boost
        if echo "${Rocky_Version}" | grep -Eqi "^9"; then
            sed -i 's@^INCLUDE(cmake/abi_check.cmake)@#INCLUDE(cmake/abi_check.cmake)@' CMakeLists.txt
        fi
        cmake -DCMAKE_INSTALL_PREFIX=/usr/local/mysql -DSYSCONFDIR=/etc -DWITH_MYISAM_STORAGE_ENGINE=1 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DWITH_PARTITION_STORAGE_ENGINE=1 -DWITH_FEDERATED_STORAGE_ENGINE=1 -DEXTRA_CHARSETS=all -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DENABLED_LOCAL_INFILE=OFF ${MySQL_WITH_SSL} ${MySQL_WITH_BOOST}
        Make_Install
    fi

    groupadd mysql
    useradd -s /sbin/nologin -M -g mysql mysql

cat > /etc/my.cnf<<EOF
[client]
#password   = your_password
port        = 3306
socket      = /run/mysqld/mysqld.sock

[mysqld]
port        = 3306
socket      = /run/mysqld/mysqld.sock
datadir = ${MySQL_Data_Dir}
bind_address = 127.0.0.1
skip_name_resolve = ON
local_infile = OFF
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
performance_schema_max_table_instances = 500

explicit_defaults_for_timestamp = true
#skip-networking
max_connections = 500
max_connect_errors = 100
open_files_limit = 65535

log-bin=mysql-bin
binlog_format=mixed
server-id   = 1
expire_logs_days = 10
early-plugin-load = ""

default_storage_engine = InnoDB
innodb_data_home_dir = ${MySQL_Data_Dir}
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = ${MySQL_Data_Dir}
innodb_buffer_pool_size = 16M
innodb_log_file_size = 5M
innodb_log_buffer_size = 8M
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 50

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[myisamchk]
key_buffer_size = 20M
sort_buffer_size = 20M
read_buffer_size = 2M
write_buffer_size = 2M

[mysqlhotcopy]
interactive-timeout

${MySQLMAOpt}
EOF

    MySQL_Opt
    if [ -d "${MySQL_Data_Dir}" ]; then
        rm -rf -- "${MySQL_Data_Dir:?}"/*
    else
        mkdir -p -- "${MySQL_Data_Dir}"
    fi
    chown -R mysql:mysql /usr/local/mysql/
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
/usr/local/mysql/lib
/usr/local/lib
EOF

    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql
}

Upgrade_MySQL80()
{
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Generic Binaries..."
        Tar_Cd ${mysql_src}
        mkdir /usr/local/mysql
        mv mysql-${mysql_version}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Source code..."
        Activate_MySQL97_Compiler || return 1
        Tar_Cd ${mysql_src} mysql-${mysql_version}
        Install_Boost
        mkdir build && cd build
        cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/mysql -DSYSCONFDIR=/etc -DWITH_MYISAM_STORAGE_ENGINE=1 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DWITH_FEDERATED_STORAGE_ENGINE=1 -DEXTRA_CHARSETS=all -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_0900_ai_ci -DENABLED_LOCAL_INFILE=OFF -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF ${MySQL_WITH_BOOST}
        Make_Install
    fi

    groupadd mysql
    useradd -s /sbin/nologin -M -g mysql mysql

cat > /etc/my.cnf<<EOF
[client]
#password   = your_password
port        = 3306
socket      = /run/mysqld/mysqld.sock

[mysqld]
port        = 3306
socket      = /run/mysqld/mysqld.sock
datadir = ${MySQL_Data_Dir}
bind_address = 127.0.0.1
mysqlx_bind_address = 127.0.0.1
skip-external-locking
skip_name_resolve = ON
local_infile = OFF
key_buffer_size = 16M
max_allowed_packet = 1M
table_open_cache = 64
sort_buffer_size = 512K
net_buffer_length = 8K
read_buffer_size = 256K
read_rnd_buffer_size = 512K
myisam_sort_buffer_size = 8M
thread_cache_size = 8
tmp_table_size = 16M
performance_schema_max_table_instances = 500

explicit_defaults_for_timestamp = true
#skip-networking
max_connections = 500
max_connect_errors = 100
open_files_limit = 65535
log-bin=mysql-bin
binlog_format=mixed
server-id   = 1
binlog_expire_logs_seconds = 864000
early-plugin-load = ""

default_storage_engine = InnoDB
innodb_data_home_dir = ${MySQL_Data_Dir}
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = ${MySQL_Data_Dir}
innodb_buffer_pool_size = 16M
innodb_log_file_size = 5M
innodb_log_buffer_size = 8M
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 50

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[myisamchk]
key_buffer_size = 20M
sort_buffer_size = 20M
read_buffer_size = 2M
write_buffer_size = 2M

[mysqlhotcopy]
interactive-timeout

${MySQLMAOpt}
EOF

    MySQL_Opt
    if [ -d "${MySQL_Data_Dir}" ]; then
        rm -rf -- "${MySQL_Data_Dir:?}"/*
    else
        mkdir -p -- "${MySQL_Data_Dir}"
    fi
    chown -R mysql:mysql /usr/local/mysql/
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
/usr/local/mysql/lib
/usr/local/lib
EOF

    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql
}

Upgrade_MySQL84()
{
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Generic Binaries..."
        Tar_Cd ${mysql_src}
        mkdir /usr/local/mysql
        mv mysql-${mysql_version}-linux-glibc2.28-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "Starting upgrade MySQL ${mysql_version} Using Source code..."
        Activate_MySQL97_Compiler || return 1
        Tar_Cd ${mysql_src} mysql-${mysql_version}
        Install_Boost
        mkdir build && cd build
        cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/mysql -DSYSCONFDIR=/etc -DWITH_MYISAM_STORAGE_ENGINE=1 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DWITH_FEDERATED_STORAGE_ENGINE=1 -DEXTRA_CHARSETS=all -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_0900_ai_ci -DENABLED_LOCAL_INFILE=OFF -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF ${MySQL_WITH_BOOST}
        Make_Install
    fi

    groupadd mysql
    useradd -s /sbin/nologin -M -g mysql mysql

cat > /etc/my.cnf<<EOF
[client]
#password   = your_password
port        = 3306
socket      = /run/mysqld/mysqld.sock

[mysqld]
port        = 3306
socket      = /run/mysqld/mysqld.sock
datadir = ${MySQL_Data_Dir}
bind_address = 127.0.0.1
mysqlx_bind_address = 127.0.0.1
skip-external-locking
skip_name_resolve = ON
local_infile = OFF
key_buffer_size = 16M
max_allowed_packet = 64M
table_open_cache = 256
sort_buffer_size = 512K
net_buffer_length = 8K
read_buffer_size = 256K
read_rnd_buffer_size = 512K
myisam_sort_buffer_size = 8M
thread_cache_size = 8
tmp_table_size = 16M
performance_schema_max_table_instances = 500

explicit_defaults_for_timestamp = true
#skip-networking
max_connections = 500
max_connect_errors = 1000
open_files_limit = 65535

log-bin=mysql-bin
server-id   = 1
binlog_expire_logs_seconds = 864000

default_storage_engine = InnoDB
character_set_server = utf8mb4
collation_server = utf8mb4_0900_ai_ci
innodb_file_per_table = 1
innodb_data_home_dir = ${MySQL_Data_Dir}
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = ${MySQL_Data_Dir}
innodb_buffer_pool_size = 16M
innodb_redo_log_capacity = 100M
innodb_log_buffer_size = 8M
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 50
innodb_flush_method = O_DIRECT

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[myisamchk]
key_buffer_size = 20M
sort_buffer_size = 20M
read_buffer_size = 2M
write_buffer_size = 2M

[mysqlhotcopy]
interactive-timeout

${MySQLMAOpt}
EOF

    MySQL_Opt
    if [ -d "${MySQL_Data_Dir}" ]; then
        rm -rf -- "${MySQL_Data_Dir:?}"/*
    else
        mkdir -p -- "${MySQL_Data_Dir}"
    fi
    chown -R mysql:mysql /usr/local/mysql/
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
/usr/local/mysql/lib
/usr/local/lib
EOF

    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql
}

Restore_Start_MySQL()
{
    chgrp -R mysql /usr/local/mysql/.
    \cp /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql
    chmod 755 /etc/init.d/mysql

    ldconfig

    MySQL_Sec_Setting
    /etc/init.d/mysql start

    echo "Restore backup databases..."
    if ! /usr/local/mysql/bin/mysql --defaults-file="${LNMP_MYCNF}" < "/root/mysql_all_backup${Upgrade_Date}.sql"; then
        Echo_Red "Database restore failed; the backup and previous installation were preserved."
        return 1
    fi
    echo "Repair databases..."
    if [ "$(printf '%s\n' "${mysql_version}" 8.0.16 | sort -V | head -n1)" = 8.0.16 ]; then
        echo "MySQL ${mysql_version} performs the data-dictionary upgrade automatically during startup."
        /usr/local/mysql/bin/mysqladmin --defaults-file="${LNMP_MYCNF}" ping >/dev/null || return 1
    elif [ -x /usr/local/mysql/bin/mysql_upgrade ]; then
        /usr/local/mysql/bin/mysql_upgrade --defaults-file="${LNMP_MYCNF}" || return 1
    else
        Echo_Red "mysql_upgrade is required for MySQL ${mysql_version} but was not installed."
        return 1
    fi

    /etc/init.d/mysql stop
    TempMycnf_Clean
    cd "${cur_dir}" || return 1
    rm -rf -- "${cur_dir}/src/mysql-${mysql_version}"

    lnmp start
    if [[ -s /usr/local/mysql/bin/mysql && -s /usr/local/mysql/bin/mysqld_safe && -s /etc/my.cnf ]]; then
        Echo_Green "======== upgrade MySQL completed ======"
    else
        Echo_Red "======== upgrade MySQL failed ======"
        Echo_Red "upgrade MySQL log: /root/upgrade_mysq${Upgrade_Date}.log"
        echo "You upload upgrade_mysq${Upgrade_Date}.log to LNMP Forum for help."
    fi
}

Upgrade_MySQL()
{
    Check_DB
    Validate_Install_Path "${MySQL_Data_Dir}" 'MySQL data directory' || exit 1
    if [ "${Is_MySQL}" = "n" ]; then
        Echo_Red "Current database was MariaDB, Can't run MySQL upgrade script."
        exit 1
    fi

    Verify_DB_Password

    cur_mysql_version=`/usr/local/mysql/bin/mysql_config --version`
    mysql_version=""
    echo "Current MYSQL Version:${cur_mysql_version}"
    echo "You can get version number from https://dev.mysql.com/downloads/mysql/"
    Echo_Yellow "Please input MySQL Version you want."
    read -p "(example: 9.7.1): " mysql_version
    if [ "${mysql_version}" = "" ]; then
        echo "Error: You must input MySQL Version!!"
        exit 1
    fi
    if ! echo "${mysql_version}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        Echo_Red "Error: invalid MySQL version format."
        exit 1
    fi
    case "${mysql_version}" in
        5.7.*|8.0.*|8.4.*|9.7.*) ;;
        *) Echo_Red "Supported MySQL upgrade branches are 5.7, 8.0, 8.4 and 9.7."; exit 1 ;;
    esac

    if [ "${mysql_version}" == "${cur_mysql_version}" ]; then
        echo "Error: The upgrade MYSQL Version is the same as the old Version!!"
        exit 1
    fi

    Select_Database_Package_Mode mysql "${mysql_version}" "${DB_Install_Mode:-auto}" || exit 1

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
        ;;
    esac

    mysql_short_version=`echo ${mysql_version} | cut -d. -f1-2`

    echo "=================================================="
    echo "You will upgrade MySQL Version to ${mysql_version}"
    echo "=================================================="

    Press_Start

    echo "============================check files=================================="
    cd ${cur_dir}/src
    if [[ "${Bin}" = "y" && "${mysql_short_version}" = "8.0" ]]; then
        mysql8_glibc_ver="2.28"
        mysql_src="mysql-${mysql_version}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz"
    elif [[ "${Bin}" = "y" && "${mysql_short_version}" = "8.4" ]]; then
        mysql_src="mysql-${mysql_version}-linux-glibc2.28-${DB_ARCH}.tar.xz"
    elif [[ "${Bin}" = "y" && "${mysql_short_version}" = "9.7" ]]; then
        mysql_src="mysql-${mysql_version}-linux-glibc2.28-${DB_ARCH}.tar.xz"
    elif [[ "${Bin}" = "y" && "${mysql_short_version}" = "5.7" ]]; then
        mysql_src="mysql-${mysql_version}-linux-glibc2.12-${DB_ARCH}.tar.gz"
    else
        if [[ "${mysql_short_version}" = "5.7" || "${mysql_short_version}" = "8.0" ]]; then
            mysql_src="mysql-boost-${mysql_version}.tar.gz"
        else
            mysql_src="mysql-${mysql_version}.tar.gz"
        fi
    fi
    if ! Download_Files "https://cdn.mysql.com/Downloads/MySQL-${mysql_short_version}/${mysql_src}" "${mysql_src}" publisher-tls; then
        if ! Download_Files "https://cdn.mysql.com/archives/mysql-${mysql_short_version}/${mysql_src}" "${mysql_src}" publisher-tls; then
            Echo_Red "Error: invalid MySQL version or publisher download failed."
            exit 1
        fi
    fi
    Check_Openssl
    if [ "${Bin}" != "y" ]; then
        Echo_Blue "Install dependent packages..."
        . ${cur_dir}/include/only.sh
        DB_Dependent
    fi
    echo "============================check files=================================="

    Backup_MySQL
    if [ "${mysql_short_version}" = "5.7" ]; then
        Upgrade_MySQL57
    elif [ "${mysql_short_version}" = "8.0" ]; then
        Upgrade_MySQL80
    elif [ "${mysql_short_version}" = "8.4" ]; then
        Upgrade_MySQL84
    elif [ "${mysql_short_version}" = "9.7" ]; then
        Upgrade_MySQL84
    fi
    Restore_Start_MySQL
}
