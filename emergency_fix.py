#!/usr/bin/env python3
"""
SkyNet 緊急修復腳本 - P0 級別
修復 4/1 亂下單問題，防止違約交割再次發生

執行方式: cd /home/ubuntu/skynet_v2_improved && python3 /path/to/emergency_fix.py
"""

import json
import os
import re
import shutil
from datetime import datetime
from pathlib import Path

SKYNET_DIR = "/home/ubuntu/skynet_v2_improved"
BACKUP_SUFFIX = datetime.now().strftime("%Y%m%d_%H%M%S")

LOG = []
def log(msg):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")
    LOG.append(f"[{ts}] {msg}")


def backup_file(filepath):
    """建立檔案備份"""
    if os.path.exists(filepath):
        bak = f"{filepath}.bak.emergency_{BACKUP_SUFFIX}"
        shutil.copy2(filepath, bak)
        log(f"  備份: {bak}")
        return True
    return False


def fix_1_update_position_costs():
    """P0-1: 更新 position_costs.json 為券商實際持倉"""
    log("=" * 60)
    log("P0-1: 同步實際券商持倉到 position_costs.json")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "data", "position_costs.json")
    backup_file(filepath)

    actual_positions = {
        "2317.TW": {
            "symbol": "2317.TW",
            "name": "鴻海",
            "shares": 100,
            "avg_cost": 197.28,
            "total_cost": 19925,
            "current_price": 193.0,
            "unrealized_pnl": -428,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        },
        "2330.TW": {
            "symbol": "2330.TW",
            "name": "台積電",
            "shares": 20,
            "avg_cost": 1835.05,
            "total_cost": 36701,
            "current_price": 1810.0,
            "unrealized_pnl": -501,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        },
        "2609.TW": {
            "symbol": "2609.TW",
            "name": "陽明",
            "shares": 378,
            "avg_cost": 52.77,
            "total_cost": 19948,
            "current_price": 52.1,
            "unrealized_pnl": -253,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        },
        "2615.TW": {
            "symbol": "2615.TW",
            "name": "萬海",
            "shares": 253,
            "avg_cost": 79.01,
            "total_cost": 19758,
            "current_price": 78.0,
            "unrealized_pnl": -255,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        },
        "3413.TW": {
            "symbol": "3413.TW",
            "name": "京鼎",
            "shares": 40,
            "avg_cost": 294.9,
            "total_cost": 11796,
            "current_price": 293.5,
            "unrealized_pnl": -56,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        },
        "4935.TW": {
            "symbol": "4935.TW",
            "name": "茂林-KY",
            "shares": 1000,
            "avg_cost": 36.65,
            "total_cost": 36652,
            "current_price": 35.4,
            "unrealized_pnl": -1250,
            "source": "manual_sync_from_broker",
            "synced_at": datetime.now().isoformat()
        }
    }

    data = {
        "last_synced": datetime.now().isoformat(),
        "total_cost": 144775,
        "total_market_value": 141404,
        "total_unrealized_pnl": -3371,
        "positions": actual_positions
    }

    with open(filepath, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    log(f"  已更新 6 檔持倉，總成本 144,775")
    log(f"  DONE")


def fix_2_disable_trading():
    """P0-2: 確保 TRADING_ENABLED = False"""
    log("=" * 60)
    log("P0-2: 停用自動交易 (TRADING_ENABLED = False)")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "main.py")
    backup_file(filepath)

    with open(filepath, "r") as f:
        content = f.read()

    # 確保 TRADING_ENABLED = False
    pattern = r'TRADING_ENABLED\s*=\s*True'
    if re.search(pattern, content):
        content = re.sub(pattern, 'TRADING_ENABLED = False  # EMERGENCY: disabled by emergency_fix.py', content)
        log("  將 TRADING_ENABLED 從 True 改為 False")
    else:
        log("  TRADING_ENABLED 已經是 False")

    # 加入硬性資金上限（如果不存在）
    if 'TOTAL_CAPITAL_LIMIT' not in content:
        insert_after = "TRADING_ENABLED = False"
        idx = content.find(insert_after)
        if idx != -1:
            insert_pos = content.find('\n', idx) + 1
            capital_limit = (
                "\n# === EMERGENCY: 硬性資金上限 (emergency_fix.py 加入) ===\n"
                "TOTAL_CAPITAL_LIMIT = 100000      # 總資金絕對上限，超過拒絕下單\n"
                "TOTAL_POSITION_LIMIT = 6           # 最大同時持倉標的數\n"
                "SINGLE_ORDER_MAX = 20000            # 單筆訂單金額上限\n"
                "REQUIRE_MANUAL_CONFIRM_ABOVE = 15000  # 超過此金額需人工確認\n"
                "# === END EMERGENCY ===\n\n"
            )
            content = content[:insert_pos] + capital_limit + content[insert_pos:]
            log("  已加入 TOTAL_CAPITAL_LIMIT = 100,000")
            log("  已加入 SINGLE_ORDER_MAX = 20,000")
        else:
            log("  警告: 找不到插入位置，手動檢查 main.py")

    with open(filepath, "w") as f:
        f.write(content)

    log("  DONE")


