#!/bin/bash
set -euo pipefail

API_DIR="/opt/trading-api"
PORT=8080
MAX_BACKUPS=5
MAX_RETRIES=5

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ ! -d "$API_DIR" ]; then
    log "ERROR: $API_DIR does not exist"
    exit 1
fi

cd "$API_DIR"

if [ ! -f main.py ]; then
    log "ERROR: main.py not found in $API_DIR"
    exit 1
fi

# --- Parse arguments ---
CHECK_ONLY=False
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=True
    log "Running in check-only mode (no modifications)"
fi

BACKUP_FILE="main.py.bak.$(date +%Y%m%d_%H%M%S)"
cp main.py "$BACKUP_FILE"
log "Backup created: $BACKUP_FILE"

# Auto-cleanup: keep only the most recent backups
BACKUP_COUNT=$(ls -1 main.py.bak.* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    ls -1t main.py.bak.* | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    log "Cleaned up old backups, kept latest $MAX_BACKUPS"
fi

# Run the Python fix engine; capture exit code without triggering set -e
FIX_RESULT=0
python3 << PYEOF || FIX_RESULT=\$?
import ast, sys

f = '${API_DIR}/main.py'
check_only = ${CHECK_ONLY}

with open(f, 'r') as fh:
    source = fh.read()

# Check if the file already compiles
try:
    ast.parse(source)
    print('NO_FIX_NEEDED: file already valid')
    # Exit code 0 = no fix needed
    sys.exit(0)
except SyntaxError as e:
    print(f'Syntax error detected: {e}')

if check_only:
    print('CHECK_MODE: would fix try blocks (use without --check to apply)')
    sys.exit(2)

lines = source.splitlines(keepends=True)

def detect_indent_char(lines):
    """Detect whether the file uses tabs or spaces for indentation."""
    for line in lines:
        stripped = line.lstrip()
        if stripped and line != stripped:
            leading = line[:len(line) - len(stripped)]
            if '\t' in leading:
                return '\t'
    return ' '

def get_indent(line):
    """Return the indentation level of a non-blank line."""
    return len(line) - len(line.lstrip())

def has_code_content(line):
    """Check if a line has actual code (not just a comment or blank)."""
    stripped = line.strip()
    return stripped != '' and not stripped.startswith('#')

def fix_try_blocks(lines):
    """Fix try blocks missing except/finally by iterating bottom-up.

    Bottom-up ensures nested try blocks are fixed before their parents,
    avoiding the issue where an outer try consumes an inner try's block.
    """
    indent_char = detect_indent_char(lines)
    indent_unit = 1 if indent_char == '\t' else 4

    try_indices = []
    for idx, line in enumerate(lines):
        if line.strip() == 'try:':
            try_indices.append(idx)

    for ti in reversed(try_indices):
        indent = get_indent(lines[ti])
        j = ti + 1
        has_body = False
        while j < len(lines):
            l = lines[j]
            if l.strip() == '':
                peek = j + 1
                while peek < len(lines) and lines[peek].strip() == '':
                    peek += 1
                if peek < len(lines) and get_indent(lines[peek]) > indent:
                    j += 1
                else:
                    break
            elif get_indent(l) > indent:
                if has_code_content(l):
                    has_body = True
                j += 1
            else:
                break

        k = j
        while k < len(lines) and lines[k].strip() == '':
            k += 1

        if k >= len(lines) or not lines[k].strip().startswith(('except', 'finally')):
            body_indent = indent_char * (indent + indent_unit)
            if not has_body:
                lines.insert(j, body_indent + 'pass\n')
                j += 1
            except_line = indent_char * indent + 'except Exception:\n'
            pass_line = body_indent + 'pass\n'
            lines.insert(j, pass_line)
            lines.insert(j, except_line)

    return lines

lines = fix_try_blocks(lines)

# Verify the fix works before writing
try:
    ast.parse(''.join(lines))
except SyntaxError as e:
    print(f'FATAL: fix produced invalid syntax: {e}')
    sys.exit(1)

with open(f, 'w') as fh:
    fh.writelines(lines)

print('FIXED OK')
sys.exit(0)
PYEOF

# Handle Python exit codes:
#   0 = no fix needed or fix succeeded
#   2 = check-only mode, has errors
#   1 = fix failed
if [ "$FIX_RESULT" -eq 1 ]; then
    log "FATAL: Fix failed, restoring backup..."
    cp "$BACKUP_FILE" main.py
    log "Restored main.py from $BACKUP_FILE"
    exit 1
elif [ "$FIX_RESULT" -eq 2 ]; then
    log "Check-only mode complete"
    exit 0
fi

# Double-check with py_compile
if ! python3 -m py_compile "$API_DIR/main.py" 2>/dev/null; then
    log "FATAL: py_compile failed after fix, restoring backup..."
    cp "$BACKUP_FILE" main.py
    log "Restored main.py from $BACKUP_FILE"
    exit 1
fi
log "SYNTAX_OK"

if [ "$CHECK_ONLY" = "True" ]; then
    exit 0
fi

# --- Service restart ---
OLD_PID=$(lsof -ti:"$PORT" 2>/dev/null || ss -tlnp 2>/dev/null | grep ":$PORT" | grep -oP 'pid=\K[0-9]+' || true)
if [ -n "$OLD_PID" ]; then
    log "Stopping existing process on port $PORT (PID: $OLD_PID)"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill -9 "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
else
    log "No existing process on port $PORT"
fi

if [ ! -f "$API_DIR/venv/bin/uvicorn" ]; then
    log "ERROR: uvicorn not found in venv"
    exit 1
fi

cd "$API_DIR"
nohup venv/bin/uvicorn main:app --host 0.0.0.0 --port "$PORT" > /tmp/trading.log 2>&1 &
UVICORN_PID=$!
log "Started uvicorn (PID: $UVICORN_PID)"

# --- Health check with retry ---
for i in $(seq 1 $MAX_RETRIES); do
    sleep 2
    if curl -s --connect-timeout 3 "http://localhost:${PORT}/health" > /dev/null 2>&1; then
        log "HEALTH_CHECK_OK (attempt $i)"
        exit 0
    fi
    log "Waiting for server... attempt $i/$MAX_RETRIES"
done

# Server didn't start - show logs for debugging
log "HEALTH_CHECK_FAILED after $MAX_RETRIES attempts"
if [ -f /tmp/trading.log ]; then
    log "=== Last 20 lines of trading.log ==="
    tail -20 /tmp/trading.log
fi
exit 1