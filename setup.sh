#!/bin/zsh

# Home Security Analytics Platform - Automated Setup Script
# Based on the manual instructions in README.md ( https://github.com/kaiAsmOne/ELKAnalytics )
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# PLEASE NOTE THAT THIS SCRIPT WILL STOP AND DELETE 
# The following containers if they exist: elasticsearch , kibana , logstash
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Home Security Analytics Platform - Automated Setup${NC}"
echo "=================================================="

# Get the current directory as ELK_PATH
ELK_PATH=$(pwd)
echo -e "Using ${YELLOW}${ELK_PATH}${NC} as the project directory"

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running. Please start Docker first.${NC}"
        exit 1
    fi
}

# Function to prompt for passwords
get_passwords() {
    echo -e "\n${YELLOW}Setting up passwords...${NC}"
    
    # Get Elasticsearch password
    while true; do
        read -s -p "Enter password for Elasticsearch 'elastic' user: " ELASTIC_PASSWORD
        echo
        read -s -p "Confirm password: " ELASTIC_PASSWORD_CONFIRM
        echo
        if [ "$ELASTIC_PASSWORD" = "$ELASTIC_PASSWORD_CONFIRM" ]; then
            export ELASTIC_PASSWORD
            break
        else
            echo -e "${RED}Passwords don't match. Please try again.${NC}"
        fi
    done
    
    # Get Logstash password
    while true; do
        read -s -p "Enter password for Elasticsearch 'logstash_system' user: " LOGSTASH_PASSWORD
        echo
        read -s -p "Confirm password: " LOGSTASH_PASSWORD_CONFIRM
        echo
        if [ "$LOGSTASH_PASSWORD" = "$LOGSTASH_PASSWORD_CONFIRM" ]; then
            export LOGSTASH_PASSWORD
            break
        else
            echo -e "${RED}Passwords don't match. Please try again.${NC}"
        fi
    done
}

# Function to create required directories
create_directories() {
    echo -e "\n${YELLOW}Creating required directories...${NC}"
    mkdir -p "${ELK_PATH}/elasticbackup"
    echo -e "${GREEN}Directories created successfully${NC}"
}

# Function to create Docker network
create_network() {
    echo -e "\n${YELLOW}Creating Docker network 'elastic'...${NC}"
    if docker network ls | grep -q elastic; then
        echo "Network 'elastic' already exists"
    else
        docker network create elastic
        echo -e "${GREEN}Network 'elastic' created${NC}"
    fi
}

# Function to clean up existing containers
cleanup_containers() {
    echo -e "\n${YELLOW}Cleaning up existing containers...${NC}"
    
    containers=("elasticsearch" "kibana" "logstash")
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            echo "Stopping and removing existing ${container} container..."
            docker stop "${container}" > /dev/null 2>&1 || true
            docker rm "${container}" > /dev/null 2>&1 || true
        fi
    done
}

# Function to start Elasticsearch initially for password reset
start_elasticsearch_temp() {
    echo -e "\n${YELLOW}Starting Elasticsearch temporarily for initial setup...${NC}"
    
    docker run -d \
        --name elasticsearch \
        --net elastic \
        -p 9200:9200 -p 9300:9300 \
        -e "discovery.type=single-node" \
        -e "xpack.security.enabled=true" \
        -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
        docker.elastic.co/elasticsearch/elasticsearch:9.1.3

    # Wait for Elasticsearch to be ready
    echo "Waiting for Elasticsearch to start..."
    timeout=120
    counter=0
    until curl -s "http://localhost:9200/_cluster/health" > /dev/null 2>&1; do
        echo "Waiting for Elasticsearch... ($counter/${timeout}s)"
        sleep 5
        counter=$((counter + 5))
        if [ $counter -ge $timeout ]; then
            echo -e "${RED}Timeout waiting for Elasticsearch to start${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}Elasticsearch is ready${NC}"
}

# Function to reset Elasticsearch passwords
reset_elasticsearch_passwords() {
    echo -e "\n${YELLOW}Resetting Elasticsearch passwords...${NC}"
    
    # Reset elastic user password
    echo "Setting password for 'elastic' user..."
    docker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -s --batch <<< "${ELASTIC_PASSWORD}"
    
    # Reset logstash_system user password  
    echo "Setting password for 'logstash_system' user..."
    docker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-reset-password -u logstash_system -s --batch <<< "${LOGSTASH_PASSWORD}"
    
    echo -e "${GREEN}Passwords reset successfully${NC}"
}

