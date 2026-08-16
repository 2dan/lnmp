#!/usr/bin/env bash

MySQL_Sec_Setting()
{
    install -d -o mysql -g mysql -m 0755 /run/mysqld || return 1
    if [ -d "/proc/vz" ]; then
        ulimit -s unlimited
    fi

    if [ -d "/etc/mysql" ]; then
        mv /etc/mysql /etc/mysql.backup.$(date +%Y%m%d)
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable mysql.service
    fi
    /etc/init.d/mysql start

    ln -sf /usr/local/mysql/bin/mysql /usr/bin/mysql
    ln -sf /usr/local/mysql/bin/mysqldump /usr/bin/mysqldump
    ln -sf /usr/local/mysql/bin/myisamchk /usr/bin/myisamchk
    ln -sf /usr/local/mysql/bin/mysqld_safe /usr/bin/mysqld_safe
    ln -sf /usr/local/mysql/bin/mysqlcheck /usr/bin/mysqlcheck

    /etc/init.d/mysql restart
    sleep 2

    Set_Initial_DB_Root_Password /usr/local/mysql/bin/mysql "${DB_Root_Password}" || {
        Echo_Red 'Unable to set the initial MySQL root password.'
        return 1
    }
    /etc/init.d/mysql restart

    Make_TempMycnf "${DB_Root_Password}"
    Do_Query ""
    if [ $? -eq 0 ]; then
        echo "OK, MySQL root password correct."
    fi
    echo "Remove anonymous users..."
    Do_Query "DELETE FROM mysql.user WHERE User='';"
    Do_Query "DROP USER ''@'%';"
    [ $? -eq 0 ] && echo " ... Success." || echo " ... Failed!"
    echo "Disallow root login remotely..."
    Do_Query "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    [ $? -eq 0 ] && echo " ... Success." || echo " ... Failed!"
    echo "Remove test database..."
    Do_Query "DROP DATABASE test;"
    [ $? -eq 0 ] && echo " ... Success." || echo " ... Failed!"
    echo "Reload privilege tables..."
    Do_Query "FLUSH PRIVILEGES;"
    [ $? -eq 0 ] && echo " ... Success." || echo " ... Failed!"

    /etc/init.d/mysql restart
    /etc/init.d/mysql stop
}

MySQL_Opt()
{
    # Tune from actual host/container resources. MyISAM is always tuned;
    # InnoDB receives a separate budget only in mixed-engine mode.
    local mem_mb cpu_count key_buffer_mb myisam_sort_mb table_cache thread_cache
    local tmp_table_mb max_connections pool_mb redo_mb io_capacity
    if declare -F Detect_Hardware_Profile >/dev/null 2>&1; then
        Detect_Hardware_Profile
    fi
    mem_mb=${HW_MEM_MB:-${MemTotal:-1024}}
    cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
    [ "${mem_mb}" -lt 512 ] && mem_mb=512

    if [ "${InstallInnodb:-y}" = "y" ]; then
        key_buffer_mb=$((mem_mb * 5 / 100))
        [ "${key_buffer_mb}" -gt 512 ] && key_buffer_mb=512
    else
        key_buffer_mb=$((mem_mb * 25 / 100))
        [ "${key_buffer_mb}" -gt 4096 ] && key_buffer_mb=4096
        sed -i -E 's/^default_storage_engine.*/default_storage_engine = MyISAM/' /etc/my.cnf
    fi
    [ "${key_buffer_mb}" -lt 16 ] && key_buffer_mb=16
    myisam_sort_mb=$((key_buffer_mb / 2))
    [ "${myisam_sort_mb}" -lt 8 ] && myisam_sort_mb=8
    table_cache=$((cpu_count * 256))
    [ "${table_cache}" -lt 256 ] && table_cache=256
    [ "${table_cache}" -gt 8192 ] && table_cache=8192
    thread_cache=$((cpu_count * 8))
    [ "${thread_cache}" -lt 16 ] && thread_cache=16
    [ "${thread_cache}" -gt 256 ] && thread_cache=256
    tmp_table_mb=$((mem_mb / 100))
    [ "${tmp_table_mb}" -lt 16 ] && tmp_table_mb=16
    [ "${tmp_table_mb}" -gt 128 ] && tmp_table_mb=128
    max_connections=$((mem_mb / 64))
    [ "${max_connections}" -lt 50 ] && max_connections=50
    [ "${max_connections}" -gt 500 ] && max_connections=500

    sed -i -E "s/^key_buffer_size.*/key_buffer_size = ${key_buffer_mb}M/" /etc/my.cnf
    sed -i -E "s/^myisam_sort_buffer_size.*/myisam_sort_buffer_size = ${myisam_sort_mb}M/" /etc/my.cnf
    sed -i -E "s/^table_open_cache.*/table_open_cache = ${table_cache}/" /etc/my.cnf
    sed -i -E "s/^thread_cache_size.*/thread_cache_size = ${thread_cache}/" /etc/my.cnf
    sed -i -E "s/^tmp_table_size.*/tmp_table_size = ${tmp_table_mb}M/" /etc/my.cnf
    sed -i -E "s/^max_connections.*/max_connections = ${max_connections}/" /etc/my.cnf
    sed -i -E 's/^sort_buffer_size.*/sort_buffer_size = 1M/' /etc/my.cnf
    sed -i -E 's/^read_buffer_size.*/read_buffer_size = 1M/' /etc/my.cnf
    sed -i -E 's/^read_rnd_buffer_size.*/read_rnd_buffer_size = 1M/' /etc/my.cnf

    if [ "${InstallInnodb:-y}" = "y" ]; then
        pool_mb=$((mem_mb * 45 / 100))
        [ "${pool_mb}" -lt 128 ] && pool_mb=128
        pool_mb=$((pool_mb / 128 * 128))
        [ "${pool_mb}" -lt 128 ] && pool_mb=128
        redo_mb=$((pool_mb / 4))
        [ "${redo_mb}" -lt 100 ] && redo_mb=100
        [ "${redo_mb}" -gt 4096 ] && redo_mb=4096
        if find /sys/block -maxdepth 2 -name rotational -type f -exec grep -q '^1$' {} \; 2>/dev/null; then
            io_capacity=200
        else
            io_capacity=1000
        fi
        sed -i -E "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${pool_mb}M/" /etc/my.cnf
        sed -i -E "s/^innodb_log_file_size.*/innodb_log_file_size = ${redo_mb}M/" /etc/my.cnf
        sed -i -E "s/^innodb_redo_log_capacity.*/innodb_redo_log_capacity = ${redo_mb}M/" /etc/my.cnf
        if grep -q '^innodb_io_capacity' /etc/my.cnf; then
            sed -i -E "s/^innodb_io_capacity.*/innodb_io_capacity = ${io_capacity}/" /etc/my.cnf
        else
            sed -i "/^innodb_flush_method/a innodb_io_capacity = ${io_capacity}" /etc/my.cnf
        fi
    else
        # MySQL 5.7+ cannot remove InnoDB; omit explicit InnoDB tuning and
        # direct the tunable cache budget to MyISAM instead.
        sed -i -E '/^innodb_(buffer_pool_size|log_file_size|redo_log_capacity|log_buffer_size|flush_log_at_trx_commit|lock_wait_timeout|io_capacity)[[:space:]]*=/d' /etc/my.cnf
    fi
    return 0
}

