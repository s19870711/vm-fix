#!/bin/bash
# VM Diagnostic Script - Comprehensive System Check

API_DIR="/opt/trading-api"
AGENT_LOG="/opt/nebula-agent/agent.log"
HEALTH_URL="http://localhost:8080/health"
TRADING_LOG="/tmp/trading.log"
PORT=8080

PASS=0
WARN=0
FAIL=0

report() {
    local level="$1" msg="$2"
    case "$level" in
        PASS) PASS=$((PASS+1)); echo "  [PASS] $msg" ;;
        WARN) WARN=$((WARN+1)); echo "  [WARN] $msg" ;;
        FAIL) FAIL=$((FAIL+1)); echo "  [FAIL] $msg" ;;
    esac
}

echo '======================================'
echo '  VM Trading API - Diagnostic Report'
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo '======================================'
echo ''

# --- a. System resources ---
echo '=== a. System resources ==='
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
if [ -n "$DISK_USAGE" ]; then
    if [ "$DISK_USAGE" -ge 90 ]; then
        report FAIL "Disk usage: ${DISK_USAGE}% (critical)"
    elif [ "$DISK_USAGE" -ge 75 ]; then
        report WARN "Disk usage: ${DISK_USAGE}% (high)"
    else
        report PASS "Disk usage: ${DISK_USAGE}%"
    fi
fi

MEM_AVAIL=$(free -m 2>/dev/null | awk '/Mem:/{print $7}')
if [ -n "$MEM_AVAIL" ]; then
    if [ "$MEM_AVAIL" -lt 100 ]; then
        report FAIL "Available memory: ${MEM_AVAIL}MB (critical)"
    elif [ "$MEM_AVAIL" -lt 500 ]; then
        report WARN "Available memory: ${MEM_AVAIL}MB (low)"
    else
        report PASS "Available memory: ${MEM_AVAIL}MB"
    fi
fi
echo ''

# --- b. Python environment ---
echo '=== b. Python environment ==='
if [ -d "$API_DIR" ]; then
    report PASS "API directory exists: $API_DIR"
else
    report FAIL "API directory missing: $API_DIR"
fi

if [ -f "$API_DIR/main.py" ]; then
    report PASS "main.py exists"
    if python3 -c "import ast; ast.parse(open('${API_DIR}/main.py').read())" 2>/dev/null; then
        report PASS "main.py syntax valid"
    else
        report FAIL "main.py has syntax errors"
        python3 -c "import ast; ast.parse(open('${API_DIR}/main.py').read())" 2>&1 | tail -5
    fi
else
    report FAIL "main.py not found"
fi

if [ -f "$API_DIR/venv/bin/python" ]; then
    report PASS "Python venv exists"
    VENV_PY_VER=$("$API_DIR/venv/bin/python" --version 2>&1)
    echo "  Version: $VENV_PY_VER"
else
    report WARN "Python venv not found at $API_DIR/venv"
fi

if [ -f "$API_DIR/venv/bin/uvicorn" ]; then
    report PASS "uvicorn installed in venv"
    if [ -x "$API_DIR/venv/bin/uvicorn" ]; then
        report PASS "uvicorn is executable"
    else
        report FAIL "uvicorn exists but is not executable"
    fi
else
    report FAIL "uvicorn not found in venv"
fi

# File permission checks
if [ -f "$API_DIR/main.py" ]; then
    if [ -r "$API_DIR/main.py" ]; then
        report PASS "main.py is readable"
    else
        report FAIL "main.py is not readable (permission denied)"
    fi
fi

# Check if data directory is writable (needed for runtime)
if [ -d "$API_DIR/data" ] && [ -w "$API_DIR/data" ]; then
    report PASS "Data directory is writable"
elif [ -d "$API_DIR/data" ]; then
    report WARN "Data directory is not writable"
fi
echo ''

# --- c. Service status ---
echo '=== c. Service status ==='
if command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
    if systemctl is-active --quiet trading-api 2>/dev/null; then
        report PASS "trading-api service is active"
    else
        report FAIL "trading-api service is not active"
        systemctl status trading-api 2>&1 | tail -5
    fi
else
    echo "  [SKIP] systemd not available"
fi
echo ''

