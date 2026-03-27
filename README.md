# FomoBomb — Axon 链上 FOMO 博弈游戏 AI Skill

让 AI Agent 学会玩 FomoBomb：一个部署在 Axon Chain 上的倒计时博弈游戏。

## 游戏简介

FomoBomb 是一个链上 FOMO 倒计时炸弹游戏。玩家投入 AXON 代币重置倒计时，倒计时结束时最后一个投入的人赢走整个奖池。每次投入还有 2% 概率赢走跨局累积的大奖池。

**合约地址:** `0xc90576a5e136be4a1842c6883c6fe6cb43e02325`
**链:** Axon Mainnet (Chain ID: 8210)
**RPC:** `https://mainnet-rpc.axonchain.ai/`

## 作为 Claude Code Skill 使用

将 `skill.md` 放入你的 Claude Code skills 目录：

```bash
# 全局安装
cp skill.md ~/.claude/skills/fomobomb.md

# 或项目级安装
cp skill.md .claude/skills/fomobomb.md
```

然后在 Claude Code 中使用：
```
/fomobomb 查看当前游戏状态
/fomobomb 投注 1 AXON
/fomobomb 领取奖金
```

## 游戏规则

| 参数 | 值 |
|------|-----|
| 倒计时 | 100 个区块（约 10 分钟） |
| 最低投注 | 1 AXON |
| 手续费 | 5%（3% 大奖池 + 2% 金库） |
| 大奖概率 | 每次投注 2% |
| 结算方式 | Pull payment（需手动提取） |

## 博弈策略

核心矛盾：**每个人都想当最后一个投注的人，但如果大家都等着，倒计时就走完了。**

- **狙击策略：** 在倒计时最后几个区块投注
- **心理博弈：** 大奖池越大，越多人愿意投注"赌一把"
- **EV 计算：** `期望收益 = 赢奖池概率 × 奖池 + 0.02 × 大奖池 - 投注额`

## 文件说明

| 文件 | 说明 |
|------|------|
| `skill.md` | Claude Code Skill 定义文件 |
| `FomoBomb.sol` | Solidity 合约源码（已通过 Codex 5 轮审计） |
| `bot_example.py` | 完整的自动投注机器人示例 |

## License

MIT
