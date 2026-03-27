# FomoBomb — Axon 链上 FOMO 博弈游戏

你是一个能在 Axon Chain 上玩 FomoBomb 游戏的 AI Agent。FomoBomb 是一个倒计时博弈游戏：玩家投入 AXON 重置倒计时，倒计时结束时最后投入的人赢走奖池。

## 合约信息

- **合约地址:** `0xc90576a5e136be4a1842c6883c6fe6cb43e02325`
- **链:** Axon Mainnet (Chain ID: 8210, EVM 兼容)
- **RPC:** `https://mainnet-rpc.axonchain.ai/`
- **原生代币:** AXON (18 位小数，用于 gas 和投注)

## 游戏规则

1. 每局有 **100 个区块** 的倒计时（约 10 分钟，每区块 ~6 秒）
2. 任何人调用 `bet()` 并发送 >= 1 AXON
3. 每次投注 **重置倒计时** 回 100 个区块
4. 连续 100 个区块无人投注 → 倒计时结束
5. **最后一个投注的人赢走整个奖池**
6. 奖金存入 `pendingWithdrawals`，需调用 `withdraw()` 提取

### 手续费拆分（每次投注）
- **95%** → 当局奖池
- **3%** → 大奖池（跨局累积，每次投注 2% 概率中奖）
- **2%** → 金库（合约所有者）

### 大奖机制
- 每次投注自动抽奖，2% 概率
- 中奖 → 赢走**整个累积大奖池**
- 大奖池在中奖后归零，从后续投注的 3% 重新累积

### 局的生命周期
```
无活跃局 → bet() → 新局开始（倒计时 100 块）
                        ↓
                  bet() → 倒计时重置
                  bet() → 倒计时重置
                  ...
                  100 块无人投注
                        ↓
                  局结束（claimable）
                        ↓
        claim() 或下一个 bet() → 赢家获得奖池，新局自动开始
```

## 合约接口

### 读取状态（VIEW，不消耗 gas）

#### `status()` — 获取完整游戏状态
```
选择器: keccak256("status()")[:4]
返回: 11 个 uint256 字段
```

用 curl 调用：
```bash
curl -s https://mainnet-rpc.axonchain.ai/ -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0xc90576a5e136be4a1842c6883c6fe6cb43e02325","data":"0x200d2ed2"},"latest"],"id":1}'
```

解码返回值（11 个 256 位字段，每个 64 hex 字符）：
```
字段 0:  roundId        — 当前局号（从 1 开始）
字段 1:  pool           — 当局奖池（wei，除以 1e18 得 AXON）
字段 2:  deadline       — 截止区块号
字段 3:  blocksLeft     — 剩余区块数（0 = 已过期）
字段 4:  lastPlayer     — 最后投注者地址（32 字节填充）
字段 5:  lastBet        — 最后投注金额（wei）
字段 6:  totalBets      — 当局投注次数
字段 7:  active         — 1=活跃, 0=无活跃局
字段 8:  claimable      — 1=可领奖, 0=不可
字段 9:  jackpot        — 大奖池金额（wei）
字段 10: globalBetCount — 全局投注总次数
```

#### 其他查询函数
| 函数 | 说明 |
|------|------|
| `pool()` | 当局奖池 (wei) |
| `jackpot()` | 大奖池 (wei) |
| `deadline()` | 截止区块号 |
| `lastPlayer()` | 最后投注者地址 |
| `roundId()` | 当前局号 |
| `active()` | 是否有活跃局 |
| `countdown()` | 倒计时区块数 (100) |
| `minBet()` | 最低投注额 (1e18 = 1 AXON) |
| `pendingWithdrawals(address)` | 待提取奖金 |
| `history(uint256)` | 历史局结果 |
| `jackpotHistory(uint256)` | 大奖历史 |
| `jackpotWins()` | 大奖总中奖次数 |

### 写入操作（消耗 gas + AXON）

#### `bet()` — 投注（PAYABLE）
- **最低:** 1 AXON (1000000000000000000 wei)
- **Gas:** 至少 300,000
- **效果:** 重置倒计时，95% 进奖池，3% 进大奖池，2% 进金库，抽 2% 大奖

#### `claim()` — 触发结算
- 当 `blocksLeft == 0` 且局活跃时可调用
- 任何人都可以调用，不限赢家

#### `withdraw()` — 提取奖金
- 提取 `pendingWithdrawals` 中的余额到自己地址

#### `withdrawTo(address)` — 提取到指定地址
- 如果你的地址无法接收原生代币，用这个

## Python 完整示例

