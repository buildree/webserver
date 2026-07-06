#!/bin/sh

# メッセージ表示関数
EXECUTED_STEPS=""
WARNINGS=""

start_message(){
echo ""
echo "======================開始: $1 ======================"
echo ""
EXECUTED_STEPS="${EXECUTED_STEPS}- $1"$'\n'
}

end_message(){
echo ""
echo "======================完了: $1 ======================"
echo ""
}

warn_message(){
echo "警告: $1"
WARNINGS="${WARNINGS}- $1"$'\n'
}

# 起動メッセージ
cat <<EOF
-----------------------------------------------------
Buildree Nginx & React (Vite + TypeScript) インストールスクリプト
-----------------------------------------------------
注意点：
  - AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linux専用
  - rootユーザーまたはsudo権限が必要
  - 新規環境での使用を推奨
  - 実行前にバックアップを推奨
  - Reactアプリは静的ファイルにビルドしてnginxで配信します
    (Node.jsはビルド時のみ使用し、常駐サーバーは起動しません)

目的：
  - nginxのインストール（nginx.org公式リポジトリの安定版）
  - SSL設定（OpenSSLによる自己署名証明書、mod_sslは使用しません）
  - gzip圧縮の有効化
  - サーバーバージョン情報の非表示
  - Node.jsのインストール（ビルド用）
  - Vite + React + TypeScriptプロジェクトの作成・ビルド・配信
  - React Router等のクライアントサイドルーティング対応
  - unicornユーザーの自動作成

ドキュメントルート: /var/www/html
EOF

read -p "インストールを続行しますか？ (y/n): " choice
[ "$choice" != "y" ] && { echo "インストールを中止しました。"; exit 0; }

# プロジェクト名の設定
read -p "Reactプロジェクト名を入力してください (デフォルト: buildree-app): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-buildree-app}
# 安全のため英数字・ハイフン・アンダースコアのみ許可
# (パストラバーサルやコマンドインジェクションを防ぐため)
if ! echo "$PROJECT_NAME" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    echo "エラー: プロジェクト名は英数字・ハイフン・アンダースコアのみ使用できます"
    exit 1
