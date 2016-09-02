#!/bin/bash

echo 'Creating docker-compose config'

read -p 'Do you wish to install RabbitMQ (y/N): ' install_rabbitmq

webroot_path="./shared/webroot"
read -p 'Do you have existing copy of Magento 2 (y/N): ' yes_no
if [[ $yes_no = 'y' ]]
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
db_path="./shared/webroot"
read -p 'Do you have existing copy of the database files folder (y/N): ' yes_no
if [[ $yes_no = 'y' ]]
    then
        read -p 'Please provide full path to the database files folder: ' db_path
fi

cat > docker-compose.yml <<- EOM
##
# Services needed to run Magento2 application on Docker
#
# Docker Compose defines required services and attach them together through aliases
##
db:
  container_name: magento2-devbox-db
  restart: always
  image: mysql:5.6
  ports:
    - "1345:3306"
  environment:
    - MYSQL_ROOT_PASSWORD=root
    - MYSQL_DATABASE=magento2
  volumes:
    - $db_path:/var/lib/mysql
EOM

if [[ $install_rabbitmq = 'y' ]]
    then
        cat << EOM >> docker-compose.yml
rabbit:
  container_name: magento2-devbox-rabbit
  image: rabbitmq:3-management
  ports:
    - "8282:15672"
    - "5672:5672" 
EOM
fi

read -p 'Do you wish to install Redis (y/N): ' install_redis

if [[ $install_redis = 'y' ]]
    then
        cat << EOM >> docker-compose.yml
redis:
  container_name: magento2-devbox-redis
  image: redis:3.0.7
EOM
fi

cat << EOM >> docker-compose.yml
web:
  build: web
  container_name: magento2-devbox-web
  volumes:
    - $webroot_path:/var/www/magento2
    - $composer_path:/root/.composer
    - $ssh_path:/root/.ssh
    #    - ./shared/.magento-cloud:/root/.magento-cloud
  ports:
    - "1748:80"
  links:
    - db:db
EOM

if [[ $install_rabbitmq = 'y' ]]
    then
        cat << 'EOM' >> docker-compose.yml
    - rabbit:rabbit
EOM
fi

if [[ $install_redis = 'y' ]]
    then
        cat << 'EOM' >> docker-compose.yml
    - redis:redis
EOM
fi

cat << 'EOM' >> docker-compose.yml
  command: "apache2-foreground"
EOM

echo "Creating shared folders"

mkdir -p shared/.composer
mkdir -p shared/.ssh
mkdir -p shared/webroot
mkdir -p shared/db

echo 'Build docker images'

docker-compose up --build -d

docker exec -it --privileged magento2-devbox-web php /root/scripts/composerInstall.php
docker exec -it --privileged magento2-devbox-web php /root/scripts/magentoSetup.php --install-rabbitmq=$install_rabbitmq
docker exec -it --privileged magento2-devbox-web php /root/scripts/postInstall.php
