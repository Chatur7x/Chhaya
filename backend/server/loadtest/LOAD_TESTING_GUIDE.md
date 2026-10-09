# Chhaya Backend Load Testing Guide

## Overview
This guide documents the complete load testing toolkit for the Chhaya Secure Messenger backend, capable of simulating 100-1000 concurrent customers to measure efficiency, performance, and overall system health.

## Location

Every command in this guide is relative to **this directory**:

```bash
cd backend/server/loadtest
```

The `docker-compose.loadtest.yml` here builds the server from `..`
(`backend/server`) and mounts the k6 script, Prometheus config and
Grafana provisioning from this directory.

## Tools Created

### 1. Node.js Load Test (`load-test.js`)
**Pure JavaScript load test with no external dependencies**

```bash
# Basic usage
node load-test.js --users=500 --duration=60 --host=localhost:8443

# Options
--users=N        Number of concurrent users (default: 500)
--duration=N     Test duration in seconds (default: 60)
--rampup=N       Ramp-up period in seconds (default: 10)
--host=HOST:PORT Target host (default: localhost:8443)
```

**Features:**
- 9 weighted scenarios (register, login, profile, contacts, conversations, messages)
- Connection pooling with keep-alive
- Real-time metrics collection (latency percentiles, RPS, error rates)
- Resource monitoring (memory, CPU)
- Detailed console report with efficiency scores

### 2. k6 Load Test (`k6-load-test.js`)
**Industry-standard k6 script for CI/CD integration**

```bash
# Run with k6
k6 run --vus 500 --duration 60s k6-load-test.js

# With custom base URL
k6 run -e BASE_URL=https://api.chhaya.app k6-load-test.js

# Web dashboard
k6 run --vus 500 --duration 60s --web-dashboard k6-load-test.js
```

**Features:**
- 10-stage ramp profile (0→1000 users)
- Threshold-based pass/fail criteria
- Pre-registration of test users
- SharedArray for efficient test data
- Prometheus-compatible metrics output

### 3. Docker Compose Stack (`docker-compose.loadtest.yml`)
**Complete load test environment**

```bash
# Start full stack
docker-compose -f docker-compose.loadtest.yml up -d

# Run load test
docker-compose -f docker-compose.loadtest.yml run load-test

# View results in Grafana
open http://localhost:3000
```

**Services:**
- Chhaya Backend (with health checks)
- PostgreSQL 16 + Redis 7
- k6 Load Test Runner
- Prometheus + Grafana monitoring
- Resource limits and health checks

### 4. Results Analyzer (`analyze-results.js`)
**Post-process results into efficiency report**

```bash
# Analyze k6 JSON output
k6 run --out json=results.json k6-load-test.js
node analyze-results.js results.json

# Analyze Node.js test output
node load-test.js --users=500 > results.json
node analyze-results.js results.json
```

**Outputs:**
- Overall efficiency score (0-100)
- Latency distribution analysis
- Throughput efficiency rating
- Error resilience score
- Scenario-by-scenario breakdown
- Optimization recommendations
- JSON summary for CI/CD integration

### 5. Runner Script (`run-load-test.sh`)
**Convenience wrapper**

```bash
# Auto-detects k6, falls back to Node.js
./run-load-test.sh 500 60 localhost:8443

# Make executable first
chmod +x run-load-test.sh
```

## Test Scenarios (Weighted)

| Scenario | Weight | Description |
|----------|--------|-------------|
| Register | 15% | New user registration with device |
| Login | 20% | Auth with recovery phrase |
| Get Profile | 10% | Authenticated user info |
| Add Contact | 15% | Add new contact by Chhaya ID |
| Get Contacts | 10% | List user contacts |
| Create Conversation | 10% | Start direct/group chat |
| Get Conversations | 10% | List user conversations |
| Send Message | 5% | Send text message |
| Get Messages | 5% | Fetch message history |

## Efficiency Scoring

### Latency Score (0-100)
| Metric | Target | Penalty |
|--------|--------|---------|
| p50 | < 50ms | -10 per 10ms over |
| p95 | < 200ms | -10 per 20ms over |
| p99 | < 500ms | -10 per 50ms over |

### Throughput Score (0-100)
- Target: 0.2 RPS per user (100 RPS per 100 users)
- Score = min(100, actual_rps / target_rps × 100)

