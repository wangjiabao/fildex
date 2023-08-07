// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface ISwapTokenTemplate {
    function getStakeType() external view returns(uint256);

    function getStageTypeRate() external view returns(uint256);

    function getStageTypeBase() external view returns(uint256);

    function getStageRecords(address user) external view returns(uint256);

    function stakeRecord(address user, uint256 amount) external;

    function unStakeRecord(address user, uint256 amount) external;
}