// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISTFILToken {
    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address owner) external view returns (uint256);
}
