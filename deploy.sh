#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Loki Deployment with Keycloak OAuth2 ===${NC}"

# Check if client secret needs to be set
if grep -q "REPLACE_WITH_KEYCLOAK_SECRET" $HOME/projects/secrets/loki.env; then
    echo -e "${YELLOW}Please set the Keycloak client secret first!${NC}"
    echo "1. Go to https://keycloak.ai-servicers.com"
    echo "2. Create client 'loki' (see KEYCLOAK-SETUP.md)"
    echo "3. Copy the client secret"
    echo "4. Run: sed -i 's/REPLACE_WITH_KEYCLOAK_SECRET/YOUR_SECRET/' $HOME/projects/secrets/loki.env"
    echo "5. Run this script again"
    exit 1
fi

# Load secrets
source $HOME/projects/secrets/loki.env

# Stop existing containers
echo -e "${YELLOW}Stopping existing containers...${NC}"
docker stop loki 2>/dev/null || true
docker rm loki 2>/dev/null || true
docker stop loki-ui 2>/dev/null || true
docker rm loki-ui 2>/dev/null || true
docker stop loki-auth-proxy 2>/dev/null || true
docker rm loki-auth-proxy 2>/dev/null || true

# Create data directory if it doesn't exist
mkdir -p /home/administrator/projects/data/loki 2>/dev/null || true

# Create networks if they don't exist
echo -e "${YELLOW}Creating networks...${NC}"
docker network create loki-net 2>/dev/null || echo "Network loki-net already exists"
docker network create monitoring-net 2>/dev/null || echo "Network monitoring-net already exists"

# Deploy Loki (on loki-net and monitoring-net, NOT on traefik-net)
echo -e "${YELLOW}Deploying Loki container...${NC}"
docker run -d \
  --name loki \
  --restart unless-stopped \
  --network loki-net \
  --network-alias loki \
  -p 3100:3100 \
  -v /home/administrator/projects/loki/loki.yml:/etc/loki/config.yml:ro \
  -v /home/administrator/projects/data/loki:/loki \
  grafana/loki:2.9.3

# Add to monitoring network for integration with other services
docker network connect monitoring-net loki 2>/dev/null || true

# Deploy nginx to serve UI (on traefik-net and loki-net)
echo -e "${YELLOW}Deploying Loki UI container...${NC}"
docker run -d \
  --name loki-ui \
  --restart unless-stopped \
  --network traefik-net \
  --network-alias loki-ui \
  -v /home/administrator/projects/loki/loki-status.html:/usr/share/nginx/html/loki-status.html:ro \
  -v /home/administrator/projects/loki/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine

# Connect UI to loki-net to reach loki backend
docker network connect loki-net loki-ui 2>/dev/null || true

# Deploy OAuth2 Proxy (WITH Traefik labels)
echo -e "${YELLOW}Deploying OAuth2 Proxy...${NC}"
docker run -d \
  --name loki-auth-proxy \
  --restart unless-stopped \
  --network traefik-net \
  --env-file $HOME/projects/secrets/loki.env \
  -e OAUTH2_PROXY_UPSTREAMS=http://loki-ui:80/ \
  -e OAUTH2_PROXY_STANDARD_LOGGING=true \
  -e OAUTH2_PROXY_AUTH_LOGGING=true \
  -e OAUTH2_PROXY_REQUEST_LOGGING=true \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.loki.rule=Host(\`loki.ai-servicers.com\`)" \
  --label "traefik.http.routers.loki.entrypoints=websecure" \
  --label "traefik.http.routers.loki.tls=true" \
  --label "traefik.http.routers.loki.tls.certresolver=letsencrypt" \
  --label "traefik.http.services.loki.loadbalancer.server.port=4180" \
  quay.io/oauth2-proxy/oauth2-proxy:latest

# Add OAuth2 proxy to additional networks
echo -e "${YELLOW}Adding OAuth2 proxy to additional networks...${NC}"
docker network connect keycloak-net loki-auth-proxy 2>/dev/null || true
docker network connect loki-net loki-auth-proxy 2>/dev/null || true
docker network connect monitoring-net loki-auth-proxy 2>/dev/null || true

# Wait for services to start
echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 5

# Check container status
echo -e "${YELLOW}Checking container status...${NC}"
if docker ps | grep -q "loki" && docker ps | grep -q "loki-ui" && docker ps | grep -q "loki-auth-proxy"; then
    echo -e "${GREEN}✓ All containers are running${NC}"
else
    echo -e "${RED}✗ One or more containers failed to start${NC}"
    docker ps -a | grep -E "loki"
    echo -e "${YELLOW}Checking logs...${NC}"
    docker logs loki --tail 10 2>&1 || true
    docker logs loki-ui --tail 10 2>&1 || true
    docker logs loki-auth-proxy --tail 10 2>&1 || true
    exit 1
fi

# Test Loki API
echo -e "${YELLOW}Testing Loki API...${NC}"
if curl -s http://localhost:3100/ready | grep -q "ready"; then
    echo -e "${GREEN}✓ Loki API is ready${NC}"
else
    echo -e "${RED}✗ Loki API is not responding${NC}"
fi

echo -e "${GREEN}✓ Deployment complete${NC}"
echo ""
echo -e "${GREEN}Access Loki at: https://loki.ai-servicers.com${NC}"
echo -e "${YELLOW}Note: You'll need to authenticate with Keycloak (administrators group)${NC}"
echo ""
echo -e "API Endpoints (after authentication):"
echo -e "  Query: https://loki.ai-servicers.com/loki/api/v1/query"
echo -e "  Labels: https://loki.ai-servicers.com/loki/api/v1/labels"
echo -e "  Ready: https://loki.ai-servicers.com/ready"
echo ""
echo -e "To check logs:"
echo -e "  docker logs loki-auth-proxy --tail 20"
echo -e "  docker logs loki --tail 20"