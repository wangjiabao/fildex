//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ISTFIL.sol";
import "./interfaces/ISTFILToken.sol";
import "./interfaces/IWithdrawStfil.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ManagerFil is AccessControlEnumerable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");

    uint256 public defaultAdminRoleLimit;

    ISTFIL public stfil;
    ISTFILToken public stfilToken;
    address payable public exchange;
    IWithdrawStfil public withdrawStfil;

    uint256 public payAll; // 最新质押金额
    uint256 public lastReward; // 上次结算后全部利润总额

    uint256 public rewardAll; // 用户总利润
    uint256 public witdhrawRewardAll; // 用户的已提现利润（+当前stfil余额=全部利润总额）

    uint256 public feeRewardAll; // fee总利润
    uint256 public feeWithdrawRewardAll; // fee已提现总利润

    address payable public feeTo;
    uint256 public rewardFeeRate = 1000;
    uint256 public rewardFeeBase = 10000;

    event payCompleted(uint256 amount, uint256 payAll);
    event rePayCompleted(uint256 amount, uint256 payAll);
    event rewardCompleted(uint256 allReward, uint256 feeRewardAll, uint256 rewardAll, uint256 currentReward);
    event withdrawRewardCompleted(address indexed to, uint256 rewardAll, uint256 witdhrawRewardAll, uint256 amount);
    event feeWithdrawRewardCompleted(address indexed to, uint256 feeRewardAll, uint256 feeWitdhrawRewardAll, uint256 amount);

    modifier onlyDefaultAdminRole() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ManagerFil: must have default admin role to set");
        _;
    }

    modifier onlySuperAdminRole() {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "ManagerFil: must have super admin role to set");
        _;
    }

    constructor(address stfil_, address stfilToken_, address payable exchange_, address payable feeTo_) {
        stfil = ISTFIL(stfil_);
        stfilToken = ISTFILToken(stfilToken_);
        exchange = exchange_;
        feeTo = feeTo_;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
    }

    function pay() payable external {
        require(exchange == _msgSender(), "ManagerFil: not enough");
        stfil.stake{value: msg.value}(address(this), 0);
        payAll = payAll.add(msg.value);

        emit payCompleted(msg.value, payAll);
    }

    function repay(uint256 amount) external nonReentrant {
        require(exchange == _msgSender() && amount <= payAll, "ManagerFil: not enough");
        payAll = payAll.sub(amount);
        stfil.unstake(amount, exchange);

        emit rePayCompleted(amount, payAll);
    }

    function reward() external {
        // 历史总利润=(当前余额减掉兑换器的成本部分(即剩余未提利润))+已提现利润(fee和用户)
        uint256 allReward = stfilToken.balanceOf(address(this)).sub(payAll).add(witdhrawRewardAll).add(feeWithdrawRewardAll);
        // 本次利润
        uint256 currentReward = allReward.sub(lastReward);
        if (0 < currentReward) {
            // 设置fee的利润
            feeRewardAll = feeRewardAll.add(currentReward.mul(rewardFeeRate).div(rewardFeeBase));
            // 设置用户的利润
            rewardAll = rewardAll.add(currentReward.sub(currentReward.mul(rewardFeeRate).div(rewardFeeBase)));
            // 设置本次利润分红给用户
            withdrawStfil.setCurrentReward(currentReward.sub(currentReward.mul(rewardFeeRate).div(rewardFeeBase)));
        }

        // 更新最新总利润
        lastReward = allReward;

        emit rewardCompleted(allReward, feeRewardAll, rewardAll, currentReward);
    }

    function withdrawReward(uint256 amount, address to) external nonReentrant {
        require(address(withdrawStfil) == _msgSender() && rewardAll >= witdhrawRewardAll.add(amount), "ManagerFil: not enough");
        witdhrawRewardAll = witdhrawRewardAll.add(amount);

        stfil.unstake(amount, to); // 打给收fil地址
        emit withdrawRewardCompleted(to, rewardAll, witdhrawRewardAll, amount);
    }

    // feeTo
    function feeWithdraw(uint256 amount) external {
        require(feeTo == _msgSender() && feeRewardAll >= feeWithdrawRewardAll.add(amount), "ManagerFil: not enough");
        feeWithdrawRewardAll = feeWithdrawRewardAll.add(amount);

        stfil.unstake(amount, feeTo);
        emit feeWithdrawRewardCompleted(feeTo, feeRewardAll, feeWithdrawRewardAll, amount);
    }

    // default admin
    function setWithdrawStfil(address withdrawStfil_) external onlyDefaultAdminRole {
        withdrawStfil = IWithdrawStfil(withdrawStfil_);
    }

    // super admin
    function setRewardFeeRate(uint256 rate) external onlySuperAdminRole {
        require(10000 >= rate, "ManagerFil: not enough");
        rewardFeeRate = rate;
    }

    function setFeeTo(address payable feeTo_) external onlySuperAdminRole {
        feeTo = feeTo_;
    }

    receive() external payable {}
}