// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISTFIL {
    function stake(address onBehalOf, uint32 referralCode) payable external;
    
    function unstake(uint256 amount, address to) external;
}
