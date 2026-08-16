#!/usr/bin/env bash
# author: licess
# Independent hardened maintenance build

CheckURL="http://127.0.0.1/"

STATUS_CODE=$(curl --output /dev/null --max-time 10 --connect-timeout 10 --silent --write-out '%{http_code}' "${CheckURL}")
#echo "$CheckURL Status Code:\t$STATUS_CODE"
if [ "$STATUS_CODE" = "502" ]; then
    /etc/init.d/php-fpm restart
fi
