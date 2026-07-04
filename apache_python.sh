#!/bin/sh

#rootユーザーで実行 or sudo権限ユーザー

<<COMMENT
URL：https://buildree.com/

Pythonのインストールを行います

COMMENT

# 注意書きを表示して確認を取る
cat <<EOF
注意点：
  - このスクリプトは、AlmaLinux、Rocky Linux、RHEL、CentOS Stream、Oracle Linuxをインストールした直後のVPSやクラウドサーバーでの使用を想定しています。
  - 既存の環境で実行した場合、既存の設定やアプリケーションに影響を与える可能性があります。
  - 既存環境での実行は推奨されません。
  - rootユーザーで実行する場合は、コマンド実行に十分注意してください。
  - 実行前に必ずバックアップを取得してください。
  - unicornユーザーは自動生成されます。
  - Pythonは3.12を利用しています。

目的：
・Python3.12の実行環境のインストール
・pip環境の設定
・拡張モジュールコンパイル用の最小限の開発ツール
・デモ用ユーザー(unicorn)の作成

実行してもよろしいですか？ (y/n): 
EOF

# ユーザーからの入力を受け取る
read -r choice

# 入力に応じて処理を分岐
if [ "$choice" != "y" ]; then
  echo "インストールを中止しました。"
  exit 0
fi

echo "インストールを開始します..."
echo ""

# 初期設定で関数やハッシュ値をいれていく
start_message(){
echo ""
echo "======================開始======================"
echo ""
}

end_message(){
echo ""
echo "======================完了======================"
echo ""
}

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

  # 最小限の必要なパッケージのインストール
  start_message
  echo "必要な最小限の開発ツールをインストールします"
  dnf install -y gcc gcc-c++ make automake openssl openssl-devel
  end_message

# システムアップデート
start_message
echo "システムを最新版に更新します"
dnf -y update
  end_message

  start_message
          # Apacheのインストール
        start_message "Apacheのインストール"
        dnf install -y httpd httpd-devel mod_ssl
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
        #モジュールの読み込み
        sed -i -e "353i LoadModule wsgi_module modules/mod_wsgi-py312.cpython-312-x86_64-linux-gnu.so \n" /etc/httpd/conf/httpd.conf
        sed -i -e "354i WSGIScriptAlias / /var/www/html/mysite/wsgi.py \n" /etc/httpd/conf/httpd.conf
        sed -i -e "355i WSGIPythonPath /var/www/html/ \n" /etc/httpd/conf/httpd.conf
        sed -i -e "356i <Directory /var/www/html/mysite> \n" /etc/httpd/conf/httpd.conf
        sed -i -e "357i <Files wsgi.py> \n" /etc/httpd/conf/httpd.conf
        sed -i -e "358i Require all granted \n" /etc/httpd/conf/httpd.conf
        sed -i -e "359i </Files> \n" /etc/httpd/conf/httpd.conf
        sed -i -e "360i </Directory> \n" /etc/httpd/conf/httpd.conf

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
  end_message



  start_message
  echo "Python 3.12 をインストールします"
  dnf install -y python3.12 python3.12-pip python3.12-devel
  echo "環境変数を設定します"
  cat >/etc/profile.d/python.sh <<'EOF'
# Pythonとpipコマンドのパスを確実にシステムパスに含める
# これにより複数のPythonバージョンがインストールされている環境でも
# 期待通りのバージョンが使用されます
if ! echo "$PATH" | grep -q "/usr/bin"; then
    export PATH="/usr/bin:$PATH"
fi
EOF
  source /etc/profile.d/python.sh
  # シンボリックリンクの作成
  ln -sf /usr/bin/python3.12 /usr/bin/python
  ln -sf /usr/bin/pip3.12 /usr/bin/pip
  end_message

  start_message
  echo "pipをアップグレードします"
  pip install --upgrade pip
  end_message

  start_message
  echo "pipをアップグレードします"
  pip install mod-wsgi
  end_message

        #インストール場所を調べる
        start_message
        echo "インストール場所を調べます"
        pip show mod-wsgi
        ls -all /usr/local/lib64/python3.12/site-packages/mod_wsgi/server/
        end_message

        #ファイルのコピー
        start_message
        echo "ファイルをコピーします"
        cp  cp /usr/local/lib64/python3.12/site-packages/mod_wsgi/server/mod_wsgi-py312.cpython-312-x86_64-linux-gnu.so /etc/httpd/modules/
        echo "ファイルの確認"
        ls /etc/httpd/modules/
        end_message



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

  #サンプルファイル作成
  start_message
  echo "サンプルPythonファイルを作成します"
  cat > /home/unicorn/hello.py <<'EOF'
#coding:UTF-8

print ("こんにちは世界！")
EOF
  end_message

  #実行
  start_message
  echo "サンプルファイルを実行します"
  echo "python hello.py"
  su -l unicorn -c "python hello.py"
  end_message

        # apacheの起動
        echo "apacheを起動します"
        start_message
        systemctl start httpd.service

        echo "apacheのステータス確認"
        systemctl status httpd.service
        end_message

          #自動起動の設定
        start_message
        systemctl enable httpd
        systemctl list-unit-files --type=service | grep httpd
        end_message


        #firewallのポート許可
        echo "http(80番)とhttps(443番)の許可をしてます"
        start_message
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        echo ""
        echo "保存して有効化"
        echo ""
        firewall-cmd --reload

        echo ""
        echo "設定を表示"
        echo ""
        firewall-cmd --list-all
        end_message



  echo ""
  echo "-----------------"
  echo "インストール完了"
  echo "-----------------"
  echo "Python環境のインストールが完了しました。"
  echo "pipが利用可能なため、必要なパッケージは以下のように"
  echo "インストールできます："
  echo ""
  echo "$ pip install Django  # Djangoをインストールする例"
  echo "$ pip install bottle  # bottleをインストールする例"
  echo "$ pip install pymysql  # MySQLドライバをインストールする例"
  echo ""
  echo "C拡張モジュールをコンパイルするための最小限の開発ツールも"
  echo "インストール済みです。"
  
  #所有者変更
  start_message
  echo "ディレクトリ所有者を変更します"
  chown -R unicorn:nobody /home/unicorn/
  end_message
  
  echo "インストールが完了しました！以下のコマンドでunicornユーザーに切り替えることができます："
  echo "su -l unicorn"
else
  echo "エラー: このスクリプトはRHEL/CentOS/AlmaLinux/Rocky Linux/Oracle Linux 8、9または10専用です。"
  echo "検出されたOS: $DIST_NAME"
  echo "検出されたOSバージョン: $DIST_MAJOR_VERSION"
  exit 1
fi