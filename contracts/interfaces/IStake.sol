// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStake {
    function getStakingFinishTime() external returns (uint256);
    
    function setRewardRateAndStakingFinishTime(uint256 rewardRate_, uint256 stakingTime_) external;
}
