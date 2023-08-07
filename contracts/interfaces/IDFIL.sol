// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDFIL {
    function transferFrom(address from, address to, uint256 amount) external;

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function setWhite(address account, bool enable) external;

    function getWhiteEnable() external view returns(bool);

     function balanceOf(address owner) external view returns (uint);
}