# --- d. Port & process check ---
echo '=== d. Port & process check ==='
UVICORN_PROCS=$(ps aux | grep -E 'uvicorn' | grep -v grep)
if [ -n "$UVICORN_PROCS" ]; then
    report PASS "uvicorn process running"
    echo "$UVICORN_PROCS" | head -3
else
    report FAIL "No uvicorn process found"
fi

if command -v ss &>/dev/null; then
    PORT_8080=$(ss -tlnp 2>/dev/null | grep ':8080')
    if [ -n "$PORT_8080" ]; then
        report PASS "Port 8080 is listening"
    else
        report FAIL "Port 8080 is not listening"
    fi
elif command -v netstat &>/dev/null; then
    PORT_8080=$(netstat -tlnp 2>/dev/null | grep ':8080')
    if [ -n "$PORT_8080" ]; then
        report PASS "Port 8080 is listening"
    else
        report FAIL "Port 8080 is not listening"
    fi
fi
echo ''

# --- e. Data files ---
echo '=== e. Data files ==='
if [ -d "$API_DIR/data" ]; then
    report PASS "Data directory exists"
    FILE_COUNT=$(find "$API_DIR/data" -type f 2>/dev/null | wc -l)
    echo "  Files: $FILE_COUNT"
    if [ -f "$API_DIR/data/daily_watchlist.json" ]; then
        if python3 -c "import json; json.load(open('${API_DIR}/data/daily_watchlist.json'))" 2>/dev/null; then
            report PASS "daily_watchlist.json is valid JSON"
        else
            report FAIL "daily_watchlist.json is not valid JSON"
        fi
    else
        report WARN "daily_watchlist.json not found"
    fi
else
    report FAIL "Data directory missing: $API_DIR/data/"
fi
echo ''

# --- f. Logs ---
echo '=== f. Logs ==='
if [ -f "$AGENT_LOG" ]; then
    report PASS "Agent log exists"
    ERROR_COUNT=$(grep -ci 'error\|exception\|traceback' "$AGENT_LOG" 2>/dev/null || echo 0)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        report WARN "Agent log has $ERROR_COUNT error lines"
        grep -i 'error\|exception\|traceback' "$AGENT_LOG" 2>/dev/null | tail -5
    fi
else
    report WARN "Agent log not found: $AGENT_LOG"
fi

if [ -f "$TRADING_LOG" ]; then
    report PASS "Trading log exists"
    T_ERRORS=$(grep -ci 'error\|exception\|traceback' "$TRADING_LOG" 2>/dev/null || echo 0)
    if [ "$T_ERRORS" -gt 0 ]; then
        report WARN "Trading log has $T_ERRORS error lines"
        grep -i 'error\|exception\|traceback' "$TRADING_LOG" 2>/dev/null | tail -5
    fi
else
    report WARN "Trading log not found: $TRADING_LOG"
fi
echo ''

# --- g. Health check ---
echo '=== g. Health check ==='
if command -v curl &>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$HEALTH_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        report PASS "Health endpoint returned 200"
        curl -s --connect-timeout 5 "$HEALTH_URL" 2>/dev/null
        echo ''
    elif [ "$HTTP_CODE" = "000" ]; then
        report FAIL "Health endpoint unreachable (connection refused)"
    else
        report FAIL "Health endpoint returned HTTP $HTTP_CODE"
    fi
else
    echo "  [SKIP] curl not available"
fi
echo ''

# --- h. Backup files ---
echo '=== h. Backup files ==='
BAK_COUNT=$(find "$API_DIR" -maxdepth 1 -name "main.py.bak.*" 2>/dev/null | wc -l)
if [ "$BAK_COUNT" -gt 0 ]; then
    echo "  Found $BAK_COUNT backup(s):"
    ls -lh "$API_DIR"/main.py.bak.* 2>/dev/null | tail -5
    if [ "$BAK_COUNT" -gt 10 ]; then
        report WARN "Too many backups ($BAK_COUNT), consider cleanup"
    fi
else
    echo "  No backup files found"
fi
echo ''

# --- Summary ---
echo '======================================'
echo "  SUMMARY: $PASS passed, $WARN warnings, $FAIL failures"
echo '======================================'

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