### Error Resilience Score (0-100)
| Error Rate | Score |
|------------|-------|
| < 0.1% | 100 |
| < 0.5% | 95 |
| < 1% | 90 |
| < 2% | 75 |
| < 5% | 50 |
| > 5% | 0 |

### Overall Rating
| Score | Rating |
|-------|--------|
| 90-100 | EXCELLENT ⭐⭐⭐⭐⭐ |
| 80-89 | VERY GOOD ⭐⭐⭐⭐ |
| 70-79 | GOOD ⭐⭐⭐ |
| 60-69 | FAIR ⭐⭐ |
| 50-59 | NEEDS IMPROVEMENT ⭐ |
| < 50 | CRITICAL ⚠️ |

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Load Test
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly Monday 2AM
  workflow_dispatch:

jobs:
  load-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: chhaya
          POSTGRES_PASSWORD: chhaya
          POSTGRES_DB: chhaya
        ports: [5432:5432]
      redis:
        image: redis:7
        ports: [6379:6379]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: cd backend/server && npm ci && npm run build
      - run: npm start &  # Start backend
      - run: sleep 10  # Wait for startup
      - run: k6 run k6-load-test.js
      - run: node analyze-results.js results.json
```

## Key Endpoints Tested

| Method | Endpoint | Auth | Purpose |
|--------|----------|------|---------|
| GET | `/health` | No | Health check |
| POST | `/auth/register` | No | User registration |
| POST | `/auth/login` | No | User login |
| GET | `/users/me` | Yes | Profile |
| POST | `/contacts` | Yes | Add contact |
| GET | `/contacts` | Yes | List contacts |
| POST | `/conversations` | Yes | Create chat |
| GET | `/conversations` | Yes | List chats |
| POST | `/messages` | Yes | Send message |
| GET | `/messages/:id` | Yes | Get messages |

## Performance Baselines

| Users | Target RPS | p50 Latency | p95 Latency | Error Rate |
|-------|------------|-------------|-------------|------------|
| 100 | 20 | < 30ms | < 100ms | < 0.1% |
| 500 | 100 | < 50ms | < 200ms | < 0.5% |
| 1000 | 200 | < 100ms | < 500ms | < 1% |

## Monitoring Integration

### Prometheus Metrics
The backend exposes `/metrics` endpoint with:
- `http_requests_total` - Request counter by status
- `http_request_duration_seconds` - Latency histogram
- `active_users` - Current concurrent users
- `db_connections_active` - DB pool usage

### Grafana Dashboards
Pre-built dashboards available in `grafana/dashboards/`:
- Request rate & latency
- Error rate & types
- Resource usage (CPU, Memory, DB, Redis)
- Scenario breakdown

## Troubleshooting

### Common Issues

**High Latency (>500ms p95)**
- Check database connection pool size
- Add Redis caching for frequent queries
- Enable query logging to identify slow queries

**Low Throughput (<50 RPS)**
- Increase Node.js cluster workers
- Optimize database indexes
- Check network bandwidth

**High Error Rate (>1%)**
- Check application logs for 5xx errors
- Verify database connection limits
- Review rate limiting configuration

**Connection Refused**
- Ensure backend is healthy: `curl http://localhost:8443/health`
- Check Docker network connectivity
- Verify port mappings

## File Structure
```
├── load-test.js              # Node.js load test
├── k6-load-test.js           # k6 script
├── analyze-results.js        # Results analyzer
├── run-load-test.sh          # Runner script
├── docker-compose.loadtest.yml  # Full stack
├── prometheus.yml            # Prometheus config
├── LOAD_TESTING_GUIDE.md     # This file
└── grafana/
    ├── dashboards/           # Grafana dashboards
    └── datasources/          # Prometheus datasource
```

## Quick Start

```bash
# 1. Start backend services
docker-compose -f docker-compose.loadtest.yml up -d db redis backend

# 2. Wait for health
curl http://localhost:8443/api/v1/health

# 3. Run quick test (100 users, 30s)
node load-test.js --users=100 --duration=30

# 4. Run full test (500 users, 60s)
./run-load-test.sh 500 60

# 5. Analyze results
node analyze-results.js results.json
```

## Next Steps
1. Add WebSocket load testing for signaling/onion relay
2. Implement chaos engineering scenarios (network partition, DB failover)
3. Add custom business metric tracking (message delivery rate, etc.)
4. Set up automated regression detection in CI/CD