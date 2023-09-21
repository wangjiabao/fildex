// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenTemplate {
   
    struct CreateData {
        uint256 startTime;
        uint256 cap_;
        string name_;
        string logo_;
        address dfil_;
        address key_;
        address tokenExchange_;
        address bank_;
        uint64 actor_;
        address superAdmin;
        address defaultAdmin;
        address payable owner_;
        uint256 costRatePerToken;
        uint256 costBasePerToken;
        uint256 profitRatePerToken;
        uint256 profitBasePerToken;
        uint256 pledge;
        address controller;
        address swapFactory;
        address callPair;
        uint256 stageType;
        uint256 stageTypeRate;
        uint256 stageTypeBase;
        uint256 rewardOwnerRate;
        uint256 rewardOwnerBase;
        uint256 rewardRate; 
        uint256 rewardBase;
        uint256 rewardBankRate; 
        uint256 rewardBankBase;
        uint256 keyRatePerT;
        uint256 keyBasePerT;
    }

    function initialize(CreateData memory data) external returns (bool);

    function depositFilIn() external payable;

    function setReward() payable external;

    function setStake(address stake_) external;
}
