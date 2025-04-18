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

# RHEL系8/9のみ処理
if [ -e /etc/redhat-release ]; then
    DIST_VER=$(cat /etc/redhat-release | sed -e "s/.*\s\([0-9]\)\..*/\1/")
    
    if [ "$DIST_VER" = "8" ] || [ "$DIST_VER" = "9" ]; then
        # Gitリポジトリのインストール
        start_message "Gitリポジトリのインストール"
        dnf -y install git
        end_message "Gitリポジトリのインストール"



        # システムアップデート
        start_message "システムアップデート"
        curl --tlsv1.3 --proto https -o /tmp/update.sh https://raw.githubusercontent.com/buildree/common/main/system/update.sh
        chmod +x /tmp/update.sh
        source /tmp/update.sh
        rm -f /tmp/update.sh
        end_message "システムアップデート"

        # Apacheのインストール
        start_message "Apacheのインストール"
        dnf install -y httpd mod_ssl
        httpd -v
        end_message "Apacheのインストール"

        # Apacheの設定変更
        start_message "Apache設定"
        echo "Apacheの設定を変更します..."
        echo "ドキュメントルートでhtaccessを有効化しています..."
        echo "実行コマンド:sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf"
        sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf


        echo "セキュリティ強化のためサーバーバージョン情報を隠しています..."
        echo "実行コマンド: sed -i -e \"350i #バージョン非表示\" /etc/httpd/conf/httpd.conf"
        echo "実行コマンド: sed -i -e \"351i ServerTokens ProductOnly\" /etc/httpd/conf/httpd.conf"
        echo "実行コマンド: sed -i -e \"352i ServerSignature off \n\" /etc/httpd/conf/httpd.conf"
        sed -i -e "350i #バージョン非表示" /etc/httpd/conf/httpd.conf
        sed -i -e "351i ServerTokens ProductOnly" /etc/httpd/conf/httpd.conf
        sed -i -e "352i ServerSignature off \n" /etc/httpd/conf/httpd.conf
        end_message "Apache設定"


        # gzip圧縮設定
        cat > /etc/httpd/conf.d/gzip.conf <<'EOF'
SetOutputFilter DEFLATE
BrowserMatch ^Mozilla/4 gzip-only-text/html
BrowserMatch ^Mozilla/4\.0[678] no-gzip
BrowserMatch \bMSI[E] !no-gzip !gzip-only-text/html
SetEnvIfNoCase Request_URI\.(?:gif|jpe?g|png)$ no-gzip dont-vary
Header append Vary User-Agent env=!dont-var
EOF

        # unicornユーザー作成
        start_message "unicornユーザー作成"
        curl --tlsv1.3 --proto https -o /tmp/useradd.sh https://raw.githubusercontent.com/buildree/common/main/user/useradd.sh
        chmod +x /tmp/useradd.sh
        source /tmp/useradd.sh
        rm -f /tmp/useradd.sh
        end_message "unicornユーザー作成"

        # ドキュメントルート所有者変更
        start_message "ドキュメントルート所有者変更"
        chown -R unicorn:apache /var/www/html
        end_message "ドキュメントルート所有者変更"

        # Apacheサービス設定
        start_message "Apacheサービス設定"
        systemctl start httpd.service
        systemctl enable httpd
        systemctl list-unit-files --type=service | grep httpd
        end_message "Apacheサービス設定"

        # ファイアウォール設定
        start_message "ファイアウォール設定"
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        firewall-cmd --list-all
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