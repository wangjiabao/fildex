// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFilecoinMinerControllerTemplate {
    struct CreateData {
        address superAdmin;
        address defaultAdmin;
        address payable owner;
        uint64 actor;
        address miner;
        uint256 due;
        address factory;
        bool union;
        uint256 timeType;
        uint256 extraTime;
    }

    struct CheckData {
        uint256 costRatePerToken;
        uint256 costBasePerToken;
        uint256 profitRatePerToken;
        uint256 profitBasePerToken;
        uint256 stakeType;
        uint256 stakeTypeRate;
        uint256 stakeTypeBase;
        uint256 rewardOwnerRate;
        uint256 rewardRate; 
        uint256 rewardBase;
        uint256 rewardBankRate;
        uint256 timeType;
    }

    struct CreateControllerData {
        address payable owner;
        uint64 actor;
        uint256 due;
        bool union;
        uint256 stakeType;
        uint256 stakeTypeRate;
        uint256 stakeTypeBase;
        uint256 rewardOwnerRate;
        uint256 rewardRate;
        uint256 rewardBankRate;
        uint256 rewardBase;
        uint256 extraTime;
    }

    function initialize(CreateData memory data) external returns (bool);

    function adminTransferOwner(address newOwner) external;

    function adminWithdraw(address payable account) external;

    function returnPledge() external;
}
