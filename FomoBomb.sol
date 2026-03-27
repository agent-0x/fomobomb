// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FomoBomb — FOMO 倒计时炸弹 + 随机大奖
 * @notice 每次投入 AXON 重置倒计时，倒计时走完最后投入的人赢奖池。
 *         每次投入还有 2% 概率赢走累积大奖池。
 *
 * 规则：
 * - 每局倒计时 100 个区块（约 10 分钟）
 * - 任何人可以投入 >= minBet 的 AXON
 * - 每次投入：5% 手续费，其中 3% 进大奖池，2% 进金库
 * - 95% 进当局奖池，投入后倒计时重置
 * - 倒计时走完 → 最后一个投入的人赢走当局奖池
 * - 每次投入有 2% 概率赢走整个大奖池（跨局累积）
 * - 领奖后下一个 bet() 自动开始新一局
 */
contract FomoBomb {
    // ============ 配置 ============
    address public owner;
    uint256 public countdown;       // 倒计时区块数（默认 100）
    uint256 public minBet;          // 最小投入（默认 1 AXON）
    uint256 public feeBps;          // 总手续费 bps（默认 500 = 5%）
    uint256 public jackpotBps;      // 大奖池占总投注额 bps（默认 300 = 3%，与 feeBps 独立计算）
    uint256 public jackpotChance;   // 中奖概率分母（默认 50 = 1/50 = 2%）

    // ============ 当局状态 ============
    uint256 public roundId;         // 当前局数
    uint256 public pool;            // 当局奖池
    uint256 public deadline;        // 截止区块号
    address public lastPlayer;      // 最后一个投入的人
    uint256 public lastBet;         // 最后一次投入金额
    uint256 public totalBets;       // 当局总投入次数
    bool public active;             // 是否有进行中的局

    // ============ 金库 + 大奖池 ============
    uint256 public treasury;        // 累计金库（2%）
    uint256 public jackpot;         // 大奖池（3%，跨局累积）

    // ============ 提款余额 (pull payment) ============
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public totalPending;

    // ============ 重入锁 ============
    bool private _locked;

    // ============ 全局计数 ============
    uint256 public globalBetCount;  // 全局投注计数（用于随机数）

    // ============ 历史 ============
    struct RoundResult {
        address winner;
        uint256 prize;
        uint256 totalBets;
        uint256 endBlock;
    }
    mapping(uint256 => RoundResult) public history;

    // ============ 大奖历史 ============
    struct JackpotResult {
        address winner;
        uint256 prize;
        uint256 atBlock;
        uint256 roundId;
    }
    uint256 public jackpotWins;
    mapping(uint256 => JackpotResult) public jackpotHistory;

    // ============ 事件 ============
    event NewRound(uint256 indexed roundId, uint256 deadline);
    event Bet(uint256 indexed roundId, address indexed player, uint256 amount, uint256 pool, uint256 newDeadline);
    event Win(uint256 indexed roundId, address indexed winner, uint256 prize);
    event JackpotWin(address indexed winner, uint256 prize, uint256 globalBetNum);
    event Withdraw(address indexed to, uint256 amount);
    event TreasuryWithdraw(address indexed to, uint256 amount);

    // ============ 修饰器 ============
    modifier noReentrant() {
        require(!_locked, "no reentrancy");
        _locked = true;
        _;
        _locked = false;
    }

    // ============ 构造函数 ============
    constructor(
        uint256 _countdown,
        uint256 _minBet,
        uint256 _feeBps,
        uint256 _jackpotBps,
        uint256 _jackpotChance
    ) {
        require(_feeBps <= 1000, "fee too high");
        require(_jackpotBps <= _feeBps, "jackpot > fee");
        require(_minBet > 0, "min bet must be > 0");
        require(_countdown > 0, "countdown must be > 0");
        require(_jackpotChance > 0, "chance must be > 0");
        owner = msg.sender;
        countdown = _countdown;
        minBet = _minBet;
        feeBps = _feeBps;
        jackpotBps = _jackpotBps;
        jackpotChance = _jackpotChance;
    }

    // ============ 核心：投入 ============
    function bet() external payable noReentrant {
        require(msg.value >= minBet, "below min bet");

        // 如果没有进行中的局，或者上一局已结束，开新局
        if (!active || (deadline > 0 && block.number >= deadline)) {
            _settleIfNeeded();
            _startNewRound();
        }

        // 扣手续费: jackpotBps 进大奖池, 剩余进金库
        uint256 totalFee = (msg.value * feeBps) / 10000;
        uint256 toJackpot = (msg.value * jackpotBps) / 10000;
        uint256 toTreasury = totalFee - toJackpot;
        uint256 toPool = msg.value - totalFee;

        jackpot += toJackpot;
        treasury += toTreasury;
        pool += toPool;

        // 更新状态
        lastPlayer = msg.sender;
        lastBet = msg.value;
        deadline = block.number + countdown;
        totalBets += 1;
        globalBetCount += 1;

        emit Bet(roundId, msg.sender, msg.value, pool, deadline);

        // 大奖抽奖
        _tryJackpot(msg.sender);
    }

    // ============ 领奖 ============
    function claim() external noReentrant {
        require(active, "no active round");
        require(block.number >= deadline, "not ended yet");
        require(lastPlayer != address(0), "no player");

        _settle();
    }

    // ============ 提取奖金 (pull payment) ============
    function withdraw() external noReentrant {
        _withdrawTo(msg.sender, msg.sender);
    }

    function withdrawTo(address payable recipient) external noReentrant {
        require(recipient != address(0), "zero address");
        _withdrawTo(msg.sender, recipient);
    }

    function _withdrawTo(address from, address recipient) internal {
        uint256 amount = pendingWithdrawals[from];
        require(amount > 0, "nothing to withdraw");
        pendingWithdrawals[from] = 0;
        totalPending -= amount;
        (bool ok, ) = recipient.call{value: amount}("");
        require(ok, "transfer failed");
        emit Withdraw(recipient, amount);
    }

    // ============ 查询 ============
    function status() external view returns (
        uint256 _roundId,
        uint256 _pool,
        uint256 _deadline,
        uint256 _blocksLeft,
        address _lastPlayer,
        uint256 _lastBet,
        uint256 _totalBets,
        bool _active,
        bool _claimable,
        uint256 _jackpot,
        uint256 _globalBetCount
    ) {
        _roundId = roundId;
        _pool = pool;
        _deadline = deadline;
        _blocksLeft = (active && deadline > 0 && block.number < deadline) ? deadline - block.number : 0;
        _lastPlayer = lastPlayer;
        _lastBet = lastBet;
        _totalBets = totalBets;
        _active = active;
        _claimable = active && deadline > 0 && block.number >= deadline;
        _jackpot = jackpot;
        _globalBetCount = globalBetCount;
    }

    // ============ 内部 ============
    function _startNewRound() internal {
        roundId += 1;
        pool = 0;
        deadline = block.number + countdown;
        lastPlayer = address(0);
        lastBet = 0;
        totalBets = 0;
        active = true;

        emit NewRound(roundId, deadline);
    }

    function _settleIfNeeded() internal {
        if (active && deadline > 0 && block.number >= deadline && lastPlayer != address(0)) {
            _settle();
        }
    }

    function _settle() internal {
        uint256 prize = pool;
        address winner = lastPlayer;
        uint256 settledRoundId = roundId;

        history[settledRoundId] = RoundResult({
            winner: winner,
            prize: prize,
            totalBets: totalBets,
            endBlock: deadline
        });

        pool = 0;
        deadline = 0;
        lastPlayer = address(0);
        lastBet = 0;
        totalBets = 0;
        active = false;

        pendingWithdrawals[winner] += prize;
        totalPending += prize;

        emit Win(settledRoundId, winner, prize);
    }

    function _tryJackpot(address player) internal {
        if (jackpot == 0) return;

        uint256 random = uint256(keccak256(abi.encodePacked(
            player,
            blockhash(block.number - 1),
            globalBetCount,
            block.timestamp
        )));

        if (random % jackpotChance == 0) {
            uint256 prize = jackpot;
            jackpot = 0;

            jackpotHistory[jackpotWins] = JackpotResult({
                winner: player,
                prize: prize,
                atBlock: block.number,
                roundId: roundId
            });
            jackpotWins += 1;

            pendingWithdrawals[player] += prize;
            totalPending += prize;

            emit JackpotWin(player, prize, globalBetCount);
        }
    }

    // ============ 管理 ============
    function withdrawTreasury() external noReentrant {
        require(msg.sender == owner, "not owner");
        uint256 amount = treasury;
        require(amount > 0, "empty treasury");
        treasury = 0;
        (bool ok, ) = owner.call{value: amount}("");
        require(ok, "transfer failed");
        emit TreasuryWithdraw(owner, amount);
    }

    function setCountdown(uint256 _countdown) external {
        require(msg.sender == owner, "not owner");
        require(!active, "round in progress");
        require(_countdown > 0, "countdown must be > 0");
        countdown = _countdown;
    }

    function setMinBet(uint256 _minBet) external {
        require(msg.sender == owner, "not owner");
        require(!active, "round in progress");
        require(_minBet > 0, "min bet must be > 0");
        minBet = _minBet;
    }

    function setFeeBps(uint256 _feeBps) external {
        require(msg.sender == owner, "not owner");
        require(!active, "round in progress");
        require(_feeBps <= 1000, "fee too high");
        require(jackpotBps <= _feeBps, "jackpot > fee");
        feeBps = _feeBps;
    }

    function setJackpotBps(uint256 _jackpotBps) external {
        require(msg.sender == owner, "not owner");
        require(!active, "round in progress");
        require(_jackpotBps <= feeBps, "jackpot > fee");
        jackpotBps = _jackpotBps;
    }

    function setJackpotChance(uint256 _jackpotChance) external {
        require(msg.sender == owner, "not owner");
        require(!active, "round in progress");
        require(_jackpotChance > 0, "chance must be > 0");
        jackpotChance = _jackpotChance;
    }

    function rescueSurplus() external {
        require(msg.sender == owner, "not owner");
        uint256 tracked = pool + treasury + jackpot + totalPending;
        uint256 balance = address(this).balance;
        require(balance > tracked, "no surplus");
        uint256 surplus = balance - tracked;
        (bool ok, ) = owner.call{value: surplus}("");
        require(ok, "transfer failed");
    }
}
