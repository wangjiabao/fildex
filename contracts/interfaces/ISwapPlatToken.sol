// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IPlatToken {
    function transferFrom(address from, address to, uint256 amount) external;

    function transfer(address to, uint value) external returns (bool);

    function mint(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function setMinter(address account) external;
    
    function setBurner(address account) external;

    function setWhite(address account, bool enable) external;
}
