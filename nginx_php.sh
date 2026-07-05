#!/bin/sh

# メッセージ表示関数
start_message(){
echo ""
echo "======================開始: $1 ======================"
echo ""
}

end_message(){
echo ""
echo "======================完了: $1 ======================"
echo ""
}

# 起動メッセージ
cat <<EOF
-----------------------------------------------------
Buildree Nginx + PHP インストールスクリプト
-----------------------------------------------------
注意点：
  - AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linux専用
  - rootユーザーまたはsudo権限が必要
  - 新規環境での使用を推奨
  - 実行前にバックアップを推奨
  - nginxは.htaccessに対応していません。ディレクトリ単位の設定は
    /etc/nginx/conf.d/以下の設定ファイルで行ってください

目的：
  - nginxのインストール
  - PHP 8.2のインストール（remiリポジトリ使用、PHP-FPM）
  - SSL設定（OpenSSLによる自己署名証明書、mod_sslは使用しません）
  - gzip圧縮の有効化
  - サーバーバージョン情報の非表示
  - unicornユーザーの自動作成
  - SELinux対応の自動設定

ドキュメントルート: /var/www/html
EOF

read -p "インストールを続行しますか？ (y/n): " choice
[ "$choice" != "y" ] && { echo "インストールを中止しました。"; exit 0; }

# ディストリビューションとバージョンの検出
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DIST_ID=$ID
  DIST_VERSION_ID=$VERSION_ID
  DIST_NAME=$NAME
  DIST_MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
