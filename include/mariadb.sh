#!/usr/bin/env bash

MariaDB_WITHSSL()
{
    MariaDBWITHSSL=''
}

Mariadb_Sec_Setting()
{
    install -d -o mariadb -g mariadb -m 0755 /run/mysqld || return 1
    cat > /etc/ld.so.conf.d/mariadb.conf<<EOF
    /usr/local/mariadb/lib
    /usr/local/lib
EOF
    ldconfig

    if [ -d "/proc/vz" ];then
        ulimit -s unlimited
    fi

    if [ -d "/etc/mysql" ]; then
        mv /etc/mysql /etc/mysql.backup.$(date +%Y%m%d)
    fi
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable mariadb.service
    fi
    StartUp mariadb
    /etc/init.d/mariadb start

    ln -sf /usr/local/mariadb/bin/mysql /usr/bin/mysql
    ln -sf /usr/local/mariadb/bin/mysqldump /usr/bin/mysqldump
    ln -sf /usr/local/mariadb/bin/myisamchk /usr/bin/myisamchk
    ln -sf /usr/local/mariadb/bin/mysqld_safe /usr/bin/mysqld_safe
    ln -sf /usr/local/mariadb/bin/mysqlcheck /usr/bin/mysqlcheck

    /etc/init.d/mariadb restart
    sleep 2

    Set_Initial_DB_Root_Password /usr/local/mariadb/bin/mysql "${DB_Root_Password}" || {
        Echo_Red 'Unable to set the initial MariaDB root password.'
        return 1
    }

    /etc/init.d/mariadb restart
    
    Make_TempMycnf "${DB_Root_Password}"
    Do_Query ""
    [ $? -eq 0 ] || return 1

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

    /etc/init.d/mariadb stop
}

Check_MariaDB_Data_Dir()
{
    local backup_dir
    Validate_Install_Path "${MariaDB_Data_Dir}" 'MariaDB data directory' || return 1
    if [ -d "${MariaDB_Data_Dir}" ]; then
        backup_dir="/root/lnmp-backups/mariadb-data-$(date +%Y%m%d%H%M%S)-$$"
        install -d -m 0700 "${backup_dir}" || return 1
        \cp -a "${MariaDB_Data_Dir}/." "${backup_dir}/" || {
            Echo_Red "Database backup failed; existing data was not removed."
            return 1
        }
        find "${MariaDB_Data_Dir}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
        Echo_Yellow "Existing MariaDB data preserved at ${backup_dir}."
    else
        mkdir -p -- "${MariaDB_Data_Dir}"
    fi
}

Initialize_MariaDB_Data_Dir()
{
    local installer=''
    if [ -x /usr/local/mariadb/scripts/mariadb-install-db ]; then
        installer=/usr/local/mariadb/scripts/mariadb-install-db
    elif [ -x /usr/local/mariadb/scripts/mysql_install_db ]; then
        installer=/usr/local/mariadb/scripts/mysql_install_db
    else
        Echo_Red 'MariaDB data-directory initializer was not installed.'
        return 1
    fi
    "${installer}" --defaults-file=/etc/my.cnf --basedir=/usr/local/mariadb \
        --datadir="${MariaDB_Data_Dir}" --user=mariadb
}

Install_MariaDB_106()
{
    if [ "${Bin}" = "y" ]; then
        Echo_Blue "[+] Installing ${Mariadb_Ver} Using Generic Binaries..."
        Tar_Cd ${MariaDB_FileName}.tar.gz
        mkdir /usr/local/mariadb
        mv ${MariaDB_FileName}/* /usr/local/mariadb/
    else
        Echo_Blue "[+] Installing ${Mariadb_Ver} Using Source code..."
        rm -f /etc/my.cnf
        Tar_Cd ${Mariadb_Ver}.tar.gz ${Mariadb_Ver}
        cmake -DCMAKE_INSTALL_PREFIX=/usr/local/mariadb -DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock -DEXTRA_CHARSETS=all -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DWITH_READLINE=1 -DENABLED_LOCAL_INFILE=OFF -DWITHOUT_TOKUDB=1
        Make_Install
    fi

    groupadd mariadb
    useradd -s /sbin/nologin -M -g mariadb mariadb

cat > /etc/my.cnf<<EOF
[client]
#password   = your_password
port        = 3306
socket      = /run/mysqld/mysqld.sock

[mysqld]
port        = 3306
socket      = /run/mysqld/mysqld.sock
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

explicit_defaults_for_timestamp = true
#skip-networking
max_connections = 500
max_connect_errors = 100
open_files_limit = 65535

log-bin=mysql-bin
binlog_format=mixed
server-id   = 1
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
    Check_MariaDB_Data_Dir || return 1
    chown -R mariadb:mariadb /usr/local/mariadb
    Initialize_MariaDB_Data_Dir || return 1
    chown -R mariadb:mariadb -- "${MariaDB_Data_Dir}"
    \cp /usr/local/mariadb/support-files/mysql.server /etc/init.d/mariadb
    \cp ${cur_dir}/init.d/mariadb.service /etc/systemd/system/mariadb.service
    chmod 755 /etc/init.d/mariadb

    Mariadb_Sec_Setting
}