Check_MySQL_Data_Dir()
{
    local backup_dir
    Validate_Install_Path "${MySQL_Data_Dir}" 'MySQL data directory' || return 1
    if [ -d "${MySQL_Data_Dir}" ]; then
        backup_dir="/root/lnmp-backups/mysql-data-$(date +%Y%m%d%H%M%S)-$$"
        install -d -m 0700 "${backup_dir}" || return 1
        \cp -a "${MySQL_Data_Dir}/." "${backup_dir}/" || {
            Echo_Red "Database backup failed; existing data was not removed."
            return 1
        }
        find "${MySQL_Data_Dir}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
        Echo_Yellow "Existing MySQL data preserved at ${backup_dir}."
    else
        mkdir -p -- "${MySQL_Data_Dir}"
    fi
}

Install_MySQL_57()
{
    rm -f /etc/my.cnf
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Generic Binaries..."
        Tar_Cd ${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}.tar.gz
        mkdir /usr/local/mysql
        mv ${Mysql_Ver}-linux-glibc2.12-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Source code..."
        if [ "${isOpenSSL3}" = "y" ]; then
            Install_Legacy_OpenSSL || return 1
            MySQL_WITH_SSL='-DWITH_SSL=/usr/local/openssl-1.1'
        else
            MySQL_WITH_SSL=''
        fi
        Tar_Cd ${Mysql_Ver}.tar.gz ${Mysql_Ver}
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
innodb_file_per_table = 1
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
    Check_MySQL_Data_Dir || return 1
    chown -R mysql:mysql /usr/local/mysql
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"
    \cp /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql
    \cp ${cur_dir}/init.d/mysql.service /etc/systemd/system/mysql.service
    chmod 755 /etc/init.d/mysql

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
    /usr/local/mysql/lib
    /usr/local/lib
EOF
    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql

    MySQL_Sec_Setting
}

Install_MySQL_80()
{
    rm -f /etc/my.cnf
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Generic Binaries..."
        Tar_Cd ${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}.tar.xz
        mkdir /usr/local/mysql
        mv ${Mysql_Ver}-linux-glibc${mysql8_glibc_ver}-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Source code..."
        Activate_MySQL97_Compiler || return 1
        Tar_Cd ${Mysql_Ver}.tar.gz ${Mysql_Ver}
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
innodb_file_per_table = 1
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
    Check_MySQL_Data_Dir || return 1
    chown -R mysql:mysql /usr/local/mysql
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"
    \cp /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql
    \cp ${cur_dir}/init.d/mysql.service /etc/systemd/system/mysql.service
    chmod 755 /etc/init.d/mysql

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
    /usr/local/mysql/lib
    /usr/local/lib
EOF
    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql

    MySQL_Sec_Setting
}

Install_MySQL_84()
{
    rm -f /etc/my.cnf
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Generic Binaries..."
        Tar_Cd ${Mysql_Ver}-linux-glibc2.28-${DB_ARCH}.tar.xz
        mkdir /usr/local/mysql
        mv ${Mysql_Ver}-linux-glibc2.28-${DB_ARCH}/* /usr/local/mysql/
    else
        Echo_Blue "[+] Installing ${Mysql_Ver} Using Source code..."
        Activate_MySQL97_Compiler || return 1
        Tar_Cd ${Mysql_Ver}.tar.gz ${Mysql_Ver}
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
    Check_MySQL_Data_Dir || return 1
    chown -R mysql:mysql /usr/local/mysql
    /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir=${MySQL_Data_Dir} --user=mysql
    chown -R mysql:mysql -- "${MySQL_Data_Dir}"
    \cp /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql
    \cp ${cur_dir}/init.d/mysql.service /etc/systemd/system/mysql.service
    chmod 755 /etc/init.d/mysql

    cat > /etc/ld.so.conf.d/mysql.conf<<EOF
    /usr/local/mysql/lib
    /usr/local/lib
EOF
    ldconfig
    ln -sf /usr/local/mysql/lib/mysql /usr/lib/mysql
    ln -sf /usr/local/mysql/include/mysql /usr/include/mysql

    MySQL_Sec_Setting
}
