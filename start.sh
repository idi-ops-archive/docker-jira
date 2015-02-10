#!/bin/bash
set -o errexit

CONTEXT_PATH=""

[ -z $DATABASE_URL ] && echo "No DATABASE_URL provided" && exit 1 

urldecode() {
    local data=${1//+/ }
    printf '%b' "${data//%/\x}"
}

parse_url() {
  local prefix=DATABASE
  [ -n "$2" ] && prefix=$2
  # extract the protocol
  local proto="`echo $1 | grep '://' | sed -e's,^\(.*://\).*,\1,g'`"
  local scheme="`echo $proto | sed -e 's,^\(.*\)://,\1,g'`"
  # remove the protocol
  local url=`echo $1 | sed -e s,$proto,,g`

  # extract the user and password (if any)
  local userpass="`echo $url | grep @ | cut -d@ -f1`"
  local pass=`echo $userpass | grep : | cut -d: -f2`
  if [ -n "$pass" ]; then
    local user=`echo $userpass | grep : | cut -d: -f1`
  else
    local user=$userpass
  fi

  # extract the host -- updated
  local hostport=`echo $url | sed -e s,$userpass@,,g | cut -d/ -f1`
  local port=`echo $hostport | grep : | cut -d: -f2`
  if [ -n "$port" ]; then
    local host=`echo $hostport | grep : | cut -d: -f1`
  else
    local host=$hostport
  fi

  # extract the path (if any)
  local full_path="`echo $url | grep / | cut -d/ -f2-`"
  local path="`echo $full_path | cut -d? -f1`"
  local query="`echo $full_path | grep ? | cut -d? -f2`"
  local -i rc=0
  
  [ -n "$proto" ] && eval "export ${prefix}_SCHEME=\"$scheme\"" || rc=$?
  [ -n "$user" ] && eval "export ${prefix}_USER=\"`urldecode $user`\"" || rc=$?
  [ -n "$pass" ] && eval "export ${prefix}_PASSWORD=\"`urldecode $pass`\"" || rc=$?
  [ -n "$host" ] && eval "export ${prefix}_HOST=\"`urldecode $host`\"" || rc=$?
  [ -n "$port" ] && eval "export ${prefix}_PORT=\"`urldecode $port`\"" || rc=$?
  [ -n "$path" ] && eval "export ${prefix}_NAME=\"`urldecode $path`\"" || rc=$?
  [ -n "$query" ] && eval "export ${prefix}_QUERY=\"$query\"" || rc=$?
}

download_mysql_driver() {
  local driver="mysql-connector-java-5.1.34"
  if [ ! -f "$1/$driver-bin.jar" ]; then
    echo "Downloading MySQL JDBC Driver..."
    curl -L http://dev.mysql.com/get/Downloads/Connector-J/$driver.tar.gz | tar zxv -C /tmp
    cp /tmp/$driver/$driver-bin.jar $1/$driver-bin.jar
  fi
}

read_var() {
  eval "echo \$$1_$2"
}

extract_database_url() {
  local url="$1"
  local prefix="$2"
  local mysql_install="$3"

  eval "unset ${prefix}_PORT"
  parse_url "$url" $prefix
  case "$(read_var $prefix SCHEME)" in
    postgres|postgresql)
      if [ -z "$(read_var $prefix PORT)" ]; then
        eval "${prefix}_PORT=5432"
      fi
      local host_port_name="$(read_var $prefix HOST):$(read_var $prefix PORT)/$(read_var $prefix NAME)"
      local jdbc_driver="org.postgresql.Driver"
      local jdbc_url="jdbc:postgresql://$host_port_name?ssl=true"
      local hibernate_dialect="org.hibernate.dialect.PostgreSQLDialect"
      local database_type="postgres72"
      ;;
    mysql|mysql2)
      download_mysql_driver "$mysql_install"
      if [ -z "$(read_var $prefix PORT)" ]; then
        eval "${prefix}_PORT=3306"
      fi
      local host_port_name="$(read_var $prefix HOST):$(read_var $prefix PORT)/$(read_var $prefix NAME)"
      local jdbc_driver="com.mysql.jdbc.Driver"
      local jdbc_url="jdbc:mysql://$host_port_name?autoReconnect=true&characterEncoding=utf8&useUnicode=true&sessionVariables=storage_engine%3DInnoDB"
      local hibernate_dialect="org.hibernate.dialect.MySQLDialect"
      local database_type="mysql"
      ;;
    *)
      echo "Unsupported database url scheme: $(read_var $prefix SCHEME)"
      exit 1
      ;;
  esac

  eval "${prefix}_JDBC_DRIVER=\"$jdbc_driver\""
  eval "${prefix}_JDBC_URL=\"$jdbc_url\""
  eval "${prefix}_DIALECT=\"$hibernate_dialect\""
  eval "${prefix}_TYPE=\"$database_type\""
}

chown jira:jira /opt/atlassian-home -R
rm -f /opt/atlassian-home/.jira-home.lock

if [ "$CONTEXT_PATH" == "ROOT" -o -z "$CONTEXT_PATH" ]; then
  CONTEXT_PATH=
else
  CONTEXT_PATH="/$CONTEXT_PATH"
fi

xmlstarlet ed -u '//Context/@path' -v "$CONTEXT_PATH" /opt/jira/conf/server-backup.xml > /opt/jira/conf/server.xml

if [ -n "$DATABASE_URL" ]; then
  extract_database_url "$DATABASE_URL" DB /opt/jira/lib
  DB_JDBC_URL="$(xmlstarlet esc "$DB_JDBC_URL")"
  SCHEMA=''
  if [ "$DB_TYPE" != "mysql" ]; then
    SCHEMA='<schema-name>public</schema-name>'
  fi

  cat <<END > /opt/atlassian-home/dbconfig.xml
<?xml version="1.0" encoding="UTF-8"?>
<jira-database-config>
  <name>defaultDS</name>
  <delegator-name>default</delegator-name>
  <database-type>$DB_TYPE</database-type>
  $SCHEMA
  <jdbc-datasource>
    <url>$DB_JDBC_URL</url>
    <driver-class>$DB_JDBC_DRIVER</driver-class>
    <username>$DB_USER</username>
    <password>$DB_PASSWORD</password>
    <pool-min-size>20</pool-min-size>
    <pool-max-size>20</pool-max-size>
    <pool-max-wait>30000</pool-max-wait>
    <pool-max-idle>20</pool-max-idle>
    <pool-remove-abandoned>true</pool-remove-abandoned>
    <pool-remove-abandoned-timeout>300</pool-remove-abandoned-timeout>
  </jdbc-datasource>
</jira-database-config>
END
fi

/usr/bin/keytool -import -alias database -file /opt/atlassian-home/database.cert -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit -noprompt

cat >/etc/supervisord.d/jira.ini<<EOF
[program:jira]
command=/opt/jira/bin/start-jira.sh -fg
user=jira
autorestart=true
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

supervisord -c /etc/supervisord.conf
