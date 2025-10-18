## Setup
docker run -d --rm --name xirr_py -p 8000:80 -v /tmp:/tmp thimmaiah/xirr_py:v2.5
docker run -d --rm --name elasticsearch -p 9200:9200 -p 9300:9300 -e ES_JAVA_OPTS="-Xms512m -Xmx512m" -e "discovery.type=single-node" -e "xpack.security.enabled=false" elasticsearch:8.15.0
docker run mysql8
docker run redis:7

## Clone the repo
git clone git@github.com:ausangshukla/IRM.git

## Create the DB
rake db:create
mysql -uroot -proot -h127.0.0.1 -DIRM_development < tmp/staging.sql

## Get the config/credentials
Copy over the credentials files into config/credentials

## Run the app
rails s -p 3001
bundle exec prometheus_exporter -b 0.0.0.0
rails c

## Reset all emails/Wa on dev iusing the rails console
EntitySetting.disable_all(reset: true)
ElasticImporterJob.new.reset

## Visit the site
http://localhost:3001
Login using
fm1@ian.com / password