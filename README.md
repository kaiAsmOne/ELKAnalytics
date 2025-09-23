# Home Security Analytics Platform

## Table of Contents

- [About This Project](#about-this-project)
- [Requirements](#requirements)
- [Quick Setup (TL/DR)](#tldr)
- [Base Setup](#basesetup)
- [1. Folders in this repo](#1-folders-in-this-repo)
- [2. Prepare Elasticsearch](#2-prepare-elasticsearch)
- [3. Configure Kibana](#3-configure-kibana)
- [4. Configure Logstash](#4-configure-logstash)
- [5. Making this work for your environment](#5-making-this-work-for-your-environment)
- [6. I am not getting logdata](#6-i-am-not-getting-logdata)

---

**About This Project**

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


**TL/DR:**  
If you know docker and containers reading walls of text is frustrating  
you can git clone this repo & sudo chmod +x setup.sh  
Then execute the script to have it all setup for you in one go  
(It will delete any existing containers called elasticsearch , kibana and logstash. I assume you run on mac using #!/bin/zsh)  
When the setup has completed jump to Section 5 in this file
  

**Basesetup:** 
Create a folder for this project or git clone this repo. (I will refer to this folder as %ELK%/)
For the setup to survive upgrades / deletion of the containers i mount different subfolders in %ELK% directory to store config files and the Indices. 


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

**elasticsearch-data/**
- Contains the Indices and Indexes. 



## 2: Prepare Elasticsearch  
  
Start a terminal window and go to the %ELK%/ folder.  
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
docker exec -ti elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic --interactive
```
 
Create a backup folder  
mkdir %ELK%/elasticbackup/  
  
Restart Elasticsearch with password  
Run Elasticsearch with 1GB Ram ( "ES_JAVA_OPTS=-Xms1g -Xmx1g" )  

```
docker stop elasticsearch
docker rm elasticsearch
# Remember to replace %ELK% with the correct Path
docker run -d \
  --name elasticsearch \
  --net elastic \
  -p 9200:9200 -p 9300:9300 \
  -v "%ELK%/elasticsearch-data:/usr/share/elasticsearch/data" \
  -v "%ELK%/elasticbackup:/usr/share/elasticsearch/backup" \
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
In the previous section we configured and started elasticsearch.  
Elasticsearch has a builtin user for Kibana and we will use the associated token key for Auth.  

Fetch a token / key for the kibana user

```
curl -X POST "localhost:9200/_security/service/elastic/kibana/credential/token/my-kibana-token" \
  -H "Content-Type: application/json" \
  -u elastic:<YOUR_PW>
```
  
You will get an output similar to this:  
  {"created":true,"token":{"name":"my-kibana-token","value":"<YOURTOKEN>"}}% 
  
 
Edit the kibana.yml Configuration file located in the %ELK%/kibana/ folder.  
Add the followint to the kibana.yml  
```
elasticsearch.serviceAccountToken: "<INSERT_YOUR_TOKEN>"
``` 

Start Kibana

```
# Remember to replace %ELK% with the correct Path
docker run -d \
  --name kibana \
  --net elastic \
  -p 5601:5601 \
  -v %ELK%/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml \
  -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
  docker.elastic.co/kibana/kibana:9.1.3
```

Verify Kibana in a browser connecting to <http://localhost:5601/> and connect with user elastic and the password you set for elasticsearch earlier.  
If you run into issues with any containers you can inspect the logs sent to console.  
```
docker logs <containername>  
or continus output logs using the -f for follow
Logging will continue to output until you press ctrl+c
docker logs -f <containername> 
```
  
## 4: Configure Logstash

For logstash to function properly we will have to use username / password when communicating to elasticsearch. 
The api_key parameter only works when elasticsearch runs https://

Reset Password using
```
docker exec -ti elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u logstash_system --interactive
```
  

open the %ELK%/logstash/pipeline/logstash.conf file in a texteditor  
Go to line 148,165 and 230. Change the password parameter to your password for the logstash_system user  

Start logstash  
```  
# Remember to replace %ELK% with the correct Path
  --name logstash \
  --net elastic \
  -p 5044:5044 \
  -p 5140:5140/udp \
  -p 9600:9600 \
  -v "%ELK%/logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml" \
  -v "%ELK%/logstash/pipeline:/usr/share/logstash/pipeline" \
  docker.elastic.co/logstash/logstash:9.1.3

```

## 5: Making this work for your environment  
  
Login to your router and enable connection logging.  
After connection logging is enabled configure a syslog server.  
Enter the IP Address of the host running docker containers and specify 5140 as the port number.  


By default my router only logs inbound connections using GUI.  
The most interesting part is to log outbound traffic from your devices.  
To achieve this on WRT based routers, enable ssh on the LAN interface and SSH into the router using your admin username  

Enable outbound logging using iptables

``` 
iptables -I FORWARD -m state --state NEW -j LOG --log-prefix "OUT_CONN " --log-level 6
``` 

Verify that logstash is able to process syslog messages with my Grok Filter that is made to match OpenWRT / Asuswrt-Merlin.  
``` 
docker logs -f logstash
```   
Logstash will output to console all the messages it is able to interpet.   
If you see messages getting written to the console log you can skip the next chapter.   

### 6: I am not getting logdata

If your syslog messages does not conform to my syslog messages you will need to modify the rule.  
Kibana includes a Grok Debugger.  
Log into kibana and Select DevTools or use this provided link <http://localhost:5601/app/dev_tools#/grokdebugger>  

My logstash.conf provides examples of two syslog messages i process.  
``` 
<12>Sep 19 13:15:55 mephisto-D167CB1-C kernel: DROP IN=eth0 OUT= MAC=04:42:1a:cd:5a:00:40:b4:f0:e0:5e:af:08:00 SRC=165.154.49.137 DST=139.48.125.218 LEN=44 TOS=0x00 PREC=0x00 TTL=44 ID=0 DF PROTO=TCP SPT=47436 DPT=9704 SEQ=1226283879 ACK=0 WINDOW=1024 RES=0x00 SYN URGP=0 OPT (02040584) MARK=0x8000000 

<14>Sep 19 13:13:16 mephisto-D167CB1-C kernel: OUT_CONN IN=br0 OUT=eth0 MAC=04:42:1a:cd:5a:00:ae:39:1a:67:9e:8f:08:00 SRC=192.168.50.6 DST=17.148.146.49 LEN=1228 TOS=0x02 PREC=0x00 TTL=63 ID=0 DF PROTO=UDP SPT=58473 DPT=443 LEN=1208 
``` 
You can use the two messages to learn how the Grok Debugger / logstash processes my syslog data
Paste in one of the two messages into the sample data field.  
  
I use two filters. One for discarding irrelevant messages. Make sure your syslog entry passes both filters. 

Initial validation:
Paste in the grok filter below in the grok pattern field 
``` 
<%{POSINT:priority}>%{SYSLOGTIMESTAMP:timestamp} %{DATA:hostname} %{DATA:program}:
``` 

Then you need to make sure your syslog message works with the more complex filter  

Paste in the grok filter below in the grok pattern field 
``` 
<%{POSINT:priority}>%{SYSLOGTIMESTAMP:timestamp} %{DATA:hostname} %{DATA:program}: %{DATA:action} IN=%{DATA:in_interface} OUT=(?<out_interface>\S*) MAC=(?<mac>\S*) SRC=%{IP:src_ip} DST=%{IP:dst_ip} LEN=%{INT:length} TOS=%{BASE16NUM:tos} PREC=%{BASE16NUM:prec} TTL=%{INT:ttl} ID=%{INT:id}(?: %{WORD:ip_flags})? PROTO=%{WORD:protocol}(?: SPT=%{INT:src_port} DPT=%{INT:dst_port})?(?: LEN=%{INT:udp_length})?(?: SEQ=%{INT:sequence} ACK=%{INT:ack} WINDOW=%{INT:window} RES=%{BASE16NUM:res} %{DATA:tcp_flags} URGP=%{INT:urgp})?(?: MARK=%{DATA:mark})?
``` 

In the bottom of the screen you will get the now structured data.  
Including parsing of message with pri 12  

```
{
  "in_interface": "eth0",
  "ack": "0",
  "program": "kernel",
  "mac": "04:42:1a:cd:5a:00:40:b4:f0:e0:5e:af:08:00",
  "dst_ip": "139.48.125.218",
  "src_ip": "165.154.49.137",
  "hostname": "mephisto-D167CB1-C",
  "protocol": "TCP",
  "prec": "0x00",
  "tcp_flags": "SYN",
  "action": "DROP",
  "tos": "0x00",
  "id": "0",
  "timestamp": "Sep 19 13:15:55",
  "out_interface": "",
  "res": "0x00",
  "length": "44",
  "priority": "12",
  "ttl": "44",
  "ip_flags": "DF",
  "src_port": "47436",
  "urgp": "0",
  "sequence": "1226283879",
  "dst_port": "9704",
  "window": "1024"
}
```
  
In order to make your modified filter work you will have to obtain a complete syslog message from your Router / Firewall / Internet device.  
Try and fetch a complete message from your devices admin interface.  
If this fails, the best way to ensure you get the entire message, as sent to logstash use wireshark and perform a network capture.    
Since we are sending syslog data to an alternative port, 5140, not the normal 514 port you need to tell wireshark it can expect syslog data on port 5140. 
  
Start Wireshark, Select Preferences from the Menu.  
Select Protocols, scroll down to syslog (or better just type syslog and it will take you there).  
Modify Syslog UDP Port so that it contains "514,5140"  

Select the correct interface where syslog messages are recieved, in my setup that is en0: and in the filter field type "port 5140" without the hyphens.  
The filter will ensure only syslog messages on port 5140 are recieved. When you get data in the wireshark window it means a syslog message is captured.  
Stop the Packet Capture , Right click an entry of the captured data and select Follow / UPD Stream.  
Copy a syslog message to your desired text editor. Compare it to one of my example messages giving you an idea of where one message starts and ends.  
  

Play with Grok debugger until you get a match for your message. 
