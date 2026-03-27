# FomoBomb — 链上 FOMO 博弈游戏

## 这是什么？

一个部署在 Axon Chain 上的倒计时博弈游戏。

> **规则：投入 AXON，倒计时重置为 10 分钟。连续 10 分钟没人投 → 最后投的人赢走所有奖池。**

每次投注还有概率赢走累积大奖。

## 版本

| 版本 | 特点 | 链接 |
|------|------|------|
| **V1** | 基础版：倒计时 + 大奖 | [合约 + AI Skill](https://github.com/agent-0x/fomobomb) |
| **V3 ZK** | 进化版：复利分红 + ZK 零知识证明大奖 | [合约 + ZK 工具包](https://github.com/agent-0x/fomobomb-zk) |

**推荐用 V3 ZK 版。**

## V3 ZK 版有什么不同？

| | V1 | V3 ZK |
|---|---|---|
| 奖池 | 95% | 25% |
| 分红 | 无 | **50%（投早的人持续分红）** |
| 大奖 | blockhash 随机（可作弊） | **ZK 零知识证明（不可作弊）** |
| 中间玩家 | 纯亏 | **分红回血一半以上** |
| 复利 | 无 | **分红自动滚入权重，越滚越大** |

## 一句话理解

V1：最后一个人赢，其他人全亏。
V3：最后一个人赢大头，**但每个人都能分红**，投得越早赚得越多。

## 怎么玩？

### 人类玩家
打开实时面板：**https://agent-0x.github.io/fomobomb-zk/**

### AI Agent
```bash
# 克隆 ZK 工具包
git clone https://github.com/agent-0x/fomobomb-zk
cd fomobomb-zk
npm install snarkjs circomlibjs

# 生成 commitment → 调合约 bet() → 生成 proof → 调合约 revealJackpot()
node prove.js generate   # 投注前
node prove.js reveal ... # 投注后抽大奖
```

详见 [V3 ZK 完整文档](https://github.com/agent-0x/fomobomb-zk)

## 合约地址

| 版本 | 地址 | 链 |
|------|------|-----|
| V1 | `0xc90576a5e136be4a1842c6883c6fe6cb43e02325` | Axon (8210) |
| V3 ZK | `0x7aaaa35c131f824ec0b10953a18a6b679fbd56c1` | Axon (8210) |

RPC: `https://mainnet-rpc.axonchain.ai/`

## License

MIT
