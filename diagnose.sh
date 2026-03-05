#!/bin/bash
# VM Diagnostic Script
echo '=== a. Python syntax check ==='
cd /opt/trading-api && python3 -c "import ast; ast.parse(open('main.py').read())" 2>&1 | tail -10
echo ''
echo '=== b. Service status ==='
systemctl status trading-api 2>&1 | tail -20
echo ''
echo '=== c. Data dir ==='
ls /opt/trading-api/data/ 2>&1
echo ''
echo '=== d. daily_watchlist.json (first 50 lines) ==='
cat /opt/trading-api/data/daily_watchlist.json 2>&1 | head -50
echo ''
echo '=== e. Processes ==='
ps aux | grep -E 'python|uvicorn|9090' | grep -v grep
echo ''
echo '=== f. Agent log ==='
cat /opt/nebula-agent/agent.log 2>&1 | tail -20
echo ''
echo '=== g. Health check ==='
curl -s http://localhost:8080/health 2>&1
echo ''
echo '=== DONE ==='
