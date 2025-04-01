#!/bin/sh

# メッセージ表示関数
start_message() {
    echo ""
    echo "======================開始: $1 ======================"
    echo ""
}

end_message() {
    echo ""
    echo "======================完了: $1 ======================"
    echo ""
}

# 起動メッセージ
cat <<EOF
-----------------------------------------------------
Buildree Apache インストールスクリプト
-----------------------------------------------------
注意点：
  - AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linux専用
  - rootユーザーまたはsudo権限が必要
  - 新規環境での使用を推奨
  - 実行前にバックアップを推奨

目的：
  - Apache 2.4系のインストール
  - SSL設定
  - gzip圧縮の有効化
  - htaccess許可
  - PHP 8.2のインストール（remiリポジトリ使用）
  - PHP-FPMの設定
  - unicornユーザーの自動作成

ドキュメントルート: /var/www/html
EOF

read -p "インストールを続行しますか？ (y/n): " choice
[ "$choice" != "y" ] && { echo "インストールを中止しました。"; exit 0; }

# ディストリビューションとバージョンの検出
echo "ディストリビューションとバージョンを検出しています..."
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
echo "検出されたOS: $DIST_NAME バージョン: $DIST_VERSION_ID"

# RHEL系8/9のみ処理
if [ -e /etc/redhat-release ]; then
    DIST_VER=$(cat /etc/redhat-release | sed -e "s/.*\s\([0-9]\)\..*/\1/")
    
    if [ "$DIST_VER" = "8" ] || [ "$DIST_VER" = "9" ]; then
        # Gitリポジトリのインストール
        start_message "Gitリポジトリのインストール"
        echo "Gitをインストールしています..."
        dnf -y install git
        echo "Gitのインストールが完了しました"
        end_message "Gitリポジトリのインストール"

        # EPELリポジトリとremiリポジトリのインストール
        start_message "EPELリポジトリとremiリポジトリのインストール"
        echo "EPELリポジトリとremiリポジトリをインストールします..."
        curl --tlsv1.3 --proto https -o /tmp/repository.sh https://raw.githubusercontent.com/buildree/common/main/system/repository.sh
        echo "リポジトリスクリプトをダウンロードしました"
        chmod +x /tmp/repository.sh
        echo "リポジトリスクリプトを実行します..."
        source /tmp/repository.sh
        echo "リポジトリのインストールが完了しました"
        end_message "EPELリポジトリとremiリポジトリのインストール"

        # システムアップデート
        start_message "システムアップデート"
        echo "アップデートスクリプトをダウンロードしています..."
        curl --tlsv1.3 --proto https -o /tmp/update.sh https://raw.githubusercontent.com/buildree/common/main/system/update.sh
        chmod +x /tmp/update.sh
        echo "システムをアップデートしています..."
        source /tmp/update.sh
        rm -f /tmp/update.sh
        echo "システムアップデートが完了しました"
        end_message "システムアップデート"

        # Apacheのインストール
        start_message "Apacheのインストール"
        echo "Apache HTTPサーバーとSSLモジュールをインストールしています..."
        dnf install -y httpd mod_ssl
        echo "インストールされたApacheのバージョン:"
        httpd -v
        echo "Apacheのインストールが完了しました"
        end_message "Apacheのインストール"

        # gzip圧縮設定
        start_message "gzip圧縮設定"
        echo "gzip圧縮の設定ファイルを作成しています..."
        cat > /etc/httpd/conf.d/gzip.conf <<'EOF'