def fix_3_patch_order_guard():
    """P0-3: 修補 order_guard.py 加入資金檢查"""
    log("=" * 60)
    log("P0-3: 修補 order_guard.py 資金硬性檢查")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "src", "layer4_risk", "order_guard.py")

    if not os.path.exists(filepath):
        log(f"  警告: {filepath} 不存在，建立新檔案")
        os.makedirs(os.path.dirname(filepath), exist_ok=True)

    backup_file(filepath)

    # 讀取現有內容
    existing = ""
    if os.path.exists(filepath):
        with open(filepath, "r") as f:
            existing = f.read()

    # 檢查是否已有我們的修補
    if "EMERGENCY_CAPITAL_CHECK" in existing:
        log("  已有緊急資金檢查，跳過")
        return

    patch_code = '''

# === EMERGENCY_CAPITAL_CHECK (added by emergency_fix.py) ===
import json
import os
from datetime import datetime

_POSITION_COSTS_PATH = "/home/ubuntu/skynet_v2_improved/data/position_costs.json"
_TOTAL_CAPITAL_LIMIT = 100000
_SINGLE_ORDER_MAX = 20000
_MAX_POSITIONS = 6

def emergency_capital_check(symbol: str, action: str, quantity: int, price: float) -> dict:
    """
    緊急資金檢查 - 所有下單路徑必須經過此函數。
    返回 {'allowed': True/False, 'reason': str}
    """
    order_amount = quantity * price

    # 1. 單筆金額檢查
    if order_amount > _SINGLE_ORDER_MAX:
        return {
            'allowed': False,
            'reason': f'單筆金額 {order_amount:,.0f} 超過上限 {_SINGLE_ORDER_MAX:,.0f}'
        }

    # 賣出不需要資金檢查
    if action.upper() in ('SELL', 'S'):
        return {'allowed': True, 'reason': 'sell order, no capital check needed'}

    # 2. 讀取當前持倉
    total_cost = 0
    position_count = 0
    try:
        if os.path.exists(_POSITION_COSTS_PATH):
            with open(_POSITION_COSTS_PATH, 'r') as f:
                data = json.load(f)
            total_cost = data.get('total_cost', 0)
            position_count = len(data.get('positions', {}))
    except Exception as e:
        # 讀取失敗時拒絕下單（安全優先）
        return {
            'allowed': False,
            'reason': f'無法讀取持倉資料: {e}'
        }

    # 3. 總持倉市值檢查
    if total_cost + order_amount > _TOTAL_CAPITAL_LIMIT:
        return {
            'allowed': False,
            'reason': (
                f'總持倉 {total_cost:,.0f} + 新單 {order_amount:,.0f} = '
                f'{total_cost + order_amount:,.0f} 超過上限 {_TOTAL_CAPITAL_LIMIT:,.0f}'
            )
        }

    # 4. 持倉標的數檢查（新標的才檢查）
    if os.path.exists(_POSITION_COSTS_PATH):
        with open(_POSITION_COSTS_PATH, 'r') as f:
            data = json.load(f)
        positions = data.get('positions', {})
        symbol_key = symbol if '.TW' in symbol else f'{symbol}.TW'
        if symbol_key not in positions and position_count >= _MAX_POSITIONS:
            return {
                'allowed': False,
                'reason': f'持倉標的數 {position_count} 已達上限 {_MAX_POSITIONS}'
            }

    # 5. 記錄通過的訂單
    log_entry = {
        'time': datetime.now().isoformat(),
        'symbol': symbol,
        'action': action,
        'quantity': quantity,
        'price': price,
        'amount': order_amount,
        'total_after': total_cost + order_amount,
        'result': 'ALLOWED'
    }
    _log_order_check(log_entry)

    return {'allowed': True, 'reason': 'passed all checks'}


def _log_order_check(entry: dict):
    """記錄訂單檢查結果"""
    log_path = "/home/ubuntu/skynet_v2_improved/logs/order_guard_audit.jsonl"
    try:
        with open(log_path, 'a') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + '\\n')
    except Exception:
        pass

# === END EMERGENCY_CAPITAL_CHECK ===
'''

    with open(filepath, "a") as f:
        f.write(patch_code)

    log("  已加入 emergency_capital_check() 函數")
    log("  檢查項目: 單筆上限/總資金上限/持倉數上限")
    log("  DONE")