elif [ -f /etc/redhat-release ]; then
  if grep -q "CentOS Stream" /etc/redhat-release; then
    DIST_ID="centos-stream"
    DIST_VERSION_ID=$(grep -o -E '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
    DIST_MAJOR_VERSION=$(echo "$DIST_VERSION_ID" | cut -d. -f1)
    DIST_NAME="CentOS Stream"
  else
    DIST_ID="redhat"
    DIST_VERSION_ID=$(grep -o -E '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
    DIST_MAJOR_VERSION=$(echo "$DIST_VERSION_ID" | cut -d. -f1)
    DIST_NAME=$(cat /etc/redhat-release)
  fi
else
  echo "サポートされていないディストリビューションです"
  exit 1
fi

echo "検出されたディストリビューション: $DIST_NAME $DIST_VERSION_ID"

# Redhat系で8、9または10の場合のみ処理を実行
if [ -e /etc/redhat-release ] && [[ "$DIST_MAJOR_VERSION" -eq 8 || "$DIST_MAJOR_VERSION" -eq 9 || "$DIST_MAJOR_VERSION" -eq 10 ]]; then

    # Gitリポジトリのインストール
    start_message "Gitリポジトリのインストール"
    echo "Gitをインストールしています..."
    dnf -y install git
    end_message "Gitリポジトリのインストール"

    # EPELリポジトリとremiリポジトリのインストール
    start_message "EPELリポジトリとremiリポジトリのインストール"
    echo "EPELリポジトリとremiリポジトリをインストールします..."

    case $DIST_ID in
        "almalinux")
            GPG_KEY="https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux"
            ;;
        "rocky")
            GPG_KEY="https://download.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-$DIST_VERSION_ID"
            ;;
        "centos-stream" | "centos")
            GPG_KEY="https://www.centos.org/keys/RPM-GPG-KEY-CentOS-Official"
            ;;
        "rhel" | "redhat")
            GPG_KEY="https://www.redhat.com/security/data/fd431d51.txt"
            ;;
        "ol")
            GPG_KEY="https://yum.oracle.com/RPM-GPG-KEY-oracle-ol$DIST_VERSION_ID"
            ;;
        *)
            echo "警告: 認識されないディストリビューションですが、処理を続行します"
            GPG_KEY="https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux"
            ;;
    esac

    rpm --import $GPG_KEY
    dnf remove -y epel-release
    dnf -y install epel-release

    if [ "$DIST_MAJOR_VERSION" = "8" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    elif [ "$DIST_MAJOR_VERSION" = "9" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm
    elif [ "$DIST_MAJOR_VERSION" = "10" ]; then
        dnf -y install https://rpms.remirepo.net/enterprise/remi-release-10.rpm
    fi
    rpm --import https://rpms.remirepo.net/RPM-GPG-KEY-remi
    echo "リポジトリのインストールが完了しました"
    end_message "EPELリポジトリとremiリポジトリのインストール"

    # システムアップデート
    start_message "システムアップデート"
    echo "システムを最新版に更新します"
    dnf -y update
    end_message "システムアップデート"

    # nginxのインストール（公式リポジトリの安定版を使用）
    # AlmaLinux8のAppStream同梱nginxは1.14系(EOL)のため、
    # nginx.org公式リポジトリから最新安定版を導入する
    start_message "nginxのインストール"
    cat > /etc/yum.repos.d/nginx.repo <<'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
    dnf install -y nginx
    nginx -v
    end_message "nginxのインストール"

    # PHPを無効化してremiのPHP8.2を有効化
    start_message "PHP8.2の有効化"
    dnf module reset php -y
    echo "remiリポジトリのPHP8.2を有効化しています..."
    dnf module enable -y php:remi-8.2
    end_message "PHP8.2の有効化"

    # PHP8.2をインストール
    start_message "PHP8.2をインストール"
    dnf install -y libzip-devel
    dnf install -y php php-cli php-fpm php-mbstring php-xml php-json php-mysqlnd php-zip php-gd php-curl php-opcache php-common
    php -v
    end_message "PHP8.2をインストール"

    # ドキュメントルートの作成
    start_message "ドキュメントルートの作成"
    mkdir -p /var/www/html
    end_message "ドキュメントルートの作成"

    # php-fpmプールをnginxユーザーで動くように設定
    start_message "php-fpmプールの設定"
    sed -i -e "s|^user = apache|user = nginx|" /etc/php-fpm.d/www.conf
    sed -i -e "s|^group = apache|group = nginx|" /etc/php-fpm.d/www.conf
    sed -i -e "s|^listen.acl_users = apache|listen.acl_users = nginx|" /etc/php-fpm.d/www.conf
    sed -i -e "s|^;listen.owner = nobody|listen.owner = nginx|" /etc/php-fpm.d/www.conf
    sed -i -e "s|^;listen.group = nobody|listen.group = nginx|" /etc/php-fpm.d/www.conf
    end_message "php-fpmプールの設定"

    # nginx.confをBuildree用に書き換え
    start_message "nginx設定"
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
    # 公式リポジトリ版が置くデフォルトのserverブロックを無効化（80番の競合防止）
    [ -f /etc/nginx/conf.d/default.conf ] && mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
    cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;
    server_tokens       off;
    client_max_body_size 32m;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # SSL証明書の作成（OpenSSLによる自己署名証明書。mod_sslは使用しない）
    start_message "SSL証明書の作成"
    mkdir -p /etc/nginx/ssl
    if [ ! -f /etc/nginx/ssl/buildree.crt ]; then
        CERT_CN=$(hostname -f 2>/dev/null || hostname)
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/buildree.key \
            -out /etc/nginx/ssl/buildree.crt \
            -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Buildree/CN=${CERT_CN}"
        chmod 600 /etc/nginx/ssl/buildree.key
        echo "自己署名証明書を作成しました: /etc/nginx/ssl/buildree.crt"
        echo "本番運用では正式な証明書(Let's Encrypt等)に差し替えてください"
    else
        echo "証明書は既に存在するため作成をスキップしました"
    fi
    end_message "SSL証明書の作成"

    cat > /etc/nginx/conf.d/buildree.conf <<'EOF'
server {
    listen       80;
    listen       [::]:80;
    server_name  _;
    root         /var/www/html;
    index        index.php index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}

server {
    listen       443 ssl;
    listen       [::]:443 ssl;
    server_name  _;
    root         /var/www/html;
    index        index.php index.html index.htm;

    ssl_certificate     /etc/nginx/ssl/buildree.crt;
    ssl_certificate_key /etc/nginx/ssl/buildree.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    cat > /etc/nginx/conf.d/gzip.conf <<'EOF'
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF

    nginx -t
    end_message "nginx設定"

    # php.iniの設定変更
    start_message "php.iniの設定"
    echo "phpのバージョンを非表示にします..."
    sed -i -e "s|expose_php = On|expose_php = Off|" /etc/php.ini
    echo "phpのタイムゾーンを変更..."
    sed -i -e "s|;date.timezone =|date.timezone = Asia/Tokyo|" /etc/php.ini
    echo "PHPの実行範囲を制限..."
    sed -i -e "s|;open_basedir =|open_basedir = /var/www/html|" /etc/php.ini
    echo "ファイルアップロードサイズを設定..."
    sed -i -e "s|upload_max_filesize = 2M|upload_max_filesize = 32M|" /etc/php.ini
    sed -i -e "s|post_max_size = 8M|post_max_size = 32M|" /etc/php.ini
    end_message "php.iniの設定"

    # phpinfoの作成
    start_message "phpinfoの作成"
    touch /var/www/html/info.php
    echo '<?php phpinfo(); ?>' >> /var/www/html/info.php
    end_message "phpinfoの作成"

    # SELinuxの状態確認
    start_message "SELinuxの状態確認"
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "現在のSELinux状態: $SELINUX_STATUS"
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        if ! rpm -q policycoreutils-python-utils > /dev/null 2>&1; then
            dnf install -y policycoreutils-python-utils
        fi
        echo "ドキュメントルートのSELinuxコンテキストを設定しています..."
        semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html(/.*)?"
        restorecon -Rv /var/www/html
        setsebool -P httpd_can_network_connect=1
        setsebool -P httpd_enable_homedirs=1
    else
        echo "SELinuxはEnforcing状態ではないため、追加のポリシー設定はスキップします"
    fi
    end_message "SELinuxの状態確認"

    # ユーザーを作成
    start_message "unicornユーザー作成"
    USERNAME='unicorn'
    PASSWORD=$(< /dev/urandom tr -dc '[:alnum:]' | head -c32)

    useradd -m -s /bin/bash $USERNAME
    if [ $? -ne 0 ]; then
        echo "ユーザー作成に失敗しました。"
        exit 1
    fi
    echo "$PASSWORD" | passwd --stdin $USERNAME

    mkdir -p /home/${USERNAME}/.ssh
    chmod 700 /home/${USERNAME}/.ssh
    ssh-keygen -t ed25519 -N "" -f /home/${USERNAME}/.ssh/${USERNAME}
    chmod 644 /home/${USERNAME}/.ssh/${USERNAME}.pub
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
    cat /home/${USERNAME}/.ssh/${USERNAME}.pub >> /home/${USERNAME}/.ssh/authorized_keys
    chmod 600 /home/${USERNAME}/.ssh/authorized_keys
    chmod 600 /home/${USERNAME}/.ssh/${USERNAME}
    cp /home/${USERNAME}/.ssh/${USERNAME} /home/${USERNAME}/
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/${USERNAME}
    rm /home/${USERNAME}/.ssh/${USERNAME}

    echo "ed25519 SSH鍵が生成されました。"
    echo "秘密鍵: /home/${USERNAME}/${USERNAME}"
    echo "公開鍵: /home/${USERNAME}/.ssh/${USERNAME}.pub"
    echo "秘密鍵が /home/${USERNAME}/${USERNAME} に移動されました。"
    echo "秘密鍵のパーミッションは 600 に設定されています。"
    echo "このファイルを安全な方法でクライアントマシンに移動し、サーバーからは削除することを強く推奨します。"
    echo "秘密鍵はサーバー上に保管せず、使用するクライアントマシンにのみ保管してください。"
    echo "公開鍵をクライアントマシンの ~/.ssh/authorized_keys ファイルに追加してください。"
    echo "必要に応じて、秘密鍵にパスフレーズを設定してください。"
    echo "ユーザーのパスワードはランダムで生成されています。セキュリティの関係上表示したりファイルに残していないので新しく設定してください。"
    end_message "unicornユーザー作成"

    # ドキュメントルート所有者変更
    start_message "ドキュメントルート所有者変更"
    chown -R unicorn:nginx /var/www/html
    chmod 750 /var/www/html
    end_message "ドキュメントルート所有者変更"

    # サービス設定
    start_message "サービス設定"
    # nginx.org公式パッケージの既知の不具合対策:
    # 再起動時に古い/run/nginx.pidが残っているとPermission deniedで
    # 起動に失敗することがあるため、起動前に必ず削除するようにする
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=/usr/bin/rm -f /run/nginx.pid
EOF
    systemctl daemon-reload
    systemctl start php-fpm.service
    systemctl enable php-fpm
    systemctl start nginx.service
    systemctl enable nginx
    systemctl list-unit-files --type=service | grep -E "nginx|php-fpm"
    end_message "サービス設定"

    # ファイアウォール設定
    start_message "ファイアウォール設定"
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    firewall-cmd --list-all
    end_message "ファイアウォール設定"

    cat <<EOF

Nginx + PHPインストール完了！

アクセス方法:
- http://IPアドレス or ドメイン名
- https://IPアドレス or ドメイン名

設定ファイル: /etc/nginx/conf.d/buildree.conf
ドキュメントルート: /var/www/html

セキュリティ設定:
- ディレクトリトラバーサル対策として、PHPの実行範囲をドキュメントルート(/var/www/html)に制限しています
- ファイルアップロード上限: 32MB

注意:
- HTTPSはOpenSSLで作成した自己署名証明書で有効化済みです(/etc/nginx/ssl/buildree.crt)
  ブラウザで警告が出ますが、動作確認目的であればそのまま接続できます
- 本番運用する場合は、Let's Encrypt等の正式な証明書に差し替えてください
  （/etc/nginx/conf.d/buildree.conf のssl_certificate / ssl_certificate_keyを変更）
- php-fpmの設定変更後は systemctl restart php-fpm が必要です
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: nginx
EOF

else
    echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
    echo "検出されたOS: $DIST_NAME"
    echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
    exit 1
fi
