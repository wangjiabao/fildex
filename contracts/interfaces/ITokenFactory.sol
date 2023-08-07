// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenFactory {
    function setAcotrMinerController(uint64 actor, address controller) external;

    function createToken(
        uint256 cap,
        string memory name,
        string memory logo,
        address payable owner,
        uint64 actor,
        uint256 depositRatePerToken,
        uint256 depositBasePerToken
    ) external returns (address token);

    function createUnionToken(
        uint256 cap,
        string memory name,
        string memory logo,
        uint64 actor,
        uint256 depositRatePerToken,
        uint256 depositBasePerToken
    ) external returns (address token);

    function getUserOwnerByAccount(address account) external view returns (address);

    function existsOwner(address owner) external view returns (bool);
    
    function getTop() external view returns (address);

    function existsToken(address token) external view returns (bool);

    function existsTopUnionTokens(address token) external view returns (bool);
}
