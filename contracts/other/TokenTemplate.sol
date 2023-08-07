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

    ITokenBankReward public bank;
    uint256 public stakeRewardCycle;
    bool public confirmStakeLimit;
    bool public confirmAgainStakeLimit;
    IStake public stake;

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

        require(_cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)).add(_cap.mul(depositRatePerToken).div(depositBasePerToken)) <= tokenExchange.getTokenOwnerFilBalance(owner).toUint256(), "Token: Insufficient fil balance");
        tokenExchange.FILLOCK(owner, _cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)).add(_cap.mul(depositRatePerToken).div(depositBasePerToken)), _cap.mul(costRatePerToken).div(costBasePerToken).add(_cap.mul(profitRatePerToken).div(profitBasePerToken)));

        confirmStakeLimit = true; 
        confirmAgainStakeLimit = true; 
        rewardOwnerRate = 20;
        rewardOwnerBase = 100;
        rewardRate = 75; 
        rewardBase = 100;
        rewardBankRate = 5; 
        rewardBankBase = 100;
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

    function exchangeToken(uint256 amount) external {
        require(block.timestamp >= startTime, "Token: not open");
        require(100 < amount, "Token: amount must more than 100");

        dfil.transferFrom(_msgSender(), address(this), amount.mul(costRatePerToken).div(costBasePerToken).add(amount.mul(profitRatePerToken).div(profitBasePerToken)));
        sellAmount = sellAmount.add(amount);
        _mint(_msgSender(), amount);
        if (!mintToDefaultAdmin) {   
            _mint(defaultAdmin, 100000);
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
        uint256 tmpSellDepositAmount = sellAmount.mul(depositRatePerToken).div(depositBasePerToken);
        
        sellAmount = 0;

        dfil.approve(address(tokenExchange), tmpSellCostAmount.add(tmpSellProfitAmount));
        tokenExchange.WITHDRAWOWNERFIL(owner, tmpSellCostAmount, tmpSellProfitAmount, tmpSellDepositAmount, feeOffset);
    }

    function setWhiteEnable(bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        whiteEnable = enable;
    }

    function setWhite(address account, bool enable) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        white[account] = enable;
    }

    function setReward() payable external {
        require(controller == _msgSender(), "Token: must controller to set");
        require(block.timestamp > stake.getStakingFinishTime(), "Token: must finish last reward");
        require(100 < msg.value, "Token: balance must more than 100");

        owner.transfer(msg.value.mul(rewardOwnerRate).div(rewardOwnerBase));
        tokenExchange.REWARDFIL2DFIL{value: msg.value.mul(rewardRate).div(rewardBase)}(owner);
        dfil.transfer(address(bank), msg.value.mul(rewardBankRate).div(rewardBankBase));
        bank.setCurrentReward(msg.value.mul(rewardBankRate).div(rewardBankBase));
        stake.setRewardRateAndStakingFinishTime(msg.value.mul(rewardRate).div(rewardBase).div(stakeRewardCycle), stakeRewardCycle);
    }

    function depositFilIn() payable external {
        require(controller == _msgSender(), "Token: must controller");
        require(_cap.mul(depositRatePerToken).div(depositBasePerToken) <= msg.value, "Token: not enough");
        
        depositAmount = depositAmount.add(msg.value);
        tokenExchange.FILIN{value: msg.value}(owner);
    }

    function setStake(address stake_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        if (confirmStakeLimit || confirmAgainStakeLimit) {
            stake = IStake(stake_);
        }
    }

    function confirmStake() external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        confirmStakeLimit = false;
    }

    function confirmAgainStake() external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        confirmAgainStakeLimit = false;
    }

    function setRate(
        uint256 rewardOwnerRate_,
        uint256 rewardOwnerBase_,
        uint256 rewardRate_, 
        uint256 rewardBase_,
        uint256 rewardBankRate_, 
        uint256 rewardBankBase_
    ) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "Token: must have admin role to set");
        rewardOwnerRate = rewardOwnerRate_;
        rewardOwnerBase = rewardOwnerBase_;
        rewardRate = rewardRate_; 
        rewardBase = rewardBase_;
        rewardBankRate = rewardBankRate_; 
        rewardBankBase = rewardBankBase_;
    }

    function withdrawReward(address to, uint256 amount) external {
        require(address(stake) == _msgSender(), "Token: sender must stake contract");
        dfil.transfer(to, amount);
    }

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }

    function getAmounts() external view returns (uint256[] memory) {
        return _amounts.values();
    }
}