# Function to restart Elasticsearch with persistent configuration
restart_elasticsearch() {
    echo -e "\n${YELLOW}Restarting Elasticsearch with persistent configuration...${NC}"
    
    # Stop temporary container
    docker stop elasticsearch
    docker rm elasticsearch
    
    # Start with persistent volumes and password
    docker run -d \
        --name elasticsearch \
        --net elastic \
        -p 9200:9200 -p 9300:9300 \
        -v "${ELK_PATH}/elasticsearch-data:/usr/share/elasticsearch/data" \
        -v "${ELK_PATH}/elasticbackup:/usr/share/elasticsearch/backup" \
        -e "discovery.type=single-node" \
        -e "xpack.security.enabled=true" \
        -e "ELASTIC_PASSWORD=${ELASTIC_PASSWORD}" \
        -e "path.repo=/usr/share/elasticsearch/backup" \
        -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
        docker.elastic.co/elasticsearch/elasticsearch:9.1.3

    # Wait for Elasticsearch to be ready with authentication
    echo "Waiting for Elasticsearch to restart..."
    timeout=120
    counter=0
    until curl -s -u "elastic:${ELASTIC_PASSWORD}" "http://localhost:9200/_cluster/health" > /dev/null 2>&1; do
        echo "Waiting for Elasticsearch with authentication... ($counter/${timeout}s)"
        sleep 5
        counter=$((counter + 5))
        if [ $counter -ge $timeout ]; then
            echo -e "${RED}Timeout waiting for Elasticsearch to restart${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}Elasticsearch is ready with authentication${NC}"
}

# Function to verify cluster health
verify_cluster_health() {
    echo -e "\n${YELLOW}Verifying cluster health...${NC}"
    health_response=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" "http://localhost:9200/_cluster/health")
    echo "Cluster health: ${health_response}"
    echo -e "${GREEN}Cluster health verified${NC}"
}

# Function to get Kibana service token
get_kibana_token() {
    echo -e "\n${YELLOW}Getting Kibana service token...${NC}"
    
    token_response=$(curl -s -X POST "http://localhost:9200/_security/service/elastic/kibana/credential/token/my-kibana-token" \
        -H "Content-Type: application/json" \
        -u "elastic:${ELASTIC_PASSWORD}")
    
    KIBANA_TOKEN=$(echo "$token_response" | grep -o '"value":"[^"]*"' | sed 's/"value":"\([^"]*\)"/\1/')
    export KIBANA_TOKEN
    
    if [ -z "$KIBANA_TOKEN" ]; then
        echo -e "${RED}Failed to get Kibana token${NC}"
        echo "Response: $token_response"
        exit 1
    fi
    
    echo -e "${GREEN}Kibana token obtained${NC}"
}

# Function to create Kibana configuration
create_kibana_config() {
    echo -e "\n${YELLOW}Creating Kibana configuration...${NC}"
    
    cat > "${ELK_PATH}/kibana/kibana.yml" << EOF
elasticsearch.serviceAccountToken: "${KIBANA_TOKEN}"
EOF
    
    echo -e "${GREEN}Kibana configuration created${NC}"
}

# Function to start Kibana
start_kibana() {
    echo -e "\n${YELLOW}Starting Kibana...${NC}"
    
    docker run -d \
        --name kibana \
        --net elastic \
        -p 5601:5601 \
        -v "${ELK_PATH}/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml" \
        -e "ELASTICSEARCH_HOSTS=http://elasticsearch:9200" \
        docker.elastic.co/kibana/kibana:9.1.3

    # Wait for Kibana to be ready
    echo "Waiting for Kibana to start..."
    timeout=180
    counter=0
    until curl -s "http://localhost:5601/api/status" > /dev/null 2>&1; do
        echo "Waiting for Kibana... ($counter/${timeout}s)"
        sleep 5
        counter=$((counter + 5))
        if [ $counter -ge $timeout ]; then
            echo -e "${RED}Timeout waiting for Kibana to start${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}Kibana is ready${NC}"
}

