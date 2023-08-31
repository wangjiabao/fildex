//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenBankRewardDfil is AccessControlEnumerable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant GRANT_SET_REWARD_ROLE = keccak256("GRANT_SET_REWARD_ROLE");
    bytes32 public constant SET_REWARD_ROLE = keccak256("SET_REWARD_ROLE");

    uint256 public total;
    mapping(address => uint256) public userBalance;

    IDFIL public rewardUNIToken;
    address public bank;

    uint256 public stakingFinishTime = block.timestamp;

    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;
    uint256 public rewardRate;

    uint256 public currentReward;
    uint256 public stakeRewardCycle = 604800;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardsPerToken;

    EnumerableSet.UintSet private _historyRewardRate;
    EnumerableSet.UintSet private _historyStakingTime;

    modifier update(address owner) {
        if (owner != address(0)) {
            rewards[owner] = allRewardsOfUser(owner);
            rewardPerTokenStored = rewardUNIPerToken();
            userRewardsPerToken[owner] = rewardPerTokenStored;
            lastUpdateTime = getLastTime();
        }
        _;
    }

    event Reward(address indexed account, uint256 amount);

    constructor(address rewardUNIToken_) {
        rewardUNIToken = IDFIL(rewardUNIToken_);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(SET_REWARD_ROLE, GRANT_SET_REWARD_ROLE); // tokenFactory
    }
    
    function getLastTime() public view returns (uint256) {
        return Math.min(block.timestamp, stakingFinishTime);
    }

    function rewardUNIPerToken() public view returns (uint256 rewardUNI) {
        if (total == 0) {
            rewardUNI = rewardPerTokenStored;
        } else {
            rewardUNI = rewardPerTokenStored.add(rewardRate.mul(getLastTime().sub(lastUpdateTime)).mul(1e18).div(total));
        }
    }

    function allRewardsOfUser(address account) public view returns (uint256) {
        return userBalance[account].mul(rewardUNIPerToken().sub(userRewardsPerToken[account])).div(1e18).add(rewards[account]);
    }

    function record(address account, uint256 amount) external update(account) {
        require(bank == _msgSender(), "TokenBank: must bank to record");
        
        userBalance[account] = userBalance[account].add(amount);
        total = total.add(amount);
    }

    function _outRecord(address account, uint256 amount) internal {
        rewardHandle(account);

        if (amount >= userBalance[account]) {
            total = total.sub(userBalance[account]);
            delete userBalance[account];
        } else {
            total = total.sub(amount);
            userBalance[account] = userBalance[account].sub(amount);
        }
    }

    function outRecord(address account) external {
        _outRecord(account, userBalance[account]);
    }

    function outRecord(address account, uint256 amount) external {
        _outRecord(account, amount);
    }

    function reward(address account) external  {
        rewardHandle(account);
    }

    function rewardHandle(address account) internal update(account) {
        require(bank == _msgSender(), "TokenBank: must bank to reward");

        uint256 stakingRewards = rewards[account];
        if (stakingRewards > 0) {
            rewards[account] = 0;
            rewardUNIToken.transfer(account, stakingRewards);
        }

        emit Reward(account, stakingRewards);
    }

    /**
     * 算力代币合约陆续设置分红收益
     */
    function setCurrentReward(uint256 amount) external {
        require(hasRole(SET_REWARD_ROLE, _msgSender()), "Token: must set reward role to set");
        currentReward = currentReward.add(amount);
    }

    /**
     *  根据分红收益数量，设置分红速率和周期
     */
    function setRewardRateAndStakingFinishTime() external {
        require(block.timestamp > stakingFinishTime, "TokenBank: must finish last reward");
        require(currentReward > 0, "TokenBank: must reward more than 0");

        rewardPerTokenStored = rewardUNIPerToken();

        stakingFinishTime = block.timestamp;
        lastUpdateTime = getLastTime();

        rewardRate =  currentReward.div(stakeRewardCycle);
        stakingFinishTime = stakingFinishTime.add(stakeRewardCycle);

        _historyRewardRate.add(rewardRate);
        _historyStakingTime.add(stakeRewardCycle);

        currentReward = 0;
    }

    function getHistoryRewardRate() external view returns (uint256[] memory) {
        return _historyRewardRate.values();
    }

    function getHistoryStakingTime() external view returns (uint256[] memory) {
        return _historyStakingTime.values();
    }

    function getStakingFinishTime() external view returns (uint256) {
        return stakingFinishTime;
    }

    // tokenFactory
    function setRewarder(address account) external {
        grantRole(SET_REWARD_ROLE, account);
    }
    
    // default admin 
    function setBank(address bank_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenBank: must have default admin role to set");
        bank = bank_;
    }
}