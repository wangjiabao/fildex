// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenBankReward {
   function record(address account, uint256 amount) external;

   function outRecord(address account) external;

   function outRecord(address account, uint256 amount) external;

   function outRecordKeyAt(address account, uint256 keyAt) external;

   function reward(address account) external;

   function setRewarder(address account) external;

   function setCurrentReward(uint256 amount) external;

   function getTermRecord() external view returns (bool);
}
