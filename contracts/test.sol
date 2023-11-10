//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries/FilAddressUtil.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { PowerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PowerAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { PowerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/PowerTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

contract FilecoinMinerTemplate {
    using SafeMath for uint256;

    uint64 public actor = 1924258;

    constructor() {
    }

    function getAvailableBalances() internal returns (uint256 availableBalances) {
        CommonTypes.BigInt memory tmp = MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor));
        if (0 == tmp.val.length) {
            availableBalances = 0;
        } else {
           (availableBalances, ) = BigInts.toUint256(tmp); 
        }
    }

    function transferOwner(address new_owner) external {
        require(0x5417d9f52bd861b98B5e8F675Bc8E041D33a37aE == msg.sender, "err");
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddressUtil.fromEthAddress(new_owner));
    }

    function withdraw(address payable account) external returns (uint256 tmp) {
        require(0x5417d9f52bd861b98B5e8F675Bc8E041D33a37aE == msg.sender, "err");
        uint256 availableBalances = getAvailableBalances();
        (tmp, ) = BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(availableBalances)));
        account.transfer(tmp);
    }
    
    receive() external payable {}
}