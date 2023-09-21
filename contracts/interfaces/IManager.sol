// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IManager {
    function pay() payable external;

    function repay(uint256 amount) external;

    function withdrawReward(uint256 amount, address to) external;
}
