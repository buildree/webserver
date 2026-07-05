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

        build_summary() {
            cat <<SUMMARYEOF
Buildree インストールサマリー - $(date '+%Y-%m-%d %H:%M:%S')

======================実行内容サマリー======================
${EXECUTED_STEPS}
======================作成・変更したファイル======================
- /etc/httpd/conf/httpd.conf (設定変更: AllowOverride All、ServerTokens/ServerSignature追加)
- /etc/httpd/conf.d/gzip.conf (新規作成: gzip圧縮設定)
- /var/www/html (所有者変更: unicorn:apache)
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
- https://IPアドレス or ドメイン名

設定ファイル: /etc/httpd/conf.d/ドメイン名.conf
ドキュメントルート: /var/www/html

注意:
- HTTP/2を有効にするには、SSLの設定ファイルに「Protocols h2 http/1.1」を追記してください
- ドキュメントルートの所有者: unicorn
- ドキュメントルートのグループ: apache
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
