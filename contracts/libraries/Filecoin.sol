//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./FilAddressUtil.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

library Filecoin {
    using SafeMath for uint256;

    function transferOwner(address new_owner, uint64 actor) internal {
        changeOwner(new_owner, actor);
    }

    function returnPledge(address new_owner, uint64 actor, uint256 pledge) internal {
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(pledge));
        changeOwner(new_owner, actor);
    }

    function changeOwner(address new_owner, uint64 actor) internal {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddresses.fromActorID(PrecompilesAPI.resolveEthAddress(new_owner)));
    }

    function reward(uint64 actor) internal returns (uint256 tmp) {
        (tmp, ) = BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(getAvailableBalances(actor))));
    }

    function getPledge(uint64 actor) internal returns (uint256) {
        return FilAddressUtil.ethAddress(actor).balance.sub(getAvailableBalances(actor)).sub(getVestingFunds(actor));
    }

    function getAvailableBalances(uint64 actor) internal returns (uint256 availableBalances) {
        (availableBalances, ) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor)));
    }

    function getVestingFunds(uint64 actor) internal returns (uint256 vestingFund) {
        MinerTypes.GetVestingFundsReturn memory res = MinerAPI.getVestingFunds(CommonTypes.FilActorId.wrap(actor));
        uint256 tmp = 0;
        for (uint i = 0; i < res.vesting_funds.length; i++) {
            (tmp, ) = BigInts.toUint256(res.vesting_funds[i].amount);
            vestingFund = vestingFund + tmp;
        }
    }

    function getSectorSize(uint64 actor) internal returns (uint256) {
        return uint256(MinerAPI.getSectorSize(CommonTypes.FilActorId.wrap(actor)));
    }
}