// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFilecoinMinerTemplate {
    function initialize(uint64 actor_, address payable controller_) external returns (bool);

    function withdraw() external returns (uint256 tmp);

    function transferOwner(address new_owner) external;

    function getPledge() external returns (uint256);

    function getMinerAvailableBalances() external returns (uint256);

    function changeWorkerAddress(address new_worker, address[] memory controls) external;
    
    function confirmChangeWorkerAddress() external;

    function getSectorSize() external returns (uint256);

    function minerRawPower() external returns (bool meetsConsensusMinimum, uint256 cap);
}