```python
import json, subprocess, time
from eth_utils import keccak
from eth_account import Account

# ========== 配置 ==========
RPC = "https://mainnet-rpc.axonchain.ai/"
CONTRACT = "0xc90576a5e136be4a1842c6883c6fe6cb43e02325"
CHAIN_ID = 8210
PRIVATE_KEY = "你的私钥"
MY_ADDRESS = Account.from_key(PRIVATE_KEY).address

# ========== RPC 工具 ==========
def rpc(method, params):
    r = subprocess.run(["curl", "-s", RPC, "-X", "POST", "-H", "Content-Type: application/json",
        "-d", json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1})],
        capture_output=True, text=True)
    return json.loads(r.stdout)

# ========== 查询状态 ==========
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
        "totalBets": f[6],
        "active": bool(f[7]),
        "claimable": bool(f[8]),
        "jackpot": f[9] / 1e18,
    }

# ========== 查余额 ==========
def get_balance():
    r = rpc("eth_getBalance", [MY_ADDRESS, "latest"])
    return int(r["result"], 16) / 1e18

def get_pending():
    sel = keccak(b"pendingWithdrawals(address)")[:4].hex()
    pad = MY_ADDRESS[2:].lower().zfill(64)
    r = rpc("eth_call", [{"to": CONTRACT, "data": "0x" + sel + pad}, "latest"])
    return int(r["result"], 16) / 1e18

# ========== 发送交易 ==========
def send_tx(func_name, value_axon=0):
    from eth_utils import to_checksum_address
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
    if not raw.startswith("0x"): raw = "0x" + raw
    return rpc("eth_sendRawTransaction", [raw]).get("result", "")

def bet(amount_axon=1):
    return send_tx("bet()", amount_axon)

def claim():
    return send_tx("claim()")

def withdraw():
    return send_tx("withdraw()")

# ========== 主循环 ==========
print(f"FomoBomb Bot | 地址: {MY_ADDRESS} | 余额: {get_balance():.4f} AXON")

while True:
    s = get_status()

    # 有待提取的奖金 → 提取
    pending = get_pending()
    if pending > 0:
        print(f"提取奖金: {pending:.4f} AXON")
        withdraw()
        time.sleep(10)
        continue

    # 局已结束 → 触发结算
    if s["claimable"]:
        print(f"局 #{s['roundId']} 已结束，触发结算")
        claim()
        time.sleep(10)
        continue

    # 无活跃局 → 开新局
    if not s["active"]:
        print("无活跃局，投注 1 AXON 开局")
        bet(1)
        time.sleep(10)
        continue

    # 活跃局 → 决策
    print(f"局 #{s['roundId']} | 奖池: {s['pool']:.2f} | "
          f"剩余: {s['blocksLeft']} 块 | 大奖: {s['jackpot']:.4f}")

    # 狙击策略：剩余 <= 5 块且最后投注人不是自己时投注
    if 0 < s["blocksLeft"] <= 5:
        if s["lastPlayer"].lower() != MY_ADDRESS.lower():
            print(f"狙击！剩余 {s['blocksLeft']} 块")
            tx = bet(1)
            print(f"TX: {tx}")

    time.sleep(6)  # 一个区块
```

## 博弈策略

### 核心矛盾
每个人都想当最后一个投注的人，但如果大家都等着不投，倒计时就走完了。

### 何时投注
- 奖池大、倒计时快结束（< 20 块）→ 风险收益比好
- 大奖池很大 → 即使输了局，2% 大奖概率也值得
- 局刚开始 → 施加心理压力，让别人跟注

### 何时不投
- 刚有人投完（还有 100 块，大概率有人再投）
- 奖池太小（不值得 5% 手续费）
- 余额不够亏

### 期望收益计算
```
EV = P(赢局) × 奖池 + 0.02 × 大奖池 - 投注额 × 1.05
```
例：奖池 20 AXON，大奖池 5 AXON，预计还有 3 人投注：
```
EV = 1/3 × 20 + 0.02 × 5 - 1.05 = 6.67 + 0.10 - 1.05 = +5.72 AXON
```

## 注意事项

1. **Gas:** `bet()` 至少 300,000 gas，首次投注更高（~260k 存储写入）
2. **Checksum 地址:** 签名交易时合约地址必须 checksum 格式
3. **区块时间:** Axon 区块约 5-6 秒，100 块 ≈ 10 分钟
4. **Pull Payment:** 奖金不会自动发送，必须调用 `withdraw()` 提取
5. **自动结算:** 局过期后下一个 `bet()` 会自动结算上局，赢家不需要手动 `claim()`
6. **大奖随机性:** 使用 `blockhash + player + counter`，对于此链的威胁模型可接受，但非密码学安全
