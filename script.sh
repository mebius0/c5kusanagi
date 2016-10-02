#!/bin/bash

# @sacloud-once

# @sacloud-desc concrete5をインストールします。
# @sacloud-desc サーバ作成後、ドメインの設定を行いアクセスしてください
# @sacloud-desc http://サイトのドメイン/
# @sacloud-desc （このスクリプトは、KUSANAGIでのみ動作します）

# @sacloud-password required shellarg maxlen=100 kusanagi_password "kusanagiのパスワード"
# @sacloud-text required shellarg maxlen=100 site_domain "サイトのドメイン"
# @sacloud-text required shellarg maxlen=100 site_name "サイトの名前"
# @sacloud-password required shellarg maxlen=100 admin_password "adminのパスワード"
# @sacloud-text required shellarg maxlen=100 admin_email "adminのメールアドレス"

KUSANAGI_PASSWORD=@@@kusanagi_password@@@

SITE_DOMAIN=@@@site_domain@@@
SITE_NAME=@@@site_name@@@
ADMIN_PASSWORD=@@@admin_password@@@
ADMIN_EMAIL=@@@admin_email@@@

#---------START OF firewall---------#
systemctl start firewalld.service
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --zone=public --add-service=https --permanent
systemctl restart firewalld.service
#---------END OF firewall---------#

#---------START OF BASIC SETUP---------#
yum -y --enablerepo=remi,remi-php56 update
yum -y --enablerepo=remi install expect || exit 1

service mysql status >/dev/null 2>&1 || service mysql start
for i in {1..5}; do
sleep 1
service mysql status && break
[ "$i" -lt 5 ] || exit 1
done
chkconfig mysql on || exit 1

MYSQLROOTPASSWORD=`mkpasswd -l 32 -d 9 -c 9 -C 9 -s 0 -2`

kusanagi init --tz Asia/Tokyo --lang ja --keyboard ja --passwd $KUSANAGI_PASSWORD --nophrase --dbrootpass $MYSQLROOTPASSWORD --nginx --php7
#---------END OF BASIC SETUP---------#

#---------START OF concrete5---------#
USERNAME="c5_`mkpasswd -l 10 -C 0 -s 0`"
PASSWORD=`mkpasswd -l 32 -d 9 -c 9 -C 9 -s 0 -2`

kusanagi provision --concrete5 --fqdn $SITE_DOMAIN --noemail --dbname $USERNAME --dbuser $USERNAME --dbpass $PASSWORD $USERNAME

cd /home/kusanagi/$USERNAME/DocumentRoot/concrete/bin
chmod +x concrete5
./concrete5 c5:install --db-server=127.0.0.1 --db-username=$USERNAME --db-password=$PASSWORD --db-database=$USERNAME --admin-password=$ADMIN_PASSWORD --admin-email=$ADMIN_EMAIL --starting-point=elemental_full --site="$SITE_NAME"

chmod -R 777 /home/kusanagi/$USERNAME/DocumentRoot/application/files
chown -R kusanagi:kusanagi /home/kusanagi/$USERNAME || exit 1
