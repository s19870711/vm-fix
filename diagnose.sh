#!/bin/bash
# VM Diagnostic Script

API_DIR="/opt/trading-api"
AGENT_LOG="/opt/nebula-agent/agent.log"
HEALTH_URL="http://localhost:8080/health"

echo '=== a. Python syntax check ==='
if [ -d "$API_DIR" ]; then
    python3 -c "import ast; ast.parse(open('${API_DIR}/main.py').read())" 2>&1 | tail -10
else
    echo "ERROR: $API_DIR does not exist"
fi
echo ''

echo '=== b. Service status ==='
if command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
    systemctl status trading-api 2>&1 | tail -20
else
    echo "SKIP: systemd not available"
fi
echo ''

echo '=== c. Data dir ==='
if [ -d "$API_DIR/data" ]; then
    ls "$API_DIR/data/" 2>&1
else
    echo "ERROR: $API_DIR/data/ does not exist"
fi
echo ''

echo '=== d. daily_watchlist.json (first 50 lines) ==='
if [ -f "$API_DIR/data/daily_watchlist.json" ]; then
    head -50 "$API_DIR/data/daily_watchlist.json"
else
    echo "ERROR: daily_watchlist.json not found"
fi
echo ''

echo '=== e. Processes ==='
ps aux | grep -E 'python|uvicorn|9090' | grep -v grep || echo "No matching processes found"
echo ''

echo '=== f. Agent log ==='
if [ -f "$AGENT_LOG" ]; then
    tail -20 "$AGENT_LOG"
else
    echo "ERROR: $AGENT_LOG not found"
fi
echo ''

echo '=== g. Health check ==='
if command -v curl &>/dev/null; then
    curl -s --connect-timeout 5 "$HEALTH_URL" 2>&1 || echo "HEALTH_CHECK_FAILED"
else
    echo "SKIP: curl not available"
fi
echo ''
echo '=== DONE ==='
