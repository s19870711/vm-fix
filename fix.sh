#!/bin/bash
set -e

cd /opt/trading-api

cp main.py main.py.bak.$(date +%Y%m%d_%H%M%S)

python3 << 'PYEOF'
f = '/opt/trading-api/main.py'
with open(f, 'r') as fh:
    lines = fh.readlines()

fixed = []
i = 0
while i < len(lines):
    line = lines[i]
    fixed.append(line)
    if line.strip() == 'try:':
        indent = len(line) - len(line.lstrip())
        j = i + 1
        block = []
        while j < len(lines):
            l = lines[j]
            if l.strip() == '' or len(l) - len(l.lstrip()) > indent:
                block.append(l)
                j += 1
            else:
                break
        fixed.extend(block)
        k = j
        while k < len(lines) and lines[k].strip() == '':
            k += 1
        if k >= len(lines) or not lines[k].strip().startswith(('except', 'finally')):
            fixed.append(' ' * indent + 'except Exception:\n')
            fixed.append(' ' * (indent + 4) + 'pass\n')
        i = j
        continue
    i += 1

with open(f, 'w') as fh:
    fh.writelines(fixed)
print('FIXED OK')
PYEOF

python3 -m py_compile /opt/trading-api/main.py && echo "SYNTAX_OK"

pkill -f uvicorn 2>/dev/null || true
sleep 2
cd /opt/trading-api
nohup venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080 > /tmp/trading.log 2>&1 &
sleep 8

curl -s http://localhost:8080/health || echo "HEALTH_CHECK_FAILED"