# Function to update Logstash configuration
update_logstash_config() {
    echo -e "\n${YELLOW}Updating Logstash configuration...${NC}"
    
    # Check if logstash.conf exists
    if [ ! -f "${ELK_PATH}/logstash/pipeline/logstash.conf" ]; then
        echo -e "${RED}Error: logstash.conf not found at ${ELK_PATH}/logstash/pipeline/logstash.conf${NC}"
        echo "Please ensure the logstash.conf file exists before running this script."
        exit 1
    fi
        
    # Replace password placeholders with actual password
    sed -i.tmp "s/password => \"<YOUR_PW>\"/password => \"${LOGSTASH_PASSWORD}\"/g" "${ELK_PATH}/logstash/pipeline/logstash.conf"
    
    # Remove the temporary file created by sed
    rm -f "${ELK_PATH}/logstash/pipeline/logstash.conf.tmp"
    
    # Verify replacements were made
    password_count=$(grep -c "password => \"${LOGSTASH_PASSWORD}\"" "${ELK_PATH}/logstash/pipeline/logstash.conf")
    placeholder_count=$(grep -c "password => \"<YOUR_PW>\"" "${ELK_PATH}/logstash/pipeline/logstash.conf")
    
    if [ $placeholder_count -gt 0 ]; then
        echo -e "${RED}Warning: ${placeholder_count} password placeholder(s) still found in logstash.conf${NC}"
        echo "Please check the file manually."
    fi
    
    if [ $password_count -gt 0 ]; then
        echo -e "${GREEN}Successfully updated ${password_count} password(s) in logstash.conf${NC}"
    else
        echo -e "${YELLOW}No password placeholders found to replace${NC}"
    fi
    
    # Append to logstash.yml
    cat >> "${ELK_PATH}/logstash/config/logstash.yml" << EOF
xpack.monitoring.elasticsearch.username: logstash_system
xpack.monitoring.elasticsearch.password: "${LOGSTASH_PASSWORD}"
EOF
    
    echo -e "${GREEN}Logstash configuration updated${NC}"
}

# Function to start Logstash
start_logstash() {
    echo -e "\n${YELLOW}Starting Logstash...${NC}"
    
    docker run -d \
        --name logstash \
        --net elastic \
        -p 5044:5044 \
        -p 5140:5140/udp \
        -p 9600:9600 \
        -v "${ELK_PATH}/logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml" \
        -v "${ELK_PATH}/logstash/pipeline:/usr/share/logstash/pipeline" \
        docker.elastic.co/logstash/logstash:9.1.3

    # Wait for Logstash to be ready
    echo "Waiting for Logstash to start..."
    timeout=180
    counter=0
    until curl -s "http://localhost:9600/_node/stats" > /dev/null 2>&1; do
        echo "Waiting for Logstash... ($counter/${timeout}s)"
        sleep 5
        counter=$((counter + 5))
        if [ $counter -ge $timeout ]; then
            echo -e "${RED}Timeout waiting for Logstash to start${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}Logstash is ready${NC}"
}

# Function to display final information
display_final_info() {
    echo -e "\n${GREEN}=================================================="
    echo -e "Home Security Analytics Platform Setup Complete!"
    echo -e "==================================================${NC}"
    echo
    echo -e "${YELLOW}Access URLs:${NC}"
    echo "- Kibana: http://localhost:5601"
    echo "  Username: elastic"
    echo "  Password: ${ELASTIC_PASSWORD}"
    echo
    echo "- Elasticsearch: http://localhost:9200"
    echo "  Username: elastic" 
    echo "  Password: ${ELASTIC_PASSWORD}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Configure your router to send syslog data to this server on port 5044"
    echo "2. Customize the Logstash configuration in ${ELK_PATH}/logstash/pipeline/logstash.conf"
    echo "3. Set up iptables logging on your router if required for outbound logging:"
    echo "   iptables -I FORWARD -m state --state NEW -j LOG --log-prefix \"OUT_CONN \" --log-level 6"
    echo
    echo -e "${YELLOW}Container Management:${NC}"
    echo "- View logs: docker logs -f <container-name>"
    echo "- Stop all: docker stop elasticsearch kibana logstash"
    echo "- Start all: docker start elasticsearch && sleep 30 && docker start kibana logstash"
    echo
    echo -e "${GREEN}Setup completed successfully!${NC}"
}

# Main execution
main() {
    echo "Starting automated setup..."
    
    check_docker
    get_passwords
    create_directories
    create_network
    cleanup_containers
    start_elasticsearch_temp
    reset_elasticsearch_passwords
    restart_elasticsearch
    verify_cluster_health
    get_kibana_token
    create_kibana_config
    start_kibana
    create_logstash_config
    start_logstash
    display_final_info
}

# Run main function
main "$@"