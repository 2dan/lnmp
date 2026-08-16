#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script!"
    exit 1
fi

echo "+-------------------------------------------------------------------+"
echo "|   Reset MySQL/MariaDB root Password for LNMP, Written by Licess   |"
echo "+-------------------------------------------------------------------+"
echo "|       A tool to reset MySQL/MariaDB root password for LNMP        |"
echo "+-------------------------------------------------------------------+"
echo "|         Independent hardened maintenance build                   |"
echo "+-------------------------------------------------------------------+"
echo "|           Usage: ./reset_mysql_root_password.sh                   |"
echo "+-------------------------------------------------------------------+"

if [ -s /usr/local/mariadb/bin/mysql ]; then
    DB_Name="mariadb"
    DB_Ver=`/usr/local/mariadb/bin/mysql_config --version`
elif [ -s /usr/local/mysql/bin/mysql ]; then
    DB_Name="mysql"
    DB_Ver=`/usr/local/mysql/bin/mysql_config --version`
else
    echo "MySQL/MariaDB not found!"
    exit 1
fi

while :;do
    DB_Root_Password=""
    read -r -s -p "Enter New ${DB_Name} root password: " DB_Root_Password
    echo
    if [ "${DB_Root_Password}" = "" ]; then
        echo "Error: Password can't be NULL!!"
    else
        break
    fi
done

DB_Root_Password_SQL=${DB_Root_Password//\\/\\\\}
DB_Root_Password_SQL=${DB_Root_Password_SQL//\'/\'\'}

echo "Stoping ${DB_Name}..."
/etc/init.d/${DB_Name} stop || exit 1
echo "Starting ${DB_Name} with grant tables and networking disabled"
"/usr/local/${DB_Name}/bin/mysqld_safe" --skip-grant-tables --skip-networking >/dev/null 2>&1 &
RESET_SAFE_PID=$!
ready=n
for _ in $(seq 1 30); do
    if "/usr/local/${DB_Name}/bin/mysqladmin" -u root ping >/dev/null 2>&1; then
        ready=y
        break
    fi
    sleep 1
done
if [ "${ready}" != y ]; then
    echo "Temporary ${DB_Name} server failed to start."
    kill "${RESET_SAFE_PID}" 2>/dev/null || true
    exit 1
fi
echo "update ${DB_Name} root password..."
if echo "${DB_Ver}" | grep -Eqi '^(5\.7\.|[89]\.|10\.[2-9]\.|1[1-9]\.)'; then
    "/usr/local/${DB_Name}/bin/mysql" -u root << EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_Root_Password_SQL}';
EOF
else
    "/usr/local/${DB_Name}/bin/mysql" -u root << EOF
update mysql.user set password = Password('${DB_Root_Password_SQL}') where User = 'root';
EOF
fi

if [ $? -eq 0 ]; then
    echo "Password reset successfully. Stopping the temporary server cleanly."
    "/usr/local/${DB_Name}/bin/mysqladmin" -u root shutdown || {
        echo "Unable to stop the temporary ${DB_Name} server safely."
        exit 1
    }
    wait "${RESET_SAFE_PID}" 2>/dev/null || true
    echo "Restarting the actual ${DB_Name} service"
    /etc/init.d/${DB_Name} start || exit 1
    echo "Password successfully reset (value hidden)."
else
    echo "Reset ${DB_Name} root password failed!"
    "/usr/local/${DB_Name}/bin/mysqladmin" -u root shutdown >/dev/null 2>&1 || true
    wait "${RESET_SAFE_PID}" 2>/dev/null || true
    exit 1
fi
