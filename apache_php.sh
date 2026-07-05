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
  # メジャーバージョン番号の抽出（8.10から8を取得）
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
    echo "Gitのインストールが完了しました"
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
        start_message
        echo "システムを最新版に更新します"
        dnf -y update
        end_message

    # SELinuxの状態確認（ツールのインストールの代わりにチェックのみ実行）
    start_message "SELinuxの状態確認"
    echo "システムのSELinux状態を確認しています..."
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "現在のSELinux状態: $SELINUX_STATUS"
    
    # SELinuxがEnforcingの場合のみ、管理ツールをインストール
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo "SELinuxがEnforcing状態です。必要なユーティリティがなければインストールします..."
        if ! rpm -q policycoreutils-python-utils > /dev/null 2>&1; then
            echo "SELinux管理ツールをインストールしています..."
            dnf install -y policycoreutils-python-utils
            echo "SELinux管理ツールのインストールが完了しました"
        else
            echo "SELinux管理ツールは既にインストールされています"
        fi
    else
        echo "SELinuxはEnforcing状態ではないため、追加のSELinuxツールのインストールはスキップします"
    fi
    end_message "SELinuxの状態確認"

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
    echo "アップロードサイズを32MBに設定しました"
    end_message "php.iniの設定"

    # phpinfoの作成
    start_message "phpinfoの作成"
    echo "PHPの情報確認用ファイル(info.php)を作成しています..."
    touch /var/www/html/info.php
    echo '<?php phpinfo(); ?>' >> /var/www/html/info.php
    echo "info.phpの内容:"
    cat /var/www/html/info.php
    echo "info.phpの作成が完了しました"
    end_message "phpinfoの作成"

    # アップロードディレクトリの作成（学習・テスト環境用）
    start_message "アップロードディレクトリの作成"
    echo "アップロード用ディレクトリを作成しています（学習・テスト環境用）..."
    mkdir -p /var/www/html/upload
    echo "アップロードディレクトリを作成しました"
    echo "※注意: 本番環境では専用のLAMP環境やWordPress専用環境の構築を推奨します"
    end_message "アップロードディレクトリの作成"

        # ユーザーを作成
        start_message
        echo "unicornユーザーを作成します"

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
        end_message

    # ドキュメントルート所有者変更
    start_message "ドキュメントルート所有者変更"
    echo "ドキュメントルートの所有者をunicorn:apacheに変更しています..."
    chown -R unicorn:apache /var/www/html
    echo "所有者の変更が完了しました"
    end_message "ドキュメントルート所有者変更"

    # SELinux設定
    start_message "SELinux設定"
    # SELinuxの状態を確認
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "現在のSELinux状態: $SELINUX_STATUS"
    
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo "SELinuxがEnforcing状態のため、必要なポリシーを設定します..."
        
        # ドキュメントルートのコンテキスト設定
        echo "ドキュメントルートのSELinuxコンテキストを設定しています..."
        semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"
        restorecon -Rv /var/www/html
        
        # アップロードディレクトリの書き込み許可
        echo "アップロードディレクトリに書き込み権限を設定しています..."
        semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/upload(/.*)?"
        restorecon -Rv /var/www/html/upload
        
        # PHP-FPMの接続許可
        echo "PHP-FPMとの接続を許可しています..."
        setsebool -P httpd_can_network_connect=1
        
        echo "SELinuxのポリシー設定が完了しました"
    elif [ "$SELINUX_STATUS" = "Permissive" ]; then
        echo "SELinuxはPermissive状態です。必要に応じてEnforcing状態に変更してください。"
        echo "※Enforcing状態に変更する場合は、再度このスクリプトを実行するか、SELinuxポリシーを手動で設定してください。"
    else
        echo "SELinuxが無効またはインストールされていないため、SELinuxポリシー設定をスキップします"
    fi
    end_message "SELinux設定"

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

PHPの動作確認:
- http://IPアドレス or ドメイン名/info.php にアクセスするとphpinfo()の内容が表示されます
- 確認後はセキュリティのため info.php を削除することを推奨します
  (rm -f /var/www/html/info.php)

設定ファイル: /etc/httpd/conf.d/ドメイン名.conf
ドキュメントルート: /var/www/html

セキュリティ設定:
- ディレクトリトラバーサル対応のため、PHP実行範囲をドキュメントルート(/var/www/html)に制限しています
- ファイルアップロード上限: 32MB
- アップロード専用ディレクトリ: /var/www/html/upload（書き込み権限設定済み）

SELinux設定:
- SELinuxがEnforcing状態の場合のみ、必要なポリシーを適用済み
- ドキュメントルート(/var/www/html)には通常のWebコンテンツ用ポリシーを適用
- アップロードディレクトリ(/var/www/html/upload)には書き込み可能なポリシーを適用
- PHP-FPMとの接続を許可済み

データベース利用時の注意事項:
- MySQLなどのデータベースを後からインストールする場合、SELinuxで以下の設定が必要:
  sudo setsebool -P httpd_can_network_connect_db=1

学習・テスト環境としての利用:
- 本スクリプトで作成した環境は学習・テスト用に最適化されています
- WordPressなどの本格的なCMSを使用する場合は、専用のLAMP環境構築を推奨します

注意事項:
- WordPressなどでさらに大きなファイルをアップロードしたい場合は以下の方法で変更できます:
  1. php.ini編集: /etc/php.ini の「upload_max_filesize」と「post_max_size」の値を変更
  2. .htaccess使用: ドキュメントルート内の.htaccessファイルに以下を追記
     php_value upload_max_filesize 64M
     php_value post_max_size 64M
     php_value memory_limit 128M
- Apache再起動は不要ですが、PHP-FPMの再起動が必要です: systemctl restart php-fpm
- HTTP/2を有効にするには、SSLの設定ファイルに「Protocols h2 http/1.1」を追記してください
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: apache
EOF

else
    echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
    echo "検出されたOS: $DIST_NAME"
    echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
    exit 1
fi