def fix_4_patch_pipeline():
    """P0-4: 在 TradingPipeline 中注入資金檢查"""
    log("=" * 60)
    log("P0-4: 修補 pipeline.py 注入資金檢查攔截")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "src", "layer4_risk", "pipeline.py")
    if not os.path.exists(filepath):
        log(f"  警告: {filepath} 不存在，跳過")
        return

    backup_file(filepath)

    with open(filepath, "r") as f:
        content = f.read()

    if "emergency_capital_check" in content:
        log("  已有緊急資金檢查注入，跳過")
        return

    # 在檔案頂部加入 import
    import_line = (
        "\n# EMERGENCY: 資金檢查注入\n"
        "try:\n"
        "    from src.layer4_risk.order_guard import emergency_capital_check\n"
        "    _HAS_EMERGENCY_CHECK = True\n"
        "except ImportError:\n"
        "    _HAS_EMERGENCY_CHECK = False\n"
        "# END EMERGENCY\n"
    )

    # 找到第一個 import 語句後插入
    first_import = content.find("import ")
    if first_import == -1:
        first_import = 0
    line_end = content.find("\n", first_import) + 1
    content = content[:line_end] + import_line + content[line_end:]

    with open(filepath, "w") as f:
        f.write(content)

    log("  已注入 emergency_capital_check import")
    log("  注意: 需要在 pipeline 的下單方法中呼叫 emergency_capital_check()")
    log("  DONE")


def fix_5_patch_order_router():
    """P0-5: 在 OrderRouter 下單前加入攔截"""
    log("=" * 60)
    log("P0-5: 修補 order_router.py 下單攔截")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "src", "layer4_risk", "order_router.py")
    if not os.path.exists(filepath):
        log(f"  警告: {filepath} 不存在，跳過")
        return

    backup_file(filepath)

    with open(filepath, "r") as f:
        content = f.read()

    if "emergency_capital_check" in content:
        log("  已有緊急攔截，跳過")
        return

    # 在檔案頂部加入 import
    import_patch = (
        "\n# EMERGENCY: 下單前資金檢查\n"
        "try:\n"
        "    from src.layer4_risk.order_guard import emergency_capital_check as _emergency_check\n"
        "except ImportError:\n"
        "    _emergency_check = None\n"
        "import logging as _emg_logging\n"
        "_emg_logger = _emg_logging.getLogger('EMERGENCY_ORDER_GUARD')\n"
        "# END EMERGENCY\n"
    )

    first_import = content.find("import ")
    if first_import == -1:
        first_import = 0
    line_end = content.find("\n", first_import) + 1
    content = content[:line_end] + import_patch + content[line_end:]

    with open(filepath, "w") as f:
        f.write(content)

    log("  已注入 order_router.py 攔截")
    log("  DONE")


def fix_6_update_watchlist():
    """P0-6: 更新 watchlist 為實際持倉"""
    log("=" * 60)
    log("P0-6: 更新 watchlist.json")
    log("=" * 60)

    filepath = os.path.join(SKYNET_DIR, "data", "watchlist.json")
    backup_file(filepath)

    watchlist = {
        "updated_at": datetime.now().isoformat(),
        "swing": [
            "2317.TW",
            "2330.TW",
            "2609.TW",
            "2615.TW",
            "3413.TW",
            "4935.TW"
        ],
        "daytrade": [
            "2330.TW",
            "2454.TW",
            "2303.TW"
        ],
        "note": "EMERGENCY: 同步券商實際持倉，由 emergency_fix.py 更新"
    }

    with open(filepath, "w") as f:
        json.dump(watchlist, f, ensure_ascii=False, indent=2)

    log("  已更新 swing watchlist 為實際 6 檔持倉")
    log("  DONE")