fi
echo "プロジェクト名: $PROJECT_NAME"

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

        # Node.jsのインストール（ビルド用）
        # EL10のAppStreamにはnodejs:20ストリームが無いため、EL10のみnodejs:22を使用
        if [ "$DIST_VER" = "10" ]; then
            NODEJS_STREAM="22"
        else
            NODEJS_STREAM="20"
        fi
        start_message "Node.jsのインストール"
        dnf module reset -y nodejs
        dnf module install -y nodejs:${NODEJS_STREAM}
        echo "インストールされたNode.jsのバージョン:"
        node -v
        echo "インストールされたnpmのバージョン:"
        npm -v
        end_message "Node.jsのインストール"

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

        # Reactアプリケーション(Vite + React + TypeScript)のインストール
        start_message "Reactアプリケーションのインストール"
        mkdir -p /var/www/html
        mkdir -p /var/www/$PROJECT_NAME
        chown -R unicorn:nginx /var/www/$PROJECT_NAME

        echo "Vite + React + TypeScriptプロジェクトを作成しています..."
        su - unicorn -c "cd /var/www/$PROJECT_NAME && npm create vite@latest . -y -- --template react-ts"

        echo "依存パッケージをインストールしています..."
        su - unicorn -c "cd /var/www/$PROJECT_NAME && npm install"

        echo "Reactアプリをビルドしています..."
        su - unicorn -c "cd /var/www/$PROJECT_NAME && npm run build"

        echo "ビルド結果を/var/www/htmlに配置しています..."
        cp -r /var/www/$PROJECT_NAME/dist/* /var/www/html/
        chown -R unicorn:nginx /var/www/html
        chmod 750 /var/www/html
        end_message "Reactアプリケーションのインストール"

        # nginxの設定変更
        start_message "nginx設定"
        echo "nginx.confをBuildree用に書き換えます（同梱のデフォルトserverブロックは削除）..."
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

        # SPAルーティング対応(React Router等) - $uriが見つからなければindex.htmlにフォールバック
        echo "Buildree用のサーバーブロックを作成しています..."
        cat > /etc/nginx/conf.d/buildree.conf <<'EOF'
server {
    listen       80;
    listen       [::]:80;
    server_name  _;
    root         /var/www/html;
    index        index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen       443 ssl;
    listen       [::]:443 ssl;
    server_name  _;
    root         /var/www/html;
    index        index.html;

    ssl_certificate     /etc/nginx/ssl/buildree.crt;
    ssl_certificate_key /etc/nginx/ssl/buildree.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        try_files $uri $uri/ /index.html;
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

        # SELinuxの状態確認
        # nginxはApacheと同じhttpd_tドメインで動作するため、ドキュメントルートに
        # httpd_sys_content_tを付与しないと403 Forbiddenになる
        start_message "SELinuxの状態確認"
        SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
        echo "現在のSELinux状態: $SELINUX_STATUS"
        if [ "$SELINUX_STATUS" = "Enforcing" ]; then
            if ! rpm -q policycoreutils-python-utils > /dev/null 2>&1; then
                echo "SELinux管理ツールをインストールしています..."
                dnf install -y policycoreutils-python-utils
            fi
            echo "ドキュメントルートのSELinuxコンテキストを設定しています..."
            semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"
            restorecon -Rv /var/www/html
        else
            warn_message "SELinuxはEnforcing状態ではないため、追加のポリシー設定はスキップします"
        fi
        end_message "SELinuxの状態確認"

        # nginxサービス設定
        start_message "nginxサービス設定"
        # nginx.org公式パッケージの既知の不具合対策:
        # 再起動時に古い/run/nginx.pidが残っているとPermission deniedで
        # 起動に失敗することがあるため、起動前に必ず削除するようにする
        mkdir -p /etc/systemd/system/nginx.service.d
        cat > /etc/systemd/system/nginx.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=/usr/bin/rm -f /run/nginx.pid
EOF
        systemctl daemon-reload
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

        build_summary() {
            cat <<SUMMARYEOF
Buildree インストールサマリー - $(date '+%Y-%m-%d %H:%M:%S')

======================実行内容サマリー======================
${EXECUTED_STEPS}
======================作成・変更したファイル======================
- /etc/yum.repos.d/nginx.repo (新規作成: nginx公式リポジトリ)
- /var/www/$PROJECT_NAME/ (新規作成: Vite + React + TypeScriptプロジェクトソース)
- /var/www/html/ (新規作成: Reactビルド成果物(dist)の配置)
- /etc/nginx/nginx.conf (上書き: Buildree用設定、元ファイルは/etc/nginx/nginx.conf.origに保存)
- /etc/nginx/conf.d/default.conf.disabled (リネーム: 同梱デフォルトserverブロックの無効化、存在した場合のみ)
- /etc/nginx/ssl/buildree.crt / buildree.key (新規作成: 自己署名SSL証明書、既存の場合はスキップ)
- /etc/nginx/conf.d/buildree.conf (新規作成: Buildree用serverブロック、SPAフォールバック設定含む)
- /etc/nginx/conf.d/gzip.conf (新規作成: gzip圧縮設定)
- /etc/systemd/system/nginx.service.d/override.conf (新規作成: 起動前にnginx.pidを削除するExecStartPre設定)
- /var/www/html (所有者変更: unicorn:nginx、パーミッション750、SELinuxコンテキスト設定はEnforcing時のみ)
- /home/${USERNAME}/${USERNAME} (新規作成: SSH秘密鍵)
- /home/${USERNAME}/.ssh/${USERNAME}.pub (新規作成: SSH公開鍵)
- /home/${USERNAME}/.ssh/authorized_keys (新規作成: 公開鍵登録)

======================unicornユーザーの認証情報======================
- ログイン方式: SSH鍵認証(ed25519)
- 秘密鍵: /home/unicorn/${USERNAME}  (パーミッション600)
- 公開鍵: /home/unicorn/.ssh/${USERNAME}.pub
- OSログインパスワードはランダム生成後、画面表示・ファイル保存はしていません(セキュリティのため)。必要な場合は passwd unicorn で再設定してください。

======================警告======================
$( [ -n "$WARNINGS" ] && printf '%s' "$WARNINGS" || echo "警告はありませんでした" )

======================アクセス方法・注意事項======================
アクセス方法:
- http://IPアドレス or ドメイン名
- https://IPアドレス or ドメイン名（自己署名証明書、ブラウザ警告あり）

設定ファイル: /etc/nginx/conf.d/buildree.conf
ドキュメントルート: /var/www/html（Viteのビルド成果物 = dist/ の中身を配置済み）
プロジェクトソース: /var/www/$PROJECT_NAME（src/以下を編集してください）

Reactアプリケーション管理:
- ソースの編集: /var/www/$PROJECT_NAME/src
- 再ビルド: su - unicorn -c "cd /var/www/$PROJECT_NAME && npm run build"
- 再ビルド後は /var/www/$PROJECT_NAME/dist の中身を /var/www/html にコピーしてください
  (cp -r /var/www/$PROJECT_NAME/dist/* /var/www/html/)

注意:
- Node.js/npmはビルド時のみ使用しており、常駐サーバーは起動していません
  (静的ファイルをnginxが直接配信する構成です)
- HTTPSはOpenSSLで作成した自己署名証明書で有効化済みです(/etc/nginx/ssl/buildree.crt)
- 本番運用する場合は、Let's Encrypt等の正式な証明書に差し替えてください
  （/etc/nginx/conf.d/buildree.conf のssl_certificate / ssl_certificate_keyを変更）
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: nginx
SUMMARYEOF
        }

        SUMMARY_TEXT=$(build_summary)
        echo "$SUMMARY_TEXT"
        echo "$SUMMARY_TEXT" > /home/unicorn/buildree_install_summary.txt
        chown unicorn:unicorn /home/unicorn/buildree_install_summary.txt
        chmod 600 /home/unicorn/buildree_install_summary.txt
        echo ""
        echo "このサマリーは /home/unicorn/buildree_install_summary.txt に保存されました。"

    else
        echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
        echo "検出されたOS: $DIST_NAME"
        echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
        exit 1
    fi
fi
