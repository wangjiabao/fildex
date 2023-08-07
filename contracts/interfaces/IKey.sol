// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IKey {
    function mint(address account, uint256 amount) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external;

    function burnFrom(address account, uint256 amount) external;

    function setBurner(address account) external;
}
