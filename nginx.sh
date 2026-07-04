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
Buildree Nginx インストールスクリプト
-----------------------------------------------------
注意点：
  - AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linux専用
  - rootユーザーまたはsudo権限が必要
  - 新規環境での使用を推奨
  - 実行前にバックアップを推奨
  - nginxは.htaccessに対応していません。ディレクトリ単位の設定は
    /etc/nginx/conf.d/以下の設定ファイルで行ってください

目的：
  - nginx 1.20系のインストール
  - SSL設定（OpenSSLによる自己署名証明書、mod_sslは使用しません）
  - gzip圧縮の有効化
  - サーバーバージョン情報の非表示
  - unicornユーザーの自動作成

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

# RHEL系8/9/10のみ処理
if [ -e /etc/redhat-release ]; then
    DIST_VER=$(cat /etc/redhat-release | sed -e "s/.*\s\([0-9]\)\..*/\1/")

    if [ "$DIST_VER" = "8" ] || [ "$DIST_VER" = "9" ] || [ "$DIST_VER" = "10" ]; then
        # Gitリポジトリのインストール
        start_message "Gitリポジトリのインストール"
        dnf -y install git
        end_message "Gitリポジトリのインストール"

        # システムアップデート
        start_message "システムアップデート"
        dnf -y update
        end_message "システムアップデート"

        # nginxのインストール
        start_message "nginxのインストール"
        dnf install -y nginx
        nginx -v
        end_message "nginxのインストール"

        # ドキュメントルートの作成
        start_message "ドキュメントルートの作成"
        mkdir -p /var/www/html
        cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ja">
<head><meta charset="UTF-8"><title>Buildree</title></head>
<body><h1>nginxのインストールが完了しました</h1></body>
</html>
EOF
        end_message "ドキュメントルートの作成"

        # nginxの設定変更
        start_message "nginx設定"
        echo "nginx.confをBuildree用に書き換えます（同梱のデフォルトserverブロックは削除）..."
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
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

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
}
EOF

        end_message "nginx設定"

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

        echo "Buildree用のサーバーブロックを作成しています..."
        cat > /etc/nginx/conf.d/buildree.conf <<'EOF'
server {
    listen       80;
    listen       [::]:80;
    server_name  _;
    root         /var/www/html;
    index        index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen       443 ssl;
    listen       [::]:443 ssl;
    server_name  _;
    root         /var/www/html;
    index        index.html index.htm;

    ssl_certificate     /etc/nginx/ssl/buildree.crt;
    ssl_certificate_key /etc/nginx/ssl/buildree.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

        # gzip圧縮設定
        start_message "gzip圧縮設定"
        cat > /etc/nginx/conf.d/gzip.conf <<'EOF'
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF
        end_message "gzip圧縮設定"

        # 設定ファイルのチェック
        start_message "nginx設定チェック"
        nginx -t
        end_message "nginx設定チェック"

        # unicornユーザー作成
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

        # nginxサービス設定
        start_message "nginxサービス設定"
        systemctl start nginx.service
        systemctl enable nginx
        systemctl list-unit-files --type=service | grep nginx
        end_message "nginxサービス設定"

        # ファイアウォール設定
        start_message "ファイアウォール設定"
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        firewall-cmd --list-all
        end_message "ファイアウォール設定"

        cat <<EOF

nginxインストール完了！

アクセス方法:
- http://IPアドレス or ドメイン名
- https://IPアドレス or ドメイン名

設定ファイル: /etc/nginx/conf.d/buildree.conf
ドキュメントルート: /var/www/html

注意:
- HTTPSはOpenSSLで作成した自己署名証明書で有効化済みです(/etc/nginx/ssl/buildree.crt)
  ブラウザで警告が出ますが、動作確認目的であればそのまま接続できます
- 本番運用する場合は、Let's Encrypt等の正式な証明書に差し替えてください
  （/etc/nginx/conf.d/buildree.conf のssl_certificate / ssl_certificate_keyを変更）
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: nginx
EOF

    else
        echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
        echo "検出されたOS: $DIST_NAME"
        echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
        exit 1
    fi
fi
