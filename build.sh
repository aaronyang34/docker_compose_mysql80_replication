#!/bin/bash

docker compose down -v
rm -rf ./mysql-master/*
rm -rf ./mysql-slave/*
docker compose build
docker compose up -d

sleep 4

until docker exec mysql-master sh -c 'export MYSQL_PWD=123456; mysql -u root -e ";"'
do
    echo "Waiting for mysql-master database connection..."
    sleep 4
done

priv_stmt='CREATE USER "replica_user"@"%" IDENTIFIED BY "replica_pwd"; GRANT REPLICATION SLAVE ON *.* TO "replica_user"@"%"; FLUSH PRIVILEGES;'
# priv_stmt='CREATE USER "replica_user"@"%" IDENTIFIED WITH 'mysql_native_password' BY "replica_pwd"; GRANT REPLICATION SLAVE ON *.* TO "replica_user"@"%"; FLUSH PRIVILEGES;'
docker exec mysql-master sh -c "export MYSQL_PWD=123456; mysql -u root -e '$priv_stmt'"

until docker compose exec mysql-slave sh -c 'export MYSQL_PWD=123456; mysql -u root -e ";"'
do
    echo "Waiting for mysql-slave database connection..."
    sleep 4
done

# 解決Mysql 8之後 caching_sha2_password 連線沒有公鑰會導致replication設定出錯的問題. (失敗了,直接用可以,包在bash內就不型)
docker exec mysql-slave sh -c 'export MYSQL_PWD=replica_pwd; mysql -hmysql-master -ureplica_user --get-server-public-key -e ";"'

MS_STATUS=`docker exec mysql-master sh -c 'export MYSQL_PWD=123456; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`


start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-master',MASTER_USER='replica_user',MASTER_PASSWORD='replica_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=123456; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
echo $start_slave_cmd
docker exec mysql-slave sh -c "$start_slave_cmd"

docker exec mysql-slave sh -c "export MYSQL_PWD=123456; mysql -u root -e 'SHOW SLAVE STATUS \G'"
