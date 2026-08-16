# LNMP 2.3 Hardened

这是从本地 LNMP 2.1 独立演进的安全维护版本。项目不从原 LNMP 站点、镜像或论坛下载和执行任何内容；所有核心软件均使用各软件项目的 HTTPS 官方源。

## 默认组件

- Nginx 1.30.4
- MySQL 8.4.11 LTS
- PHP 8.5.9
- Redis 8.10.0
- phpredis 6.3.0
- OpenSSL 3.5.7 LTS
- phpMyAdmin 5.2.3
- libzip 1.11.4
- FreeType 2.14.3
- PCRE2 10.47
- GNU libiconv 1.19

支持矩阵从 PHP 7.4.33、MySQL 5.7.44 起步：PHP 支持 7.4.33、8.0.30、8.1.34、8.2.33、8.3.33、8.4.24、8.5.9；MySQL 支持 5.7.44、8.0.46、8.4.11、9.7.1 LTS；MariaDB 支持 10.6.27、10.11.18、11.4.12、11.8.8、12.3.2 LTS。PHP 7.4/8.0/8.1、MySQL 5.7/8.0 已结束上游安全维护，只应用于隔离的遗留业务迁移。

项目只保留 Nginx + MySQL/MariaDB + PHP-FPM，Apache、LAMP、LNMPA 及 nghttp2 构建内容均已移除。SourceGuardian 和 ionCube 只从厂商 HTTPS 地址获取；SourceGuardian 自动下载要求调用者显式确认已接受厂商 Loader 许可。eAccelerator、XCache、Zend Guard 及 PHP 7.3 以下代码已移除。

## 安装

在受支持的 Linux 主机上，以 root 用户执行：

```bash
./install.sh lnmp
```

主要兼容目标为 Ubuntu 22.04/24.04/26.04、Debian 12/13、RHEL/Rocky/Alma/Oracle Linux 8–10、CentOS Stream 9/10、Amazon Linux 2023 及仍在上游维护期内的 Fedora。安装器保留管理员配置的软件仓库，不会把已结束维护的发行版偷偷切换到归档源；旧系统应先升级操作系统。

默认采用混合安装策略：Nginx、PHP、Redis、ImageMagick 和开源 PHP 扩展从已校验源码编译，以保留模块、TLS、多 PHP 与安装路径控制；MySQL/MariaDB 在 CPU 架构和 glibc 满足厂商通用包要求时使用已校验的官方二进制，否则自动回退源码；ionCube 与 SourceGuardian 使用厂商 Loader。数据库策略由 `lnmp.conf` 的 `DB_Install_Mode` 控制，默认 `auto`，也可设为 `source` 强制编译，或设为 `binary` 强制要求兼容的官方二进制（不兼容时停止而非冒险安装）。

默认选项会安装 Nginx、MySQL 8.4 和 PHP 8.5。下载函数强制使用 HTTPS、验证 TLS 证书，并对本版本清单内的关键源码包校验 SHA-256；MySQL 官方仅公布 MD5 的归档同时校验发布页给出的校验值。项目不再携带未校验的第三方源码归档，并统一使用操作系统内存分配器。不要使用 `--no-check-certificate` 绕过证书错误。

不再下载或编译已淘汰的 libmcrypt、mhash 和 mcrypt。PHP 7.4/8.0 以及需要源码构建的 MySQL 5.7 在 OpenSSL 3 系统上使用仅由这些旧进程加载的 `/usr/local/openssl-1.1` 隔离兼容库，不替换系统 OpenSSL。该兼容库不参与 Web 协议处理；Nginx 单独使用 OpenSSL 3.5 LTS，并直接编译其自带的 HTTP/2、HTTP/3 模块，不需要 nghttp2。PHP 8.1+ 使用操作系统提供的受支持 OpenSSL。

未输入数据库 root 密码时，安装器会生成强随机密码，并以 0600 权限保存到：

```text
/root/.lnmp-db-root-password
```

phpMyAdmin 使用随机 URL，路径以 0600 权限保存到：

```text
/root/.lnmp-phpmyadmin-path
```

默认站点不再部署 phpinfo、系统探针、Redis 测试页或 Opcache 管理面板。

## TLS 与证书

新增站点时，ACME 证书默认使用 `ec-256` ECC 密钥。RSA 与 ECC 都部署到 `/usr/local/nginx/conf/ssl/<域名>/<域名>.key` 和 `fullchain.cer`，路径不含 `_ecc`，更换密钥类型无需改 Web 配置。ACME 客户端内部状态隔离在 `/usr/local/acme.sh/certs`，不再写入 Nginx 证书目录。Nginx 模板仅启用 TLS 1.2/1.3。ACME 客户端固定到经过提交号核验的发布版本。