SetOutputFilter DEFLATE
BrowserMatch ^Mozilla/4 gzip-only-text/html
BrowserMatch ^Mozilla/4\.0[678] no-gzip
BrowserMatch \bMSI[E] !no-gzip !gzip-only-text/html
SetEnvIfNoCase Request_URI\.(?:gif|jpe?g|png)$ no-gzip dont-vary
Header append Vary User-Agent env=!dont-var
EOF
        echo "gzip圧縮の設定が完了しました"
        end_message "gzip圧縮設定"
        
        # 標準のPHPを無効化
        start_message "標準のPHPを無効化"
        echo "標準のPHPモジュールをリセットしています..."
        dnf module reset php -y
        echo "remiリポジトリのPHP8.2を有効化しています..."
        dnf module enable -y php:remi-8.2
        echo "PHP8.2モジュールの有効化が完了しました"
        end_message "標準のPHPを無効化"

        # PHP8.2をインストール
        start_message "PHP8.2をインストール"
        echo "PHPの依存ライブラリ(libzip-devel)をインストールしています..."
        dnf install -y libzip-devel
        echo "PHP8.2と必要なモジュールをインストールしています..."
        echo "インストール中のパッケージ: php php-cli php-fpm php-mbstring php-xml php-json php-mysqlnd php-zip php-gd php-curl php-openssl php-tokenizer php-xmlwriter php-common"
        dnf install -y php php-cli php-fpm php-mbstring php-xml php-json php-mysqlnd php-zip php-gd php-curl php-openssl php-tokenizer php-xmlwriter php-common
        echo "PHP8.2のインストールが完了しました"
        echo "インストールされたPHPのバージョン:"
        php -v
        end_message "PHP8.2をインストール"

        # php-fpmで動くように追記
        start_message "php-fpmで動くように追記"
        echo "Apache設定にPHP-FPM用のハンドラーを追加しています..."
        sed -i -e "357i #FastCGI追記" /etc/httpd/conf/httpd.conf
        sed -i -e "358i <FilesMatch \.php$>" /etc/httpd/conf/httpd.conf
        sed -i -e '359i     SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost/"' /etc/httpd/conf/httpd.conf
        sed -i -e "360i </FilesMatch>" /etc/httpd/conf/httpd.conf
        echo "PHP-FPM設定の追加が完了しました"
        end_message "php-fpmで動くように追記"

        # phpinfoの作成
        start_message "phpinfoの作成"
        echo "PHPの情報確認用ファイル(info.php)を作成しています..."
        touch /var/www/html/info.php
        echo '<?php phpinfo(); ?>' >> /var/www/html/info.php
        echo "info.phpの内容:"
        cat /var/www/html/info.php
        echo "info.phpの作成が完了しました"
        end_message "phpinfoの作成"

        # unicornユーザー作成
        start_message "unicornユーザー作成"
        echo "unicornユーザー作成スクリプトをダウンロードしています..."
        curl --tlsv1.3 --proto https -o /tmp/useradd.sh https://raw.githubusercontent.com/buildree/common/main/user/useradd.sh
        chmod +x /tmp/useradd.sh
        echo "unicornユーザーを作成しています..."
        source /tmp/useradd.sh
        rm -f /tmp/useradd.sh
        echo "unicornユーザーの作成が完了しました"
        end_message "unicornユーザー作成"

        # ドキュメントルート所有者変更
        start_message "ドキュメントルート所有者変更"
        echo "ドキュメントルートの所有者をunicorn:apacheに変更しています..."
        chown -R unicorn:apache /var/www/html
        echo "所有者の変更が完了しました"
        end_message "ドキュメントルート所有者変更"

        # Apacheサービス設定
        start_message "Apacheサービス設定"
        echo "Apache HTTPサービスを起動しています..."
        systemctl start httpd.service
        echo "Apache HTTPサービスを自動起動に設定しています..."
        systemctl enable httpd
        echo "Apache HTTPサービスの状態:"
        systemctl list-unit-files --type=service | grep httpd
        echo "Apacheサービスの設定が完了しました"
        end_message "Apacheサービス設定"

        # PHP-fpmのサービス設定
        start_message "PHP-fpmのサービス設定"
        echo "PHP-FPMサービスを起動しています..."
        systemctl start php-fpm.service
        echo "PHP-FPMサービスを自動起動に設定しています..."
        systemctl enable php-fpm
        echo "PHP-FPMサービスの状態:"
        systemctl list-unit-files --type=service | grep php-fpm
        echo "PHP-FPMサービスの設定が完了しました"
        end_message "PHP-fpmのサービス設定"

        # ファイアウォール設定
        start_message "ファイアウォール設定"
        echo "ファイアウォールでHTTPを許可しています..."
        firewall-cmd --permanent --add-service=http
        echo "ファイアウォールでHTTPSを許可しています..."
        firewall-cmd --permanent --add-service=https
        echo "ファイアウォール設定を再読み込みしています..."
        firewall-cmd --reload
        echo "ファイアウォールの現在の設定:"
        firewall-cmd --list-all
        echo "ファイアウォール設定が完了しました"
        end_message "ファイアウォール設定"

        cat <<EOF

Apacheインストール完了！

アクセス方法:
- http://IPアドレス or ドメイン名
- https://IPアドレス or ドメイン名

設定ファイル: /etc/httpd/conf.d/ドメイン名.conf
ドキュメントルート: /var/www/html

注意:
- HTTP/2を有効にするには、SSLの設定ファイルに「Protocols h2 http/1.1」を追記してください
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: apache
EOF

    else
        echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8または9専用です。"
        echo "検出されたOS: $DIST_NAME"
        echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
        exit 1
    fi
fi