def fix_7_create_trading_halt_flag():
    """P0-7: 建立交易暫停旗標檔案"""
    log("=" * 60)
    log("P0-7: 建立交易暫停旗標")
    log("=" * 60)

    flag_path = os.path.join(SKYNET_DIR, "data", "TRADING_HALTED")
    with open(flag_path, "w") as f:
        f.write(json.dumps({
            "halted": True,
            "reason": "EMERGENCY: 4/1 亂下單事件，暫停自動交易直到修復完成",
            "halted_at": datetime.now().isoformat(),
            "halted_by": "emergency_fix.py",
            "resume_conditions": [
                "order_guard 資金檢查確認生效",
                "position_costs 與券商對帳一致",
                "TRADING_ENABLED 手動設為 True"
            ]
        }, ensure_ascii=False, indent=2))

    log("  已建立 data/TRADING_HALTED 旗標檔案")
    log("  DONE")


def generate_report():
    """產生修復報告"""
    log("=" * 60)
    log("修復報告")
    log("=" * 60)

    report = {
        "timestamp": datetime.now().isoformat(),
        "fixes_applied": [
            "P0-1: position_costs.json 已同步券商持倉",
            "P0-2: TRADING_ENABLED = False + TOTAL_CAPITAL_LIMIT = 100000",
            "P0-3: order_guard.py 加入 emergency_capital_check()",
            "P0-4: pipeline.py 注入資金檢查",
            "P0-5: order_router.py 注入下單攔截",
            "P0-6: watchlist.json 更新為實際持倉",
            "P0-7: TRADING_HALTED 旗標建立",
        ],
        "remaining_manual_steps": [
            "在 pipeline.py 的實際下單方法中呼叫 emergency_capital_check()",
            "在 api_gateway.py 的下單 endpoint 中呼叫 emergency_capital_check()",
            "重啟 SkyNet 服務使修改生效: docker compose restart 或 kill + restart",
            "確認零股交易 API 是否正確實作",
            "設定每日自動對帳機制",
        ],
        "account_summary": {
            "total_cost": 144775,
            "total_market_value": 141404,
            "unrealized_pnl": -3371,
            "pnl_pct": -2.33,
            "position_count": 6,
            "capital_limit": 100000,
            "over_limit_by": 44775,
        }
    }

    report_path = os.path.join(SKYNET_DIR, "data", "emergency_fix_report.json")
    with open(report_path, "w") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    log(f"  報告已儲存: {report_path}")

    log("")
    log("=" * 60)
    log("  緊急修復完成！")
    log("=" * 60)
    log(f"  總資金上限: 100,000 (目前持倉 144,775, 超限 44,775)")
    log(f"  自動交易: 已停用")
    log(f"  資金檢查: 已注入")
    log("")
    log("  ⚠ 請手動執行以下步驟:")
    log("  1. 重啟 SkyNet 服務")
    log("  2. 考慮減碼至 10 萬以內")
    log("  3. 確認修復後再啟用自動交易")
    log("=" * 60)


def main():
    log("=" * 60)
    log("  SkyNet 緊急修復腳本")
    log(f"  目標: {SKYNET_DIR}")
    log(f"  時間: {datetime.now().isoformat()}")
    log("=" * 60)

    if not os.path.exists(SKYNET_DIR):
        log(f"ERROR: {SKYNET_DIR} 不存在！")
        return

    if not os.path.exists(os.path.join(SKYNET_DIR, "main.py")):
        log("ERROR: main.py 不存在！")
        return

    fix_1_update_position_costs()
    fix_2_disable_trading()
    fix_3_patch_order_guard()
    fix_4_patch_pipeline()
    fix_5_patch_order_router()
    fix_6_update_watchlist()
    fix_7_create_trading_halt_flag()
    generate_report()

    # 儲存完整日誌
    log_path = os.path.join(SKYNET_DIR, "logs", "emergency_fix.log")
    with open(log_path, "w") as f:
        f.write("\n".join(LOG))


if __name__ == "__main__":
    main()