## 自动调优与日志

安装器按 CPU、物理内存、cgroup 内存限制和磁盘类型生成 Nginx worker、PHP-FPM 进程、内核队列及 MySQL/MariaDB 参数。数据库默认同时调优 InnoDB 和 MyISAM；选择 MyISAM-only 时只给 MyISAM 分配主要缓存，但 MySQL 5.7+ 的必需 InnoDB 引擎仍保留可用。可再次执行 `tools/tune.sh` 重新检测硬件。

Nginx 日志位于 `/usr/local/nginx/logs`，主 PHP 日志位于 `/usr/local/php/var/log`，多 PHP 日志位于各自前缀的 `var/log`。切割脚本使用锁、先移动再发送 USR1 重开、延迟压缩，并默认保留 30 天。

## 扩展

`addons.sh` 支持 `install`、`upgrade`、`uninstall` 和指定版本，例如：

```bash
./addons.sh upgrade phpredis 6.3.0 /usr/local/php7.4
./addons.sh upgrade redis 8.10.0 /usr/local/php
./addons.sh install imagick 3.8.1 /usr/local/php8.5
./addons.sh install swoole 5.1.8 /usr/local/php7.4
```

支持 phpredis、APCu、imagick/ImageMagick、memcached、memcache、Swoole、PECL imap、ionCube、SourceGuardian，以及 exif、fileinfo、ldap、bz2、sodium、Opcache 等随 PHP 源码构建的扩展。扩展会校验 PHP 最低版本和上游兼容范围。

SourceGuardian 可从厂商官网下载当前 Loader。请先阅读 `https://www.sourceguardian.com/termsloaders.html`；确认接受后，把许可确认参数放在命令末尾。脚本会识别 x86_64、armv7 或 aarch64，临时下载对应 `tar.gz` 和厂商 `.md5`，校验项目固定的 SHA-256、厂商 MD5、归档及 Loader 与 PHP 分支的兼容性，安装完成即删除临时下载。厂商更新无版本直链内容后，SHA-256 不匹配会安全停止，需要先人工核验新包并更新清单：

```bash
./addons.sh install sourceguardian --accept-sourceguardian-license
# 多 PHP 环境可明确指定目标 PHP：
./addons.sh install sourceguardian latest /usr/local/php8.5 --accept-sourceguardian-license
```

未提供许可确认参数时脚本会拒绝联网。离线或审计场景仍可先自行取得 `tar.gz` 和同名 `.md5`，再通过绝对路径安装：

```bash
./addons.sh install sourceguardian /root/loaders.linux-x86_64.tar.gz /usr/local/php8.5
```

## BBR

安装完成后可一键检查并启用 BBR：

```bash
lnmp bbr enable
lnmp bbr status
```

脚本要求 Linux 4.9 或更高版本，确认运行内核实际提供 `tcp_bbr` 后，才会写入 `/etc/sysctl.d/99-lnmp-bbr.conf`。

## 安全说明

- Redis 默认只监听回环地址、启用 protected mode，并以独立的 `redis` 系统用户运行。
- MySQL 5.7/8.0/8.4/9.7 与 MariaDB 10.6–12.3 默认只监听回环地址并关闭 `local_infile`；MySQL 8.4+ 不再启用 `mysql_native_password`。
- 安装和升级前会规范化数据及站点路径，并拒绝把系统顶级目录作为目标，避免误配置触发递归清空。
- PHP-FPM Unix socket 权限为 0660，PHP 隐藏版本信息并启用更严格的会话 Cookie 设置。
- Nginx 状态页仅允许本机访问；日志目录不再使用 0777 权限。
- systemd 服务启用 `NoNewPrivileges`、私有临时目录、内核保护和受限写目录等沙箱选项；MySQL/MariaDB/Redis socket 统一放在 `/run` 的专用运行目录。
- 安装器保留现有 firewalld、UFW 或 iptables 策略，只追加所需端口；Pure-FTPd 默认强制 TLS，并生成可替换的本地 ECC 初始证书。
- 安装器不再自动关闭 SELinux；启用强制模式的系统应按站点目录和自定义服务路径配置本机策略。
- 不要从历史项目域名恢复下载镜像，也不要执行来源不明的升级脚本。

## 升级前建议

升级已有服务器前，请备份数据库、站点文件、Web/PHP/MySQL 配置和证书，并先在同发行版的测试机演练。PHP 8.5、MySQL 9.7 和 MariaDB 12.3 可能需要业务代码或 SQL 兼容性调整；不要在没有可回滚备份的生产机上直接跨大版本升级。
