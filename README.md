# Home Security Analytics Platform

**About This Project**  

This repository contains information and configuration for building your own home network Analytics platform.  
Analytics that can run 24/7 without requiring much disk space or processing power.  
Usually we only ad-Hoc / spot check logs or connections,  
missing out on equipment that "calls home" once every 4/8/48 Hours.  
Gaining this information has proven valuable insights on how devices share our privacy without you knowing.   
  
I wrote about this topic on my website <https://www.thorsrud.io/breaking-down-information-silos-building-a-home-network-intelligence-platform/>

  
I have worked with IT Security as a professional for 26 years, working for both private and public customers building global services for several fortune 500 companies.  
What drives me today and has always driven me is curiosity: What if, How come.. 
  
I will share configuration on how to get insights into  
 - What your TV does on the internet when you use it and when you sleep.  
 - Where in the world does your Phillips Hue Bridge make clear text http requests.  
 - Sharing precise location data with your kids on the people they talk to using Discord.  

I will also share how i enrich this data with  
  
- Geo Location Information   
- Threat information (From virus total and other services)  
  
Giving you the abillity to discover if your internet connected washing machine is part of a DDOS network or a surveilance device  (Such devices are perfect sleepers for professionals)  
  

**Requirements**    
This project runs on containers.    
You will have to install docker or a compatible alternative on your machine in order to replicate this setup.  
My busy environment typically generate 40 - 80 Mbyte of logdata pr day for 100% visibillity.  
My configuration assumes your internet gateway is capable of connection logging to syslog.  (Most routers do support this)  
  
I run Asuswrt-Merlin on my Internet gateway.      


**Basesetup:** 
Create a folder for this project or git clone this repo. (I will refer to this folder as $ELK$/)
For the setup to survive upgrades / deletion of the containers i mount different subfolders in $ELK$ directory to store config files and the Indices. 


Start by creating a network for the analysis platform    
```
docker network create elastic  
```

## 1: Folders in this repo  
  
**logstash/**  
- Contains configuration files for logstash.  
The logstash.conf file is the heart of this setup. It recieves the connection logs from my home router and normalize the log entries into searchable database fields.  
The logstash collector is also responsible for enriching the data with Geo IP Information 
  
  
**kibana/**  
- Contains configuration files for Kibana. 

**elasticsearch-data/*  
- Contains the Indices and Indexes. 



## 2: Prepare Elasticsearch  
  
Start a terminal window and go to the $ELK$/ folder.  
We will start elasticsearch just to be able to set a password on the systemuser elastic.  

```
docker run -d \
  --name elasticsearch \
  --net elastic \
  -p 9200:9200 -p 9300:9300 \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=true" \
  -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
  docker.elastic.co/elasticsearch/elasticsearch:9.1.3
```
  
Docker will download elasticsearch and start up an instance of Elasticsearch in a container named elasticsearch running on network elastic  
Give it some time to boot up before we reset the admin password.  
  
Reset Password using
```
docker run -d \
-docker exec -it elasticsearch bin/elasticsearch-reset-password -u elastic --interactive 
```
 
Create a backup folder  
mkdir $ELKH/elasticbackup/  
  
Restart Elasticsearch with password  
Run Elasticsearch with 1GB Ram ( "ES_JAVA_OPTS=-Xms1g -Xmx1g" )  

```
docker stop elasticsearch
docker rm elasticsearch

docker run -d \
  --name elasticsearch \
  --net elastic \
  -p 9200:9200 -p 9300:9300 \
  -v "<Insert your $ELK$ Path>/elasticsearch-data:/usr/share/elasticsearch/data" \
  -v "<Insert your $ELK$ Path>/elasticbackup:/usr/share/elasticsearch/backup" \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=true" \
  -e "ELASTIC_PASSWORD=<YOUR_PW>" \
  -e "path.repo=/usr/share/elasticsearch/backup" \
  -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
  docker.elastic.co/elasticsearch/elasticsearch:9.1.3
  
### Verify Cluster Health with auth
curl -u elastic:<YOUR_PW> "localhost:9200/_cluster/health"  
 ```


## 3: Configure Kibana

In order to configure Kibana to talk with Elasticsearch we have to start with authentication.  
In the previous section we configured and started elasticsearch. Elasticsearch has a builtin user for Kibana.

Fetch a token / key for the kibana user

```
curl -X POST "localhost:9200/_security/service/elastic/kibana/credential/token/my-kibana-token" \
  -H "Content-Type: application/json" \
  -u elastic:<YOUR_PW>
```
  
You will get an output similar to this:  
  {"created":true,"token":{"name":"my-kibana-token","value":"<YOURTOKEN>"}}% 
  
 
Edit the kibana.yml Configuration file located in the $ELK$/kibana/ folder.  
Modify the parameter elasticsearch.serviceAccountToken to include the token returned above.  

Start Kibana

```
docker run -d \
  --name kibana \
  --net elastic \
  -p 5601:5601 \
  -v $ELK$/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  docker.elastic.co/kibana/kibana:9.1.3
```

Verify Kibana in a browser connecting to <http://localhost:5601/> and connect with user elastic and the password you set for elasticsearch earlier.


