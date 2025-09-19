# Home Security Analytics Platform

**About This Project**  

This repository contains information and configuration for building your own home network Analytics platform.  
Analytics that can run 24/7 without requiring much disk space or processing power.  
Usually we only ad-Hoc / spot check logs or connections,  missing out on equipment that "calls home" once every 4/8/48 Hours.  
Gaining this information has proven valuable.  
  
I will share configuration on how to get insights into  
 - What your TV does on the internet when you use it and when you sleep.  
 - Where in the world does your Phillips Hue Bridge make clear text http requests.  
 - Sharing precise location data with your kids on the people they talk to using Discord.  

I will also share how i enrich this data with  
  
- Geo Location Information   
- Threat information (From virus total and other services)  
  
Giving you the abillity to discover if your internet connected washing machine is part of a DDOS network or a surveilance device  
  

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

Note down the password and try to query Elasticsearch using the password.

```
curl -u elastic:<YOUR_PW> "localhost:9200/_cluster/health"
```

Expect an output similar to this
```
{"cluster_name":"docker-cluster","status":"green","timed_out":false,"number_of_nodes":1,"number_of_data_nodes":1,"active_primary_shards":70,"active_shards":70,"relocating_shards":0,"initializing_shards":0,"unassigned_shards":11,"unassigned_primary_shards":0,"delayed_unassigned_shards":0,"number_of_pending_tasks":0,"number_of_in_flight_fetch":0,"task_max_waiting_in_queue_millis":0,"active_shards_percent_as_number":86.41975308641975}%
```  

