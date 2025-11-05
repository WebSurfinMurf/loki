# Loki - Log Aggregation System

## Executive Summary
Loki is a horizontally scalable, highly available, multi-tenant log aggregation system inspired by Prometheus. It indexes metadata about logs rather than the full text, making it very cost-effective and efficient.

## Current Status
- **Status**: ✅ Working (with Keycloak SSO)
- **External URL**: https://loki.ai-servicers.com (Web UI with auth)
- **Internal API**: http://loki:3100 (from containers)
- **Containers**: loki, loki-ui, loki-auth-proxy
- **Networks**: observability-net (loki), traefik-net (ui & proxy)
- **Authentication**: Keycloak OAuth2 (administrators group)

## Architecture
- Stores logs in chunks on filesystem
- Uses BoltDB for indexing
- Accepts logs from Promtail
- Provides LogQL query language
- 30-day retention policy

## File Locations
- **Project**: `/home/administrator/projects/loki/`
- **Data**: `/home/administrator/projects/data/loki/`
- **Config**: `/home/administrator/projects/loki/loki.yml`
- **UI Files**: 
  - `/home/administrator/projects/loki/loki-status.html` (status page)
  - `/home/administrator/projects/loki/nginx.conf` (UI proxy config)
- **Secrets**: `$HOME/projects/secrets/loki.env`
- **Deploy Script**: `/home/administrator/projects/loki/deploy.sh` (with Keycloak OAuth2)

## Access Methods
- **Web UI**: https://loki.ai-servicers.com (requires Keycloak login)
- **API Endpoints** (after authentication):
  - Query: https://loki.ai-servicers.com/loki/api/v1/query
  - Query Range: https://loki.ai-servicers.com/loki/api/v1/query_range
  - Labels: https://loki.ai-servicers.com/loki/api/v1/labels
  - Ready: https://loki.ai-servicers.com/ready
  - Metrics: https://loki.ai-servicers.com/metrics
- **Internal API** (from containers):
  - Direct: http://loki:3100/loki/api/v1/
  - Ready: http://loki:3100/ready

## Common Operations

### Deploy/Update
```bash
cd /home/administrator/projects/loki && ./deploy.sh
```

### View Logs
```bash
# Loki service logs
docker logs loki --tail 50 -f

# OAuth2 proxy logs
docker logs loki-auth-proxy --tail 50 -f

# UI nginx logs
docker logs loki-ui --tail 50 -f
```

### Query Logs (LogQL)
```bash
# From inside containers
docker run --rm --network observability-net curlimages/curl \
  curl -G -s "http://loki:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="containerlogs"}'

# Search for errors
docker run --rm --network observability-net curlimages/curl \
  curl -G -s "http://loki:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="containerlogs"} |~ "ERROR"'
```

### Check Health
```bash
# Direct API check
curl http://localhost:3100/ready

# Through web UI (after auth)
curl https://loki.ai-servicers.com/ready
```

### Restart
```bash
docker restart loki loki-ui loki-auth-proxy
```

## Troubleshooting

### Issue: 403 Forbidden on web access
- User not in administrators group in Keycloak
- Clear browser cookies and try again
- Check user info: https://loki.ai-servicers.com/oauth2/userinfo

### Issue: Not receiving logs
- Check Promtail is running: `docker ps | grep promtail`
- Check network connectivity: `docker network inspect observability-net`
- Verify Loki is on both networks: `docker inspect loki | grep NetworkMode`
- Check logs: `docker logs loki --tail 100`

### Issue: High memory usage
- Adjust retention period in loki.yml
- Reduce ingestion_rate_mb and ingestion_burst_size_mb
- Check chunk cache settings

### Issue: Slow queries
- Add more specific labels to queries
- Reduce time range
- Check max_query_parallelism setting

### Issue: UI not loading
- Check nginx container: `docker logs loki-ui`
- Verify status page exists: `docker exec loki-ui ls /usr/share/nginx/html/`
- Check OAuth2 proxy upstream: `docker logs loki-auth-proxy | grep upstream`

## Integration Points
- **Promtail**: Sends logs to Loki
- **Grafana**: Can visualize Loki data
- **MCP Server**: Will query via API

## Authentication Details
- **Provider**: Keycloak OAuth2 via oauth2-proxy
- **Allowed Groups**: administrators
- **Session Duration**: 7 days
- **Client ID**: loki

## UI Features
- Custom status page showing API endpoints
- Real-time metrics display
- LogQL query examples
- Links to documentation

## Network Requirements
- **Loki**: Must be on `observability-net` (for Promtail) and `traefik-net` (for proxy access)
- **OAuth2 Proxy**: Must be on `traefik-net` (for web traffic) and `keycloak-net` (for token validation)
- **UI (nginx)**: Only needs `traefik-net` network

## Key Configuration Notes
- OAuth2 proxy MUST be connected to both networks for authentication to work
- The 500 "Invalid client credentials" error indicates missing keycloak-net connection
- Custom UI serves from nginx container as Loki has no built-in web interface

## Last Updated
- 2025-09-01 14:17 - Initial deployment
- 2025-09-01 22:07 - Added Keycloak OAuth2 authentication and web UI
- 2025-09-01 22:16 - Fixed OAuth2 network connectivity, added verbose logging