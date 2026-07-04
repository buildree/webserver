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
Buildree Apache & React インストールスクリプト
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
  - Node.js 20のインストール
  - Reactのインストールとビルド設定
  - unicornユーザーの自動作成
  - SELinux対応の自動設定

ドキュメントルート: /var/www/html
EOF

read -p "インストールを続行しますか？ (y/n): " choice
[ "$choice" != "y" ] && { echo "インストールを中止しました。"; exit 0; }

# プロジェクト名の設定
read -p "Reactプロジェクト名を入力してください (デフォルト: buildree-app): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-buildree-app}
echo "プロジェクト名: $PROJECT_NAME"

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

        # システムアップデート
        start_message "システムアップデート"
        echo "システムを最新版に更新します"
        dnf -y update
        end_message "システムアップデート"

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

    # Node.jsのインストール
    # EL10のAppStreamにはnodejs:20ストリームが無いため、EL10のみnodejs:22を使用
    if [ "$DIST_MAJOR_VERSION" -eq 10 ]; then
        NODEJS_STREAM="22"
    else
        NODEJS_STREAM="20"
    fi
    start_message "Node.jsのインストール"
    echo "Node.js ${NODEJS_STREAM}をインストールしています..."
    # まず既存のNodeモジュールをリセット
    dnf module reset -y nodejs
    # Node.jsをインストール
    dnf module install -y nodejs:${NODEJS_STREAM}
    echo "インストールされたNode.jsのバージョン:"
    node -v
    echo "インストールされたnpmのバージョン:"
    npm -v
    echo "Node.jsのインストールが完了しました"
    end_message "Node.jsのインストール"

    # Apacheの設定変更
    start_message "Apacheの設定変更"
    echo "Apacheの設定を変更します..."
    
    # htaccessの有効化
    echo "htaccessを有効化しています..."
    sed -i -e "151d" /etc/httpd/conf/httpd.conf
    sed -i -e "151i AllowOverride All" /etc/httpd/conf/httpd.conf
    
    # バージョン非表示
    echo "バージョン情報を非表示にしています..."
    sed -i -e "350i #バージョン非表示" /etc/httpd/conf/httpd.conf
    sed -i -e "351i ServerTokens ProductOnly" /etc/httpd/conf/httpd.conf
    sed -i -e "352i ServerSignature off \n" /etc/httpd/conf/httpd.conf
    
    echo "Apacheの設定変更が完了しました"
    end_message "Apacheの設定変更"

        # ユーザーを作成
        start_message "unicornユーザーの作成"
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
        end_message "unicornユーザーの作成"

# Reactアプリケーションのインストール
start_message "Reactアプリケーションのインストール"
echo "既存のディレクトリがあれば削除します..."
rm -rf /var/www/html/*

# プロジェクトディレクトリを/var/www/直下に作成
echo "プロジェクトディレクトリを/var/www/直下に作成しています..."
mkdir -p /var/www/$PROJECT_NAME
chown -R unicorn:apache /var/www/$PROJECT_NAME

# unicornユーザーとしてReactアプリを作成（自動的にyesで応答）
echo "Reactアプリケーションを作成しています..."
su - unicorn -c "cd /var/www/$PROJECT_NAME && yes | npx create-react-app ."

# package.jsonにビルド設定を追加
echo "ビルド出力先を設定しています..."
su - unicorn -c "sed -i 's/\"build\": \"react-scripts build\"/\"build\": \"react-scripts build\"/' /var/www/$PROJECT_NAME/package.json"

# サンプルアプリをビルド
echo "Reactアプリをビルドしています..."
su - unicorn -c "cd /var/www/$PROJECT_NAME && npm run build"

# ビルド結果を/var/www/htmlに移動
echo "ビルド結果を/var/www/htmlに移動しています..."
cp -r /var/www/$PROJECT_NAME/build/* /var/www/html/
chown -R unicorn:apache /var/www/html

    echo "Apache設定の更新が完了しました"
    end_message "Apache設定の更新"

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
        
        # Apache-Nodeプロキシ連携の許可
        echo "ApacheがNode.jsと連携できるように設定しています..."
        setsebool -P httpd_can_network_connect 1
        
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

Apache & React インストール完了！

アクセス方法:
- http://IPアドレス or ドメイン名
- https://IPアドレス or ドメイン名（SSL設定後）

設定ファイル: 
- Apacheメイン設定: /etc/httpd/conf/httpd.conf
- React用設定: /etc/httpd/conf.d/react-app.conf

ドキュメントルート: /var/www/html
ビルド済みアプリケーション: /var/www/html/build

Reactアプリケーション管理:
- アプリのソースコード: /var/www/html/src
- ビルドコマンド: cd /var/www/html && npm run build
- ビルドスクリプト: /var/www/html/build.sh

SELinux設定:
- SELinuxがEnforcing状態の場合のみ、必要なポリシーを適用済み
- ドキュメントルート(/var/www/html)には通常のWebコンテンツ用ポリシーを適用
- Apache-Node.js間の接続を許可済み

学習・テスト環境としての利用:
- 本スクリプトで作成した環境は学習・テスト用に最適化されています
- 本番環境では適切なセキュリティ対策を追加で実施してください

注意事項:
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