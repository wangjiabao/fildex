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

contract TokenTemplate is ERC20, AccessControlEnumerable, Initializable {
    using SafeMath for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    uint256 private  _cap;

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

    ITokenExchange public tokenExchange; 
    IDFIL public dfil; 
    IKey  public key;
    
    address public defaultAdmin;
    address payable public owner;
    address public controller;
    
    bool public mintToDefaultAdmin;

    address public callPair;
    uint256 public stageType;
    uint256 public stageTypeRate;
    uint256 public stageTypeBase;
    mapping(address => uint256) public stageRecords;

    uint256 public sellAmount;
    uint256 public depositAmount; 

    uint256 public startTime;
    uint256 public keyEndTime;

    string public logo;
    string public nameToken;
    uint64 public actor;

    bool public whiteEnable = true;
    mapping(address => bool) public white;

    EnumerableSet.AddressSet private _users;
    EnumerableSet.UintSet private _amounts;

    uint256 public rewardAll;

    ITokenBankReward public bank;
    IStake public stake;
    address public swapFactory;
    
    uint256 public stakeRewardCycle;

    EnumerableSet.AddressSet private _accountUnion;
    
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
        swapFactory = createData.swapFactory;
        callPair = createData.callPair;
        stageType = createData.stageType;
        stageTypeRate = createData.stageTypeRate;
        stageTypeBase = createData.stageTypeBase;

        tokenExchange.FILRECORDANDMINTDFIL(owner, _cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)).add(_cap.mul(depositRatePerToken).div(depositBasePerToken)), _cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)));

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

    function setWhiteEnable(bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        whiteEnable = enable;
    }

    function setWhite(address account, bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        white[account] = enable;
    }

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

    function ownerWithdraw(uint256 feeOffset) external {
        require(owner == _msgSender(), "Token: must owner");
        require(0 < sellAmount, "Token: amount must more than 0");

        uint256 tmpSellCostAmount = sellAmount.mul(costRatePerToken).div(costBasePerToken);
        uint256 tmpSellProfitAmount = sellAmount.mul(profitRatePerToken).div(profitBasePerToken);
        
        sellAmount = 0;

        dfil.approve(address(tokenExchange), tmpSellCostAmount.add(tmpSellProfitAmount));
        tokenExchange.WITHDRAWOWNERFIL(owner, tmpSellCostAmount, tmpSellProfitAmount, feeOffset);
    }

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

    function depositFilIn() payable external {
        require(controller == _msgSender(), "Token: must controller");
        require(_cap.mul(depositRatePerToken).div(depositBasePerToken) <= msg.value, "Token: not enough");
        
        depositAmount = depositAmount.add(msg.value);
        tokenExchange.FILIN{value: msg.value}(owner);
    }

    function setStake(address stake_) external {
        require(swapFactory == _msgSender(), "Token: must swap factory to set");
        stake = IStake(stake_);
    }

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

    function getStakeType() external view returns(uint256) {
        return stageType;
    }

    function getStageTypeRate() external view returns(uint256) {
        return stageTypeRate;
    }

    function getStageTypeBase() external view returns(uint256) {
        return stageTypeBase;
    }

    function getStageRecords(address user) external view returns(uint256) {
        return stageRecords[user];
    }

    function stakeRecord(address user, uint256 amount) external {
        require(callPair == _msgSender(), "Token: err caller");
        dfil.transferFrom(user, address(this), amount);
        stageRecords[user] = stageRecords[user].add(amount);
    }
    
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

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }

    function getAmounts() external view returns (uint256[] memory) {
        return _amounts.values();
    }
}