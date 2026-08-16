#!/usr/bin/env bash

Install_Nginx_Openssl()
{
    if [ "${Enable_Nginx_Openssl}" = 'y' ]; then
        if [ ! -n "${Nginx_Version}" ]; then
            Nginx_Version=$(echo ${Nginx_Ver} | sed "s/nginx-//")
        fi
        Download_Files https://www.openssl.org/source/${Openssl_New_Ver}.tar.gz ${Openssl_New_Ver}.tar.gz
        [[ -d "${Openssl_New_Ver}" ]] && rm -rf -- "${Openssl_New_Ver}"
        Tar_Cd "${Openssl_New_Ver}.tar.gz" "" || return 1
        Nginx_With_Openssl="--with-openssl=${cur_dir}/src/${Openssl_New_Ver}"
    fi
}

Install_Nginx_Lua()
{
    if [ "${Enable_Nginx_Lua}" = 'y' ]; then
        echo "Installing Lua for Nginx..."
        cd ${cur_dir}/src
        Download_Files https://github.com/openresty/luajit2/archive/refs/tags/v2.1-20230119.tar.gz ${Luajit_Ver}.tar.gz
        Download_Files https://github.com/openresty/lua-nginx-module/archive/refs/tags/v0.10.26.tar.gz ${LuaNginxModule}.tar.gz
        Download_Files https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v0.3.3.tar.gz ${NgxDevelKit}.tar.gz
        Download_Files https://github.com/openresty/lua-resty-core/archive/refs/tags/v0.1.28.tar.gz ${LuaRestyCore}.tar.gz
        Download_Files https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/v0.13.tar.gz ${LuaRestyLrucache}.tar.gz

        Echo_Blue "[+] Installing ${Luajit_Ver}... "
        Tar_Cd "${LuaNginxModule}.tar.gz" "" || return 1
        Tar_Cd "${NgxDevelKit}.tar.gz" "" || return 1
        Tar_Cd ${Luajit_Ver}.tar.gz ${Luajit_Ver}
        make
        make install PREFIX=/usr/local/luajit
        cd ${cur_dir}/src
        rm -rf -- "${cur_dir}/src/${Luajit_Ver}"

        cat > /etc/ld.so.conf.d/luajit.conf<<EOF
/usr/local/luajit/lib
EOF
        if [ "${Is_64bit}" = "y" ]; then
            ln -sf /usr/local/luajit/lib/libluajit-5.1.so.2 /lib64/libluajit-5.1.so.2
        else
            ln -sf /usr/local/luajit/lib/libluajit-5.1.so.2 /usr/lib/libluajit-5.1.so.2
        fi
        ldconfig

        cat >/etc/profile.d/luajit.sh<<EOF
export LUAJIT_LIB=/usr/local/luajit/lib
export LUAJIT_INC=/usr/local/luajit/include/luajit-2.1
EOF

        source /etc/profile.d/luajit.sh

        Tar_Cd ${LuaRestyCore}.tar.gz ${LuaRestyCore}
        make install PREFIX=/usr/local/nginx
        cd -
        Tar_Cd ${LuaRestyLrucache}.tar.gz ${LuaRestyLrucache}
        make install PREFIX=/usr/local/nginx
        cd -

        Nginx_Ver_Com=$(${cur_dir}/include/version_compare 1.21.5 ${Nginx_Version})
        if [[  "${Nginx_Ver_Com}" == "1" ]]; then
            Nginx_Module_Lua="--with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib --add-module=${cur_dir}/src/${LuaNginxModule} --add-module=${cur_dir}/src/${NgxDevelKit}"
        else
            if [ "${Nginx_With_Pcre}" = "" ]; then
                Nginx_Module_Lua="--with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib --add-module=${cur_dir}/src/${LuaNginxModule} --add-module=${cur_dir}/src/${NgxDevelKit} --with-pcre=${cur_dir}/src/${Pcre_Ver} --with-pcre-jit"
                cd ${cur_dir}/src
                Download_Files https://github.com/PCRE2Project/pcre2/releases/download/${Pcre_Ver}/${Pcre_Ver}.tar.bz2 ${Pcre_Ver}.tar.bz2
                Tar_Cd ${Pcre_Ver}.tar.bz2
            else
                Nginx_Module_Lua="--with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib --add-module=${cur_dir}/src/${LuaNginxModule} --add-module=${cur_dir}/src/${NgxDevelKit}"
            fi
        fi
    fi
}

Install_Ngx_FancyIndex()
{
    if [ "${Enable_Ngx_FancyIndex}" = 'y' ]; then
        echo "Installing Ngx FancyIndex for Nginx..."
        cd ${cur_dir}/src
        Download_Files https://github.com/aperezdc/ngx-fancyindex/archive/refs/tags/v0.5.2.tar.gz ${NgxFancyIndex_Ver}.tar.gz

        Tar_Cd ${NgxFancyIndex_Ver}.tar.gz ${NgxFancyIndex_Ver}
        Ngx_FancyIndex="--add-module=${cur_dir}/src/${NgxFancyIndex_Ver}"
    fi
}

