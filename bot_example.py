#!/usr/bin/env python3
"""FomoBomb 自动投注机器人示例 — 狙击策略"""
import json, subprocess, time
from eth_utils import keccak, to_checksum_address
from eth_account import Account

# ========== 配置 ==========
RPC = "https://mainnet-rpc.axonchain.ai/"
CONTRACT = "0xc90576a5e136be4a1842c6883c6fe6cb43e02325"
CHAIN_ID = 8210
PRIVATE_KEY = "你的私钥"  # 替换为你的私钥
SNIPE_BLOCKS = 5  # 剩余多少块时狙击
BET_AMOUNT = 1  # 每次投注 AXON 数量

MY_ADDRESS = Account.from_key(PRIVATE_KEY).address


def rpc(method, params):
    r = subprocess.run(["curl", "-s", RPC, "-X", "POST", "-H", "Content-Type: application/json",
        "-d", json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1})],
        capture_output=True, text=True)
    return json.loads(r.stdout)


def get_status():
    sel = keccak(b"status()")[:4].hex()
    r = rpc("eth_call", [{"to": CONTRACT, "data": "0x" + sel}, "latest"])
    raw = r["result"][2:]
    f = [int(raw[i:i+64], 16) for i in range(0, len(raw), 64)]
    return {
        "roundId": f[0],
        "pool": f[1] / 1e18,
        "deadline": f[2],
        "blocksLeft": f[3],
        "lastPlayer": "0x" + raw[4*64+24:5*64],
        "lastBet": f[5] / 1e18,
        "totalBets": f[6],
        "active": bool(f[7]),
        "claimable": bool(f[8]),
        "jackpot": f[9] / 1e18,
        "globalBetCount": f[10],
    }


def get_balance():
    r = rpc("eth_getBalance", [MY_ADDRESS, "latest"])
    return int(r["result"], 16) / 1e18


def get_pending():
    sel = keccak(b"pendingWithdrawals(address)")[:4].hex()
    pad = MY_ADDRESS[2:].lower().zfill(64)
    r = rpc("eth_call", [{"to": CONTRACT, "data": "0x" + sel + pad}, "latest"])
    return int(r["result"], 16) / 1e18


def send_tx(func_name, value_axon=0):
    sel = keccak(func_name.encode())[:4].hex()
    nonce = int(rpc("eth_getTransactionCount", [MY_ADDRESS, "latest"])["result"], 16)
    tx = {
        "nonce": nonce,
        "to": to_checksum_address(CONTRACT),
        "data": "0x" + sel,
        "value": int(value_axon * 1e18),
        "gas": 300000,
        "gasPrice": 1000000000,
        "chainId": CHAIN_ID,
    }
    signed = Account.sign_transaction(tx, PRIVATE_KEY)
    raw = signed.raw_transaction.hex()
    if not raw.startswith("0x"):
        raw = "0x" + raw
    return rpc("eth_sendRawTransaction", [raw]).get("result", "")


def bet(amount=BET_AMOUNT):
    return send_tx("bet()", amount)


def claim():
    return send_tx("claim()")


def withdraw():
    return send_tx("withdraw()")


def main():
    print(f"FomoBomb 狙击机器人启动")
    print(f"地址:     {MY_ADDRESS}")
    print(f"余额:     {get_balance():.4f} AXON")
    print(f"合约:     {CONTRACT}")
    print(f"狙击范围: 剩余 <= {SNIPE_BLOCKS} 块时投注")
    print(f"投注额:   {BET_AMOUNT} AXON")
    print()

    while True:
        try:
            # 检查待提取奖金
            pending = get_pending()
            if pending > 0:
                print(f"[提取] {pending:.4f} AXON 奖金")
                withdraw()
                time.sleep(10)
                continue

            s = get_status()

            # 局已结束 → 结算
            if s["claimable"]:
                print(f"[结算] 局 #{s['roundId']} 已结束")
                claim()
                time.sleep(10)
                continue

            # 无活跃局 → 跳过（等别人开局，或自己开）
            if not s["active"]:
                time.sleep(6)
                continue

            # 显示状态
            is_me = s["lastPlayer"].lower() == MY_ADDRESS.lower()
            marker = " (我)" if is_me else ""
            print(f"局 #{s['roundId']} | 奖池: {s['pool']:.2f} | "
                  f"剩余: {s['blocksLeft']} 块 | "
                  f"投注: {s['totalBets']} 次 | "
                  f"大奖: {s['jackpot']:.4f} | "
                  f"最后: {s['lastPlayer'][:8]}{marker}")

            # 狙击：倒计时快结束且最后投注人不是自己
            if 0 < s["blocksLeft"] <= SNIPE_BLOCKS and not is_me:
                bal = get_balance()
                if bal >= BET_AMOUNT + 0.1:
                    print(f"[狙击] 剩余 {s['blocksLeft']} 块，投注 {BET_AMOUNT} AXON")
                    tx = bet()
                    if tx:
                        print(f"  TX: {tx}")
                else:
                    print(f"[跳过] 余额不足: {bal:.4f} AXON")

        except Exception as e:
            print(f"[错误] {e}")

        time.sleep(6)  # 约一个区块


if __name__ == "__main__":
    main()
