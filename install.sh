#!/bin/bash

echo 'Creating docker-compose config'

read -p 'Do you wish to install RabbitMQ (y/N): ' install_rabbitmq

webroot_path="./shared/webroot"
read -p 'Do you have existing copy of Magento 2 (y/N): ' use_existing_sources
if [[ $use_existing_sources = 'y' ]]
    then
        read -p 'Please provide full path to the magento2 folder: ' webroot_path
fi
composer_path="./shared/.composer"
read -p 'Do you have existing copy of .composer folder (y/N): ' yes_no
if [[ $yes_no = 'y' ]]
    then
        read -p 'Please provide full path to the .composer folder: ' composer_path
fi
ssh_path="./shared/.ssh"
read -p 'Do you have existing copy of .ssh folder (y/N): ' yes_no
if [[ $yes_no = 'y' ]]
    then
        read -p 'Please provide full path to the .ssh folder: ' ssh_path
fi
db_path="./shared/db"
read -p 'Do you have existing copy of the database files folder (y/N): ' yes_no
if [[ $yes_no = 'y' ]]
    then
        read -p 'Please provide full path to the database files folder: ' db_path
fi

db_host=db
db_port=3306
db_password=root
db_user=root
db_name=magento2
cat > docker-compose.yml <<- EOM
##
# Services needed to run Magento2 application on Docker
#
# Docker Compose defines required services and attach them together through aliases
##
version: '2'
services:
  $db_host:
    container_name: magento2-devbox-db
    restart: always
    image: mysql:5.6
    ports:
      - "1345:$db_port"
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=$db_name
    volumes:
      - $db_path:/var/lib/mysql
EOM

rabbit_host='rabbit'
rabbit_port=5672
if [[ $install_rabbitmq = 'y' ]]
    then
        cat << EOM >> docker-compose.yml
  $rabbit_host:
    container_name: magento2-devbox-rabbit
    image: rabbitmq:3-management
    ports:
      - "8282:15672"
      - "$rabbit_port:$rabbit_port"
EOM
fi

read -p 'Do you wish to setup Redis as session storage (y/N): ' redis_session
read -p 'Do you wish to setup Redis (r) or Varnish (v) as page cache mechanism (any key for default file system storage) (r/v): ' cache_adapter

if [[ $cache_adapter = 'v' ]]
    then install_varnish='y'
fi

redis_cache=0
if [[ $cache_adapter = 'r' ]]
    then redis_cache=1
fi

if [[ $cache_adapter = 'r' ]] || [[ $redis_session = 'y' ]]
    then install_redis='y'
fi

redis_host='redis'
if [[ $install_redis = 'y' ]]
    then
        cat << EOM >> docker-compose.yml
  $redis_host:
    container_name: magento2-devbox-redis
    image: redis:3.0.7
EOM
fi

web_port=1748
varnish_host_container=magento2-devbox-varnish
if [[ $install_varnish = 'y' ]]
    then
        cat << EOM >> docker-compose.yml
  varnish:
    build: varnish
    container_name: $varnish_host_container
    links:
      - web:web
    ports:
      - "1748:6081"
EOM
web_port=1749
fi

magento_path='/var/www/magento2'
main_host=web
main_host_port=80
main_host_container=magento2-devbox-web
cat << EOM >> docker-compose.yml
  $main_host:
    image: magento/magento2devbox_web:latest
    container_name: $main_host_container
    volumes:
      - $webroot_path:$magento_path
      - $composer_path:/home/magento2/.composer
      - $ssh_path:/home/magento2/.ssh
      #    - ./shared/.magento-cloud:/root/.magento-cloud
    ports:
      - "$web_port:$main_host_port"
      - "2222:22"
EOM

echo "Creating shared folders"

mkdir -p shared/.composer
mkdir -p shared/.ssh
mkdir -p shared/webroot
mkdir -p shared/db

echo 'Build docker images'

docker-compose up --build -d

docker exec -it --privileged -u magento2 magento2-devbox-web /bin/sh -c 'cd /home/magento2/scripts && composer install'
docker exec -it --privileged -u magento2 magento2-devbox-web /bin/sh -c 'cd /home/magento2/scripts && composer update'

docker exec -it --privileged -u magento2 magento2-devbox-web php -f /home/magento2/scripts/devbox magento:download --use-existing-sources=$use_existing_sources
docker exec -it --privileged -u magento2 magento2-devbox-web php -f /home/magento2/scripts/devbox magento:setup --use-existing-sources=$use_existing_sources --rabbitmq-install=$install_rabbitmq --rabbitmq-host=$rabit_host --rabbitmq-port=$rabbit_port

if [[ $install_redis ]]
    then docker exec -it --privileged -u magento2 magento2-devbox-web php -f /home/magento2/scripts/devbox magento:setup:redis --as-cache=$redis_cache --as-session=$redis_session --host=$redis_host --magento-path=$magento_path
fi

if [[ $install_varnish ]]
    then
        varnish_file=/home/magento2/scripts/default.vcl
        docker exec -it --privileged -u magento2 magento2-devbox-web \
        php -f /home/magento2/scripts/devbox magento:setup:varnish  \
            --db-host=$db_host --db-port=$db_port --db-user=$db_user --db-name=$db_name --db-password=$db_password \
            --backend-host=$main_host --backend-port=$main_host_port --out-file-path=/home/magento2/scripts/default.vcl

        docker cp "$main_host_container:/$varnish_file" ./web/scripts/command/default.vcl
        docker cp ./web/scripts/command/default.vcl $varnish_host_container:/etc/varnish/default.vcl
        rm ./web/scripts/command/default.vcl

        docker-compose restart varnish
fi

docker exec -it --privileged -u magento2 magento2-devbox-web php -f /home/magento2/scripts/devbox magento:prepare
