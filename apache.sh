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

hash_file="/tmp/hashes.txt"
expected_sha3_512="efbdceddcbeb6c3dd41cfde3cab4cda01208cab2bbb932696562e006af9fc5ef7965e6bd6ff9ab4fd154385e4fad5b16ce7374be19750175cf1e8804b94372ec"

# リポジトリのシェルファイルの格納場所
update_file_path="/tmp/update.sh"
useradd_file_path="/tmp/useradd.sh"

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
    
    if [ "$DIST_VER" = "8" ] || [ "$DIST_VER" = "9" ] || [ "$DIST_VER" = "10" ]; then
        # ハッシュファイルのダウンロード
        start_message "ハッシュ検証ファイルのダウンロード"
        if ! curl --tlsv1.3 --proto https -o "$hash_file" https://raw.githubusercontent.com/buildree/common/main/other/hashes.txt; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        # ファイルのSHA3-512ハッシュ値を計算
        actual_sha3_512=$(sha3sum -a 512 "$hash_file" 2>/dev/null | awk '{print $1}')
        if [ -z "$actual_sha3_512" ]; then
            actual_sha3_512=$(openssl dgst -sha3-512 "$hash_file" 2>/dev/null | awk '{print $2}')

            if [ -z "$actual_sha3_512" ]; then
                echo "エラー: SHA3-512ハッシュの計算に失敗しました。sha3sumまたはOpenSSLがインストールされていることを確認してください。"
                rm -f "$hash_file"
                exit 1
            fi
        fi

        if [ "$actual_sha3_512" == "$expected_sha3_512" ]; then
            echo "ハッシュ値は一致します。ファイルを保存します。"
            update_hash=$(grep "^update_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            update_hash_sha3=$(grep "^update_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
            useradd_hash=$(grep "^useradd_hash_sha512=" "$hash_file" | cut -d '=' -f 2)
            useradd_hash_sha3=$(grep "^useradd_hash_sha3_512=" "$hash_file" | cut -d '=' -f 2)
        else
            echo "ハッシュ値が一致しません。ファイルを削除します。"
            echo "期待されるSHA3-512: $expected_sha3_512"
            echo "実際のSHA3-512: $actual_sha3_512"
            rm -f "$hash_file"
            exit 1
        fi
        end_message "ハッシュ検証ファイルのダウンロード"

        # Gitリポジトリのインストール
        start_message "Gitリポジトリのインストール"
        dnf -y install git
        end_message "Gitリポジトリのインストール"



        # システムアップデート
        start_message "システムアップデート"
        if ! curl --tlsv1.3 --proto https -o "$update_file_path" https://raw.githubusercontent.com/buildree/common/main/system/update.sh; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        actual_sha512=$(sha512sum "$update_file_path" 2>/dev/null | awk '{print $1}')
        actual_sha3_512=$(sha3sum -a 512 "$update_file_path" 2>/dev/null | awk '{print $1}')
        if [ -z "$actual_sha3_512" ]; then
            actual_sha3_512=$(openssl dgst -sha3-512 "$update_file_path" 2>/dev/null | awk '{print $2}')
        fi

        if [ "$actual_sha512" == "$update_hash" ] && [ "$actual_sha3_512" == "$update_hash_sha3" ]; then
            echo "ハッシュ検証が成功しました。システムアップデートを実行します..."
            chmod +x "$update_file_path"
            source "$update_file_path"
            rm -f "$update_file_path"
        else
            echo "エラー: システムアップデートスクリプトのハッシュ検証に失敗しました。"
            echo "期待されるSHA512: $update_hash"
            echo "実際のSHA512: $actual_sha512"
            echo "期待されるSHA3-512: $update_hash_sha3"
            echo "実際のSHA3-512: $actual_sha3_512"
            rm -f "$update_file_path"
            exit 1
        fi
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
        if ! curl --tlsv1.3 --proto https -o "$useradd_file_path" https://raw.githubusercontent.com/buildree/common/main/user/useradd.sh; then
            echo "エラー: ファイルのダウンロードに失敗しました"
            exit 1
        fi

        actual_sha512=$(sha512sum "$useradd_file_path" 2>/dev/null | awk '{print $1}')
        actual_sha3_512=$(sha3sum -a 512 "$useradd_file_path" 2>/dev/null | awk '{print $1}')
        if [ -z "$actual_sha3_512" ]; then
            actual_sha3_512=$(openssl dgst -sha3-512 "$useradd_file_path" 2>/dev/null | awk '{print $2}')
        fi

        if [ "$actual_sha512" == "$useradd_hash" ] && [ "$actual_sha3_512" == "$useradd_hash_sha3" ]; then
            echo "ハッシュ検証が成功しました。ユーザー作成を実行します..."
            chmod +x "$useradd_file_path"
            source "$useradd_file_path"
            rm -f "$useradd_file_path"
        else
            echo "エラー: ユーザー作成スクリプトのハッシュ検証に失敗しました。"
            echo "期待されるSHA512: $useradd_hash"
            echo "実際のSHA512: $actual_sha512"
            echo "期待されるSHA3-512: $useradd_hash_sha3"
            echo "実際のSHA3-512: $actual_sha3_512"
            rm -f "$useradd_file_path"
            exit 1
        fi
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
        echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
        echo "検出されたOS: $DIST_NAME"
        echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
        exit 1
    fi
fi