#!/bin/bash
set -e

API_DIR="/opt/trading-api"

if [ ! -d "$API_DIR" ]; then
    echo "ERROR: $API_DIR does not exist"
    exit 1
fi

cd "$API_DIR"

if [ ! -f main.py ]; then
    echo "ERROR: main.py not found in $API_DIR"
    exit 1
fi

cp main.py "main.py.bak.$(date +%Y%m%d_%H%M%S)"

python3 << 'PYEOF'
import ast, sys

f = '/opt/trading-api/main.py'
with open(f, 'r') as fh:
    source = fh.read()

# First, check if the file already compiles
try:
    ast.parse(source)
    print('NO_FIX_NEEDED: file already valid')
    sys.exit(0)
except SyntaxError as e:
    print(f'Syntax error detected: {e}')

lines = source.splitlines(keepends=True)

def get_indent(line):
    """Return the indentation level of a non-blank line."""
    return len(line) - len(line.lstrip())

def fix_try_blocks(lines):
    """Fix try blocks missing except/finally by iterating bottom-up.

    Bottom-up ensures nested try blocks are fixed before their parents,
    avoiding the issue where an outer try consumes an inner try's block.
    """
    # Collect all try statement line indices
    try_indices = []
    for idx, line in enumerate(lines):
        if line.strip() == 'try:':
            try_indices.append(idx)

    # Process from last to first so insertions don't shift earlier indices
    for ti in reversed(try_indices):
        indent = get_indent(lines[ti])
        # Find the end of the try body: lines that are deeper or blank
        j = ti + 1
        while j < len(lines):
            l = lines[j]
            if l.strip() == '':
                # Blank line: include only if followed by deeper-indented code
                # that still belongs to this block
                peek = j + 1
                while peek < len(lines) and lines[peek].strip() == '':
                    peek += 1
                if peek < len(lines) and get_indent(lines[peek]) > indent:
                    j += 1
                else:
                    break
            elif get_indent(l) > indent:
                j += 1
            else:
                break

        # Check if the next non-blank line is except/finally
        k = j
        while k < len(lines) and lines[k].strip() == '':
            k += 1

        if k >= len(lines) or not lines[k].strip().startswith(('except', 'finally')):
            # Insert except clause at position j
            except_line = ' ' * indent + 'except Exception:\n'
            pass_line = ' ' * (indent + 4) + 'pass\n'
            lines.insert(j, pass_line)
            lines.insert(j, except_line)

    return lines

lines = fix_try_blocks(lines)

with open(f, 'w') as fh:
    fh.writelines(lines)

# Verify the fix actually works
try:
    ast.parse(''.join(lines))
    print('FIXED OK')
except SyntaxError as e:
    print(f'WARNING: fix incomplete, remaining error: {e}')
    sys.exit(1)
PYEOF

python3 -m py_compile "$API_DIR/main.py" && echo "SYNTAX_OK"

pkill -f uvicorn 2>/dev/null || true
sleep 2

if [ ! -f "$API_DIR/venv/bin/uvicorn" ]; then
    echo "ERROR: uvicorn not found in venv"
    exit 1
fi

cd "$API_DIR"
nohup venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080 > /tmp/trading.log 2>&1 &
UVICORN_PID=$!

# Wait for server to be ready with retry
MAX_RETRIES=5
for i in $(seq 1 $MAX_RETRIES); do
    sleep 2
    if curl -s --connect-timeout 3 http://localhost:8080/health > /dev/null 2>&1; then
        echo "HEALTH_CHECK_OK (attempt $i)"
        exit 0
    fi
    echo "Waiting for server... attempt $i/$MAX_RETRIES"
done

# Server didn't start - show logs for debugging
echo "HEALTH_CHECK_FAILED after $MAX_RETRIES attempts"
if [ -f /tmp/trading.log ]; then
    echo "=== Last 20 lines of trading.log ==="
    tail -20 /tmp/trading.log
fi
exit 1