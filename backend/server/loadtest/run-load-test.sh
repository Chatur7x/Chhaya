#!/bin/bash
# Chhaya Load Test Runner
# Usage: ./run-load-test.sh [users] [duration] [host]

set -e

USERS=${1:-500}
DURATION=${2:-60}
HOST=${3:-localhost:8443}

echo "═══════════════════════════════════════════════════════════"
echo "       CHHAYA BACKEND LOAD TEST RUNNER"
echo "═══════════════════════════════════════════════════════════"
echo "Users:    $USERS"
echo "Duration: ${DURATION}s"
echo "Host:     $HOST"
echo "═══════════════════════════════════════════════════════════"

# Check if k6 is available
if command -v k6 &> /dev/null; then
    echo "Using k6 for load testing..."
    k6 run \
        --vus $USERS \
        --duration ${DURATION}s \
        -e BASE_URL=http://$HOST \
        k6-load-test.js
else
    echo "k6 not found. Using Node.js load test..."
    echo "Install k6 for better results: https://k6.io/docs/getting-started/installation/"
    echo ""
    
    # Run Node.js load test
    node load-test.js --users=$USERS --duration=$DURATION --host=$HOST
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Load test complete!"
echo "═══════════════════════════════════════════════════════════"