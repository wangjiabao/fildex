//SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IRewardPool {
    function setStake(address stake) external;

    function withdrawReward(address to, uint256 amount) external;
}