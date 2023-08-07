//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IKey.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenBankRewardKey is AccessControlEnumerable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IKey public rewardUNIToken;
    address public bank;

    uint256 public stakingFinishTime = block.timestamp;

    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;
    uint256 public rewardRate;

    uint256 public startTime;

    // todo
    uint256 public stakeCycleTime = 86400;
    // uint256 public stakeCycleTime = 2592000;
    // 模拟小数，提升可扩展性
    uint256 public stakeCycleRate = 100;
    uint256 public stakeCycleBase = 100;

    uint256 public total;

    mapping(address => uint256) public userRewardsPerToken;

    mapping(address => uint256[]) public rewards;
    mapping(address => uint256[]) public userBalanceRecord;
    mapping(address => uint256[]) public userBalanceRecordTime;

    EnumerableSet.UintSet private _historyRewardRate;
    EnumerableSet.UintSet private _historyStakingTime;

    modifier update(address owner) {
        if (owner != address(0)) {
            uint256[] memory userReward = allRewardsOfUser(owner);
            for (uint256 i = 0; i < userReward.length; i++) {
                rewards[owner][i] = userReward[i];
            }

            rewardPerTokenStored = rewardUNIPerToken();
            userRewardsPerToken[owner] = rewardPerTokenStored;
            lastUpdateTime = getLastTime();
        }
        _;
    }

    event Reward(address indexed account, uint256 amount);

    constructor(address rewardUNIToken_) {
        rewardUNIToken = IKey(rewardUNIToken_);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());

        startTime = block.timestamp;
    }
    
    function getLastTime() public view returns(uint256) {
        return Math.min(block.timestamp, stakingFinishTime);
    }

    function rewardUNIPerToken() public view returns(uint256 rewardUNI) {
        if (total == 0) {
            rewardUNI = rewardPerTokenStored;
        } else {
            rewardUNI = rewardPerTokenStored.add(rewardRate.mul(getLastTime().sub(lastUpdateTime)).mul(1e18).div(total));
        }
    }

    function allRewardsOfUser(address account) public view returns(uint256[] memory) {
        uint256[] memory userReward = new uint256[](userBalanceRecord[account].length);
        for (uint256 i = 0; i < userReward.length; i++) {
            userReward[i] = rewards[account][i].add(
                userBalanceRecord[account][i].mul(rewardUNIPerToken().sub(userRewardsPerToken[account])).div(1e18)
            );
        }

        return userReward;
    }

    function record(address account, uint256 amount) external update(account) {
        require(bank == _msgSender(), "TokenBank: must bank to record");

        total = total.add(amount);
        userBalanceRecord[account].push(amount);
        userBalanceRecordTime[account].push(block.timestamp);
        rewards[account].push(0);
    }

    function outRecord(address account) external {
        rewardHandle(account);

        for (uint256 i = 0; i < userBalanceRecord[account].length; i++) {
            total = total.sub(userBalanceRecord[account][i]);
        }

        delete userBalanceRecord[account];
        delete userBalanceRecordTime[account];
        delete rewards[account];
    }

    function outRecordKeyAt(address account, uint256 at_) external {
        rewardHandle(account);
        
        total = total.sub(userBalanceRecord[account][at_]);
        delete userBalanceRecord[account][at_];
        delete userBalanceRecordTime[account][at_];
        delete rewards[account][at_];
    }

    function reward(address account) external {
        rewardHandle(account);
    }

    function rewardHandle(address account) internal update(account) {
        require(bank == _msgSender(), "TokenBank: must bank to reward");

        uint256 stakingRewards = 0;
        uint256 time = block.timestamp;
        for (uint256 i = 0; i < userBalanceRecord[account].length; i++) {
            time = userBalanceRecordTime[account][i];
            if (block.timestamp.sub(time) >= stakeCycleTime.mul(4)) {
                stakingRewards = stakingRewards.add(rewards[account][i].mul(5).mul(stakeCycleRate).div(stakeCycleBase));
            } else if (block.timestamp.sub(time) >= stakeCycleTime.mul(3)) {
                stakingRewards = stakingRewards.add(rewards[account][i].mul(4).mul(stakeCycleRate).div(stakeCycleBase));
            } else if (block.timestamp.sub(time) >= stakeCycleTime.mul(2)) {
                stakingRewards = stakingRewards.add(rewards[account][i].mul(3).mul(stakeCycleRate).div(stakeCycleBase));
            } else if (block.timestamp.sub(time) >= stakeCycleTime.mul(1)) {
                stakingRewards = stakingRewards.add(rewards[account][i].mul(2).mul(stakeCycleRate).div(stakeCycleBase));
            } else {
                stakingRewards = stakingRewards.add(rewards[account][i].mul(1).mul(stakeCycleRate).div(stakeCycleBase));
            }

            rewards[account][i] = 0;
        }
        
        if (stakingRewards > 0) {
            rewardUNIToken.mint(account, stakingRewards);
        }

        emit Reward(account, stakingRewards);
    }
    
    function setRewardRateAndStakingFinishTime(uint256 rewardRate_, uint256 stakingTime_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "TokenBank: must have admin role to set");

        rewardPerTokenStored = rewardUNIPerToken();
        lastUpdateTime = getLastTime();

        rewardRate = rewardRate_;
        stakingFinishTime = stakingFinishTime.add(stakingTime_);

        _historyRewardRate.add(rewardRate_);
        _historyStakingTime.add(stakingTime_);
    }

    function setStakeCycleRate(uint256 rate) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "TokenBank: must have admin role to set");
        stakeCycleRate = rate;
    }

    function getHistoryRewardRate() external view returns (uint256[] memory) {
        return _historyRewardRate.values();
    }

    function getHistoryStakingTime() external view returns (uint256[] memory) {
        return _historyStakingTime.values();
    }

    function getUserBalanceRecord(address account) external view returns (uint256[] memory) {
        return userBalanceRecord[account];
    }

    function getUserBalanceRecordTime(address account) external view returns (uint256[] memory) {
        return userBalanceRecordTime[account];
    }

    // default admin 
    function setBank(address bank_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenBank: must have default admin role to set");
        bank = bank_;
    }
}