// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITokenExchange {
    function setTokenRole(address token) external;
    
    function ownerFilBalanceChange(address owner) external;

    function REWARDFIL2DFIL(address owner) external payable;

    function FILIN(address owner) external payable;

    function FILLOCK(address owner, uint256 amount, uint256 sellAmount) external;

    function FILRECORDANDMINTDFIL(address owner, uint256 amount, uint256 sellAmount) external;

    function WITHDRAWOWNERFIL(address payable owner, uint256 sellCostAmount, uint256 sellProfitAmount, uint256 feeOffset) external;

    function WITHDRAWOWNERUNIONFIL(address payable owner, uint256 sellProfitAmount, uint256 feeOffset) external;
    
    function WITHDRAWPROPOSERUNIONFIL(address payable owner, uint256 sellCostAmount, uint256 sellDepositAmount, uint256 feeOffset) external;

    function getAccountUnion() external view returns (address[] memory);

    function getAllowAccountUnion() external view returns (address[] memory);

    function getAllowAccountUnionAt(uint256 i) external view returns (address);

    function getAllowAccountUnionLength() external view returns (uint256);

    function getTokenOwnerFilBalance(address owner) external view returns (int256);

    function getTokenOwnerDfilBalance(address owner) external view returns (int256);

    function getAllowAccountUnionAmountTotal() external view returns (uint256);

    function getAllowAccountUnionAmount(address account) external view returns (uint256);

    function getExchangeEnableNoLimit() external view returns (bool);
}