Install_Nginx()
{
    Nginx_Version=${Nginx_Ver#nginx-}
    Echo_Blue "[+] Installing ${Nginx_Ver}... "
    groupadd www
    useradd -s /sbin/nologin -g www www

    cd "${cur_dir}/src" || return 1
    Install_Nginx_Openssl || return 1
    Install_Nginx_Lua || return 1
    Install_Ngx_FancyIndex || return 1
    Tar_Cd "${Nginx_Ver}.tar.gz" "${Nginx_Ver}" || return 1
    if [[ "${DISTRO}" = "Fedora" && ${Fedora_Version} -ge 28 ]]; then
        patch -p1 < ${cur_dir}/src/patch/nginx-libxcrypt.patch
    fi
    Nginx_Ver_Com=$(${cur_dir}/include/version_compare 1.14.2 ${Nginx_Version})
    if gcc -dumpversion|grep -q "^[8]" && [ "${Nginx_Ver_Com}" == "1" ]; then
        patch -p1 < ${cur_dir}/src/patch/nginx-gcc8.patch
    fi
    ./configure --user=www --group=www --prefix=/usr/local/nginx --with-http_stub_status_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_gzip_static_module --with-http_sub_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-http_realip_module ${Nginx_With_Openssl} ${Nginx_With_Pcre} ${Nginx_Module_Lua} ${NginxMAOpt} ${Ngx_FancyIndex} ${Nginx_Modules_Options} || return 1
    Make_Install || return 1
    cd "${cur_dir}" || return 1

    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx

    rm -f /usr/local/nginx/conf/nginx.conf
    \cp conf/nginx.conf /usr/local/nginx/conf/nginx.conf
    \cp -ra conf/rewrite /usr/local/nginx/conf/
    \cp conf/pathinfo.conf /usr/local/nginx/conf/pathinfo.conf
    \cp conf/enable-php.conf /usr/local/nginx/conf/enable-php.conf
    \cp conf/enable-php-pathinfo.conf /usr/local/nginx/conf/enable-php-pathinfo.conf
    \cp -ra conf/example /usr/local/nginx/conf/example
    if [ "${Enable_Nginx_Lua}" = 'y' ]; then
        if ! grep -q 'lua_package_path "/usr/local/nginx/lib/lua/?.lua";' /usr/local/nginx/conf/nginx.conf; then
            sed -i "/server_tokens off;/i\        lua_package_path \"/usr/local/nginx/lib/lua/?.lua\";\n" /usr/local/nginx/conf/nginx.conf
        fi
        sed -i "/include enable-php.conf;/i\        location /lua\n        {\n            default_type text/html;\n            content_by_lua 'ngx.say\(\"hello world\"\)';\n        }\n" /usr/local/nginx/conf/nginx.conf
    fi
    if [ "${isWSL}" = "y" ]; then
        sed -i "/gzip on;/i\        fastcgi_buffering off;\n" /usr/local/nginx/conf/nginx.conf
    fi

    mkdir -p -- "${Default_Website_Dir}"
    install -d -m 0750 -o root -g www /usr/local/nginx/logs /usr/local/nginx/logs/vhost /usr/local/nginx/logs/archive

    chown -R www:www -- "${Default_Website_Dir}"

    install -d -m 0750 -o root -g www /usr/local/nginx/conf/vhost

    if [ "${Default_Website_Dir}" != "/home/wwwroot/default" ]; then
        sed -i "s#/home/wwwroot/default#${Default_Website_Dir}#g" /usr/local/nginx/conf/nginx.conf
    fi

    cat >"${Default_Website_Dir}/.user.ini"<<EOF
open_basedir=${Default_Website_Dir}:/tmp/
EOF
    chmod 0644 "${Default_Website_Dir}/.user.ini"
    chattr +i "${Default_Website_Dir}/.user.ini" 2>/dev/null || true
    if ! grep -q '^fastcgi_param PHP_ADMIN_VALUE' /usr/local/nginx/conf/fastcgi.conf; then
        cat >>/usr/local/nginx/conf/fastcgi.conf<<'EOF'
fastcgi_param PHP_ADMIN_VALUE "open_basedir=$document_root/:/tmp/";
EOF
    fi

    \cp init.d/init.d.nginx /etc/init.d/nginx
    \cp init.d/nginx.service /etc/systemd/system/nginx.service
    chmod +x /etc/init.d/nginx

    uname_r=$(uname -r | cut -d- -f1)
    if [ "$(printf '%s\n' 3.9 "${uname_r}" | sort -V | head -n1)" = 3.9 ]; then
        echo "3.9+";
        sed -i 's/listen 80 default_server;/listen 80 default_server reuseport;/g' /usr/local/nginx/conf/nginx.conf
    fi
}
