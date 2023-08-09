//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/IKey.sol";
import "./interfaces/IStake.sol";
import "./interfaces/ITokenBankReward.sol";
import "./interfaces/ITokenTemplate.sol";
import "./interfaces/ITokenExchange.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenUnionTemplate is ERC20, AccessControlEnumerable, Initializable {
    using SafeMath for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    ITokenExchange public tokenExchange; 
    IDFIL public dfil; 
    IKey  public key;

    uint256 private  _cap;
    string public logo;
    string public nameToken;
    uint64 public actor;
    uint256 public startTime;
    uint256 public keyEndTime;
    bool public whiteEnable = true;
    mapping(address => bool) public white;

    uint256 public costRatePerToken;
    uint256 public costBasePerToken;
    uint256 public profitRatePerToken;
    uint256 public profitBasePerToken;
    uint256 public depositRatePerToken;
    uint256 public depositBasePerToken;
    uint256 public burnKeyRate;
    uint256 public burnKeyBase;

    uint256 public rewardOwnerRate;
    uint256 public rewardOwnerBase;
    uint256 public rewardRate; 
    uint256 public rewardBase;
    uint256 public rewardBankRate; 
    uint256 public rewardBankBase;

    address public defaultAdmin;
    bool public mintToDefaultAdmin;
    address payable public owner;
    address public controller;

    uint256 public totalAmount;
    EnumerableSet.AddressSet private _accountUnion;
    mapping(address => uint256) public accountUnionAmount;

    EnumerableSet.AddressSet private _users;
    EnumerableSet.UintSet private _amounts;
    uint256 public sellAmount;
    mapping(address => uint256) public sellAmounts;
    uint256 public depositAmount; 

    address public callPair;
    uint256 public stageType;
    uint256 public stageTypeRate;
    uint256 public stageTypeBase;
    mapping(address => uint256) public stageRecords;

    ITokenBankReward public bank;
    IStake public stake;
    address public swapFactory;
    uint256 public stakeRewardCycle;
    uint256 public rewardAll;
    
    event ExchangeToken(address indexed account, uint256 amount);

    constructor() ERC20("Token", "T") {
        _disableInitializers();
    }

    function initialize(ITokenTemplate.CreateData calldata createData) initializer public {
        require(createData.cap_ > 0, "Token: cap is 0");

        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, createData.superAdmin);
        _grantRole(ADMIN_ROLE, createData.defaultAdmin);
        _grantRole(OWNER_ROLE, createData.owner_);

        _cap = createData.cap_;
        defaultAdmin = createData.defaultAdmin;
        owner = createData.owner_;
        dfil = IDFIL(createData.dfil_);
        key = IKey(createData.key_);
        tokenExchange = ITokenExchange(createData.tokenExchange_);
        bank = ITokenBankReward(createData.bank_);
        actor = createData.actor_;
        startTime = block.timestamp;
        keyEndTime =  startTime + 24*3600;
        nameToken = createData.name_;
        logo = createData.logo_;
        burnKeyRate = createData.burnKeyRate;
        burnKeyBase = createData.burnKeyBase;
        costRatePerToken = createData.costRatePerToken;
        costBasePerToken = createData.costBasePerToken;
        profitRatePerToken = createData.profitRatePerToken;
        profitBasePerToken = createData.profitBasePerToken;
        depositRatePerToken = createData.depositRatePerToken;
        depositBasePerToken = createData.depositBasePerToken;
        controller = createData.controller;
        callPair = createData.callPair;
        stageType = createData.stageType;
        stageTypeRate = createData.stageTypeRate;
        stageTypeBase = createData.stageTypeBase;

        totalAmount = _cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)).add(_cap.mul(depositRatePerToken).div(depositBasePerToken));
        require(totalAmount <= tokenExchange.getAllowAccountUnionAmountTotal(), "Token: Insufficient fil balance");
       
        uint256 tmpAmount = totalAmount;
        for (uint256 i = 0; i < tokenExchange.getAllowAccountUnionLength(); i++) {
            if (i < tokenExchange.getAllowAccountUnionLength() - 1) { 
                tmpAmount = tmpAmount.sub(tokenExchange.getAllowAccountUnionAmount(tokenExchange.getAllowAccountUnionAt(i)).mul(totalAmount).div(tokenExchange.getAllowAccountUnionAmountTotal()));
                tokenExchange.FILLOCK(tokenExchange.getAllowAccountUnionAt(i), tokenExchange.getAllowAccountUnionAmount(tokenExchange.getAllowAccountUnionAt(i)).mul(totalAmount).div(tokenExchange.getAllowAccountUnionAmountTotal()), tokenExchange.getAllowAccountUnionAmount(tokenExchange.getAllowAccountUnionAt(i)).mul(_cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken))).div(tokenExchange.getAllowAccountUnionAmountTotal()));
                accountUnionAmount[tokenExchange.getAllowAccountUnionAt(i)] = tokenExchange.getAllowAccountUnionAmount(tokenExchange.getAllowAccountUnionAt(i)).mul(totalAmount).div(tokenExchange.getAllowAccountUnionAmountTotal());
            } else {
                tokenExchange.FILLOCK(tokenExchange.getAllowAccountUnionAt(i), tmpAmount, tokenExchange.getAllowAccountUnionAmount(tokenExchange.getAllowAccountUnionAt(i)).mul(_cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken))).div(tokenExchange.getAllowAccountUnionAmountTotal()));
                accountUnionAmount[tokenExchange.getAllowAccountUnionAt(i)] = tmpAmount;
            }

            _accountUnion.add(tokenExchange.getAllowAccountUnionAt(i));
        }

        rewardOwnerRate = createData.rewardOwnerRate;
        rewardOwnerBase = createData.rewardOwnerBase;
        rewardRate = createData.rewardRate; 
        rewardBase = createData.rewardBase;
        rewardBankRate = createData.rewardBankRate; 
        rewardBankBase = createData.rewardBankBase;
        // todo 
        stakeRewardCycle = 86400;
        // stakeRewardCycle = 604800;
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    /** 
     * @dev See {ERC20-_mint}.
     */
    function _mint(address account, uint256 amount) internal override {
        require(ERC20.totalSupply() + amount <= cap(), "Token: cap exceeded");
        super._mint(account, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        require(!whiteEnable || white[from] || white[to], "Token: not exists white");
        super._transfer(from, to, amount);
    }

    /**
     * 当前用户是否为此算力代币的联合节点商
     */
    function existsAccountUnion() external view returns (bool) {
        return _accountUnion.contains(_msgSender());
    }

    /**
     * 一级市场交易
     */
    function exchangeToken(uint256 amount) external {
        require(block.timestamp >= startTime, "Token: not open");
        require(100 < amount, "Token: amount must more than 100");

        dfil.transferFrom(_msgSender(), address(this), amount.mul(costRatePerToken).div(costBasePerToken).add(amount.mul(profitRatePerToken).div(profitBasePerToken)));
        sellAmount = sellAmount.add(amount);
        _mint(_msgSender(), amount);
        if (!mintToDefaultAdmin) {   
            _mint(defaultAdmin, 1024*1024*1024); // 1gb增发一次
            mintToDefaultAdmin = true;
        }

        if (block.timestamp <= keyEndTime) {
            key.burnFrom(_msgSender(), amount.mul(costRatePerToken).div(costBasePerToken).add(amount.mul(profitRatePerToken).div(profitBasePerToken)).mul(burnKeyRate).div(burnKeyBase));
        }
        
        _users.add(_msgSender());
        _amounts.add(amount);
        emit ExchangeToken(_msgSender(), amount);
    }

    /**
     * 一级市场交易用户
     */
    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }

    /**
     * 一级市场交易总金额
     */
    function getAmounts() external view returns (uint256[] memory) {
        return _amounts.values();
    }

    /**
     * 节点商提现
     */
    function ownerUnionWithdraw(uint256 feeOffset) external {
        require(_accountUnion.contains(_msgSender()), "Token: err withdraw owner");
        require(0 < sellAmount.sub(sellAmounts[_msgSender()]), "Token: amount must more than 0");

        uint256 tmpSellProfitAmount = sellAmount.sub(sellAmounts[_msgSender()]).mul(profitRatePerToken).div(profitBasePerToken);
        
        sellAmounts[_msgSender()] = sellAmount;

        dfil.approve(address(tokenExchange), tmpSellProfitAmount);
        tokenExchange.WITHDRAWFIL(owner, tmpSellProfitAmount, feeOffset);
    }

    /**
     * 发行商提现
     */
    function tokenUnionProposerUnionWithdraw(uint256 feeOffset) external {
        require(owner == _msgSender(), "Token: err withdraw owner");
        require(0 < sellAmount.sub(sellAmounts[_msgSender()]), "Token: amount must more than 0");

        uint256 tmpSellCostAmount = sellAmount.sub(sellAmounts[_msgSender()]).mul(costRatePerToken).div(costBasePerToken);
        uint256 tmpSellDepositAmount = sellAmount.sub(sellAmounts[_msgSender()]).mul(depositRatePerToken).div(depositBasePerToken);
        
        sellAmounts[_msgSender()] = sellAmount;

        dfil.approve(address(tokenExchange), tmpSellCostAmount.add(tmpSellDepositAmount));
        tokenExchange.WITHDRAWFIL(owner, tmpSellCostAmount.add(tmpSellDepositAmount), feeOffset);
    }

    /**
     * 质押类型
     */
    function getStakeType() external view returns (uint256) {
        return stageType;
    }

    /**
     * 质押类型对应的计算数据
     */
    function getStageTypeRate() external view returns (uint256) {
        return stageTypeRate;
    }

    /**
     * 质押类型对应的计算数据
     */
    function getStageTypeBase() external view returns (uint256) {
        return stageTypeBase;
    }

    /**
     * 质押记录
     */
    function getStageRecords(address user) external view returns (uint256) {
        return stageRecords[user];
    }

    /**
     * 质押（二级市场质押时，根据类型质押的额外的金额在此合约留存）
     */
    function stakeRecord(address user, uint256 amount) external {
        require(callPair == _msgSender(), "Token: err caller");
        dfil.transferFrom(user, address(this), amount);
        stageRecords[user] = stageRecords[user].add(amount);
    }
    
    /**
     * 解押
     */
    function unStakeRecord(address user, uint256 amount) external {
        require(callPair == _msgSender(), "Token: err caller");
        if (amount >= stageRecords[user]) {
            amount = stageRecords[user];
        }

        stageRecords[user] = stageRecords[user].sub(amount);

        if (amount >= dfil.balanceOf(address(this))) {
            amount = dfil.balanceOf(address(this));
        }
        
        dfil.transfer(user, amount);
    }

    /**
     * 被控制合约调用，设置分红数据，接收分红fil，部分转化dfil，分发等
     */
    function setReward() payable external {
        require(controller == _msgSender(), "Token: must controller to set");
        require(block.timestamp > stake.getStakingFinishTime(), "Token: must finish last reward");
        require(100 < msg.value, "Token: balance must more than 100");
        // 维护费fil给owner
        owner.transfer(msg.value.mul(rewardOwnerRate).div(rewardOwnerBase));
        // fil to dfil 质押设置奖励速率和周期，金库设置奖励速率和周期。
        tokenExchange.REWARDFIL2DFIL{value: msg.value.mul(rewardRate).div(rewardBase).add(msg.value.mul(rewardBankRate).div(rewardBankBase))}(owner);
        stake.setRewardRateAndStakingFinishTime(msg.value.mul(rewardRate).div(rewardBase).div(stakeRewardCycle), stakeRewardCycle);
        rewardAll = rewardAll + msg.value.mul(rewardRate).div(rewardBase);
        dfil.transfer(address(bank), msg.value.mul(rewardBankRate).div(rewardBankBase));
        bank.setCurrentReward(msg.value.mul(rewardBankRate).div(rewardBankBase));
    }

    /**
     * 被控制合约调用，抵押币归还，接收抵押币fil，设置流动性恢复等
     */
    function depositFilIn() payable external {
        require(controller == _msgSender(), "Token: must controller");
        require(_cap.mul(depositRatePerToken).div(depositBasePerToken) <= msg.value, "Token: not enough");
        
        depositAmount = depositAmount.add(msg.value);
        for (uint256 i = 0; i < _accountUnion.length() - 1; i++) {
           tokenExchange.FILIN{value: accountUnionAmount[_accountUnion.at(i)].mul(msg.value).div(totalAmount)}(_accountUnion.at(i));
        }
    }

    /**
     * 二级市场pair合约调用，用户收益提取
     */
    function withdrawReward(address to, uint256 amount) external {
        require(address(stake) == _msgSender() && rewardAll > 0, "Token: err withdraw");
        uint256 tmpAll = rewardAll;
        if (amount > tmpAll) {
            rewardAll = 0;
            dfil.transfer(to, tmpAll);
        } else {   
            rewardAll = tmpAll - amount;
            dfil.transfer(to, amount);
        }
    }

    // swapFactory
    function setStake(address stake_) external {
        require(swapFactory == _msgSender(), "Token: must swap factory to set");
        stake = IStake(stake_);
    }

    // admin
    function setWhiteEnable(bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        whiteEnable = enable;
    }

    function setWhite(address account, bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        white[account] = enable;
    }
}