#!/bin/bash

# #######################################################################
# Instalador rapido de ODBC para Asterisk en Debian 9 (con MariaDB)
#
# Fecha: 2018-12-21
# Autor: Elio Rojano (erojano en sinologic.net)
# Descripcion: 
#  Siempre que instalamos un Asterisk, vemos necesario instalar el CDR y para
#  y para ello, hay que instalar y configurar ODBC, lo cual no es rapido ni
#  son pocos los pasos a realizar, por lo que aqui hay un script que instala
#  todo el ODBC necesario para configurar el CDR de Asterisk rapidamente.
#
# Si encuentra algo que mejorar, por favor de admiten sugerencias. ;)
#
# Partimos de que tenemos un Asterisk instalado como se indica en este enlace:
# https://www.sinologic.net/2014-05/como-instalar-asterisk-como-un-profesional.html
# #######################################################################

clear
echo "#############################################################################


apt-get install build-essential unixodbc curl

# Instalamos el driver MySQL ODBC de su pagina oficial ya que Debian ya no lo trae
cd /tmp
wget -cq https://dev.mysql.com/get/Downloads/Connector-ODBC/5.3/mysql-connector-odbc-5.3.9-linux-debian9-x86-64bit.tar.gz -O /tmp/debian-mysql-odbc.tar.gz
tar xfz /tmp/debian-mysql-odbc.tar.gz
mv mysql-connector-odbc-5.3.9-linux-debian9-x86-64bit/lib/libmy* /usr/lib/odbc/

# Creamos el usuario y la base de datos para Asterisk

read -p "Escribe el usuario MySQL que usara Asterisk: " MYSQLASTERISKUSER
read -s -p "Escribe la password de root de MySQL: " MYSQLROOTPASS

# Creamos los archivos
mv /etc/odbcinst.ini /etc/odbcinst.ini.bak 2>/dev/null
cat << EOF >/etc/odbcinst.ini
[MySQL]
Description     = ODBC for MySQL
Driver          = /usr/lib/odbc/libmyodbc5w.so
Setup           = /usr/lib/odbc/libmyodbc5w.so
FileUsage       = 1
Pooling         = Yes
CPTimeout       = 120
EOF

mv /etc/odbc.ini /etc/odbc.ini.bak 2>/dev/null
cat << EOF >/etc/odbc.ini
[asterisk-connector]
Description = MySQL connection to 'asterisk' database
Driver = MySQL
Database = $MYSQLASTERISKUSER
Server = localhost
Port = 3306
Socket = /var/run/mysqld/mysqld.sock
EOF

## Generamos una password aleatoria de 20 caracteres
## Mas info: https://www.sinologic.net/proyectos/genpass/
##
PASSWORD=`curl "https://www.sinologic.net/proyectos/genpass/?sent=1&base=Sino&long=20&alpha=on&numbers=on&symbol=on&ajax=1"`

echo "CREATE USER '$MYSQLASTERISKUSER'@'%' IDENTIFIED BY '$PASSWORD'; CREATE DATABASE $MYSQLASTERISKUSER; GRANT ALL PRIVILEGES ON $MYSQLASTERISKUSER.* TO '$MYSQLASTERISKUSER'@'%'; FLUSH PRIVILEGES; exit" |mysql -uroot -p$MYSQLROOTPASS

echo "Apunta estos datos: "
echo "#################################################################"
echo "##   MySQL user: $MYSQLASTERISKUSER"
echo "##   MySQL pass: $PASSWORD"
echo "##   Base de datos de Asterisk: $MYSQLASTERISKUSER"
echo "#################################################################"

mv /etc/asterisk/res_odbc.conf /etc/asterisk/res_odbc.conf.old 2>/dev/null
cat << EOF >/etc/asterisk/res_odbc.conf
[asterisk]
enabled => yes
dsn => asterisk-connector
username => $MYSQLASTERISKUSER
password => $PASSWORD
pre-connect => yes
EOF

mv /etc/asterisk/cdr_adaptative_odbc.conf /etc/asterisk/cdr_adaptative_odbc.conf.old 2>/dev/null
cat << EOF >/etc/asterisk/cdr_adaptative_odbc.conf
[mysql]
connection=asterisk
table=cdr
EOF

## Creamos el archivo cdr.sql con todos los campos importantes (y los indices)
cat << EOF >/tmp/cdr.sql
CREATE TABLE cdr (
   id INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
   calldate DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
   clid VARCHAR(80) NOT NULL DEFAULT '',
   src VARCHAR(80) NOT NULL DEFAULT '',
   dst VARCHAR(80) NOT NULL DEFAULT '',
   dcontext VARCHAR(80) NOT NULL DEFAULT '',
   lastapp VARCHAR(200) NOT NULL DEFAULT '',
   lastdata VARCHAR(200) NOT NULL DEFAULT '',
   duration FLOAT UNSIGNED NULL DEFAULT NULL,
   billsec FLOAT UNSIGNED NULL DEFAULT NULL,
   disposition ENUM('ANSWERED','BUSY','FAILED','NO ANSWER','CONGESTION') NULL DEFAULT NULL,
   channel VARCHAR(50) NULL DEFAULT NULL,
   dstchannel VARCHAR(50) NULL DEFAULT NULL,
   amaflags VARCHAR(50) NULL DEFAULT NULL,
   accountcode VARCHAR(20) NULL DEFAULT NULL,
   uniqueid VARCHAR(32) NOT NULL DEFAULT '',
   peeraccount varchar(20) NOT NULL default '',
   linkedid varchar(32) NOT NULL default '',
   sequence int(11) NOT NULL default '0',
   userfield FLOAT UNSIGNED NULL DEFAULT NULL,
   answer DATETIME NOT NULL,
   end DATETIME NOT NULL,
   PRIMARY KEY (id),
   INDEX calldate (calldate),
   INDEX dst (dst),
   INDEX src (src),
   INDEX dcontext (dcontext),
   INDEX clid (clid)
)
COLLATE='utf8_bin'
ENGINE=InnoDB;
EOF

mysql -u$MYSQLASTERISKUSER -p$PASSWORD $MYSQLASTERISKUSER </tmp/cdr.sql
