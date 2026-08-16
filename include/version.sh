#!/usr/bin/env bash

Libiconv_Ver='libiconv-1.19'
Freetype_New_Ver='freetype-2.14.3'
Pcre_Ver='pcre2-10.47'
Boost_Ver='boost_1_59_0'
Openssl_New_Ver='openssl-3.5.7'
Openssl_Legacy_PHP_Ver='openssl-1.1.1w'
Curl_Legacy_PHP_Ver='curl-8.21.0'
Libzip_Ver='libzip-1.11.4'
Luajit_Ver='luajit2-2.1-20230119'
LuaNginxModule='lua-nginx-module-0.10.26'
LuaRestyCore='lua-resty-core-0.1.28'
LuaRestyLrucache='lua-resty-lrucache-0.13'
NgxDevelKit='ngx_devel_kit-0.3.3'
Nginx_Ver='nginx-1.30.4'
NgxFancyIndex_Ver='ngx-fancyindex-0.5.2'
if [ "${DBSelect}" = "4" ]; then
    Mysql_Ver='mysql-5.7.44'
elif [ "${DBSelect}" = "5" ]; then
    Mysql_Ver='mysql-8.0.46'
elif [ "${DBSelect}" = "6" ]; then
    Mysql_Ver='mysql-8.4.11'
elif [ "${DBSelect}" = "7" ]; then
    Mysql_Ver='mysql-9.7.1'
elif [ "${DBSelect}" = "10" ]; then
    Mariadb_Ver='mariadb-10.6.27'
elif [ "${DBSelect}" = "11" ]; then
    Mariadb_Ver='mariadb-10.11.18'
elif [ "${DBSelect}" = "12" ]; then
    Mariadb_Ver='mariadb-11.4.12'
elif [ "${DBSelect}" = "13" ]; then
    Mariadb_Ver='mariadb-11.8.8'
elif [ "${DBSelect}" = "14" ]; then
    Mariadb_Ver='mariadb-12.3.2'
fi
if [ "${PHPSelect}" = "10" ]; then
    Php_Ver='php-7.4.33'
elif [ "${PHPSelect}" = "11" ]; then
    Php_Ver='php-8.0.30'
elif [ "${PHPSelect}" = "12" ]; then
    Php_Ver='php-8.1.34'
elif [ "${PHPSelect}" = "13" ]; then
    Php_Ver='php-8.2.33'
elif [ "${PHPSelect}" = "14" ]; then
    Php_Ver='php-8.3.33'
elif [ "${PHPSelect}" = "15" ]; then
    Php_Ver='php-8.4.24'
elif [ "${PHPSelect}" = "16" ]; then
    Php_Ver='php-8.5.9'
fi
PhpMyAdmin_Ver='phpMyAdmin-5.2.3-all-languages'
Pureftpd_Ver='pure-ftpd-1.0.51'

Redis_Stable_Ver='redis-8.10.0'
PHPRedis_Ver='redis-6.3.0'
