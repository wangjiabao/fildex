//SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ITokenExists {
    function existsToken(address token) external view returns (bool);

    function existsTopUnionToken(address token) external view returns (bool);
}