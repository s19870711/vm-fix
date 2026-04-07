#!/bin/bash
# SkyNet 專用診斷腳本

SKYNET_DIR="/home/ubuntu/skynet_v2_improved"

echo '======================================'
echo '  SkyNet 量化中樞 - 診斷報告'
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo '======================================'
echo ''

echo '=== 系統資源 ==='
uptime
free -h | head -2
df -h / | tail -1
echo ''

echo '=== SkyNet 進程 ==='
ps aux | grep 'python main.py' | grep -v grep || echo "  [FAIL] SkyNet 未運行"
echo ''

echo '=== 端口監聽 ==='
ss -tlnp 2>/dev/null | grep -E '8080|8443|443' || echo "  [FAIL] 無端口監聽"
echo ''

echo '=== 持倉狀態 ==='
python3 -c "
import json
with open('${SKYNET_DIR}/data/position_costs.json') as f:
    d = json.load(f)
print(f'  總成本: {d.get(\"total_cost\", \"N/A\"):,}')
print(f'  總市值: {d.get(\"total_market_value\", \"N/A\"):,}')
print(f'  損益: {d.get(\"total_unrealized_pnl\", \"N/A\"):,}')
print(f'  持倉數: {len(d.get(\"positions\", {}))}')
for k, v in d.get('positions', {}).items():
    print(f'    {v[\"name\"]} ({k}): 成本{v[\"avg_cost\"]} x {v[\"shares\"]}股 = {v[\"total_cost\"]:,}')
" 2>&1 || echo "  [FAIL] 無法讀取持倉資料"
echo ''

echo '=== 交易開關 ==='
grep -n 'TRADING_ENABLED' "$SKYNET_DIR/main.py" | head -3
grep -n 'TOTAL_CAPITAL_LIMIT' "$SKYNET_DIR/main.py" | head -3
echo ''

echo '=== 交易暫停旗標 ==='
if [ -f "$SKYNET_DIR/data/TRADING_HALTED" ]; then
    echo "  [HALT] 交易已暫停"
    cat "$SKYNET_DIR/data/TRADING_HALTED" | python3 -m json.tool 2>/dev/null
else
    echo "  [ACTIVE] 無暫停旗標"
fi
echo ''

echo '=== 最近錯誤 (最新10筆) ==='
grep -iE 'error|exception|fail|critical' "$SKYNET_DIR/logs/skynet.log" 2>/dev/null | tail -10 || echo "  無錯誤"
echo ''

echo '=== 今日交易紀錄 ==='
TODAY=$(date +%Y-%m-%d)
cat "$SKYNET_DIR/data/trade_journal/trades_${TODAY}.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50 || echo "  今日無交易紀錄"
echo ''

echo '=== Watchlist 狀態 ==='
python3 -c "
import json
from datetime import datetime
with open('${SKYNET_DIR}/data/watchlist.json') as f:
    d = json.load(f)
updated = d.get('updated_at', 'unknown')
print(f'  最後更新: {updated}')
print(f'  波段: {d.get(\"swing\", [])}')
print(f'  當沖: {d.get(\"daytrade\", [])}')
" 2>&1 || echo "  [FAIL] 無法讀取 watchlist"
echo ''

echo '=== 訂單防護審計 ==='
if [ -f "$SKYNET_DIR/logs/order_guard_audit.jsonl" ]; then
    echo "  最近5筆訂單檢查:"
    tail -5 "$SKYNET_DIR/logs/order_guard_audit.jsonl" | python3 -m json.tool 2>/dev/null
else
    echo "  無訂單審計紀錄"
fi
echo ''

echo '======================================'
echo '  診斷完成'
echo '======================================'
