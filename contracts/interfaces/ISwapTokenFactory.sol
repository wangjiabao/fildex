// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface ISwapTokenFactory {
    function existsToken(address token) external view returns (bool);
    
    function existsTopUnionToken(address token) external view returns (bool);
}
