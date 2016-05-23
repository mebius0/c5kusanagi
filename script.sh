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

TERM=xterm

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

#---------START OF KUSANAGI---------#
yum -y --enablerepo=remi,remi-php56 update
yum -y --enablerepo=remi install expect || exit 1

expect -c "
spawn passwd kusanagi
expect \"New password:\"
send \"${KUSANAGI_PASSWORD}\n\"
expect \"Retype new password:\"
send \"${KUSANAGI_PASSWORD}\n\"
expect \"passwd: all authentication tokens updated successfully.\"
exit 0
"

kusanagi nginx
kusanagi php7

service mysql status >/dev/null 2>&1 || service mysql start
for i in {1..5}; do
sleep 1
service mysql status && break
[ "$i" -lt 5 ] || exit 1
done
chkconfig mysql on || exit 1

MYSQLROOTPASSWORD=`mkpasswd -l 32 -d 9 -c 9 -C 9 -s 0 -2`
/usr/bin/mysqladmin --defaults-file=/root/.my.cnf password "$MYSQLROOTPASSWORD" || exit 1

cat <<EOT > /root/.my.cnf
[mysqladmin]
host = localhost
user = root
password = $MYSQLROOTPASSWORD
[client]
host = localhost
user = root
password = $MYSQLROOTPASSWORD
EOT
chmod 600 /root/.my.cnf

kusanagi configure
#---------END OF KUSANAGI---------#

#---------START OF concrete5---------#
USERNAME="c5_`mkpasswd -l 10 -C 0 -s 0`"
PASSWORD=`mkpasswd -l 32 -d 9 -c 9 -C 9 -s 0 -2`
wget http://concrete5-japan.org/index.php/download_file/view/2080/45/ -O concrete5.zip
unzip concrete5.zip
mkdir /home/kusanagi/$USERNAME
mv concrete5.7.5.7 /home/kusanagi/$USERNAME/web

chmod 755 /home/kusanagi/$USERNAME/web/concrete/bin/concrete5
  
mysql --defaults-file=/root/.my.cnf <<-EOT
CREATE DATABASE IF NOT EXISTS $USERNAME;
GRANT ALL ON $USERNAME.* TO '$USERNAME'@'localhost' IDENTIFIED BY '$PASSWORD';
FLUSH PRIVILEGES;
EOT

cat <<EOT > /etc/nginx/conf.d/$USERNAME.conf
server {
	listen		80;
	server_name	$SITE_DOMAIN;
	access_log  	/home/kusanagi/$USERNAME/access.log main;
	error_log   	/home/kusanagi/$USERNAME/error.log warn;
	root		/home/kusanagi/$USERNAME/web;
	index		index.php index.html;
	charset 	UTF-8;
	location / {
 		if (-f \$request_filename) {
			expires 30d;
			break;
		}
		if (!-e \$request_filename) {
			rewrite ^(.+)$ /index.php/\$1 last;
		}
		error_page 404 @fallback;
	}
	location @fallback {
		return 301 /;
	}
	location ~ ^(.+\.php)(.*)$ {
		include			fastcgi_params;
		fastcgi_index		index.php;
		fastcgi_pass		127.0.0.1:9000;
		fastcgi_split_path_info	^(.+.php)(/.+)$;

		fastcgi_send_timeout	300;
		fastcgi_read_timeout	300;
		fastcgi_connect_timeout	300;	

		fastcgi_buffers		256 128k;
		fastcgi_buffer_size	128k;
		fastcgi_intercept_errors on;

		fastcgi_param	SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
		fastcgi_param	PATH_INFO \$fastcgi_path_info;
	}
}
EOT

systemctl restart nginx.service || exit 1

cd /home/kusanagi/$USERNAME/web/concrete/bin
./concrete5 c5:install --db-server=127.0.0.1 --db-username=$USERNAME --db-password=$PASSWORD --db-database=$USERNAME --admin-password=$ADMIN_PASSWORD --admin-email=$ADMIN_EMAIL --starting-point=elemental_full --site=$SITE_NAME

chmod -R 777 /home/kusanagi/$USERNAME/web/packages
chmod -R 777 /home/kusanagi/$USERNAME/web/application/config
chmod -R 777 /home/kusanagi/$USERNAME/web/application/files
chown -R kusanagi:kusanagi /home/kusanagi/$USERNAME || exit 1
