//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries/FilAddressUtil.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

contract FilecoinMinerTemplate is Initializable {
    using SafeMath for uint256;

    uint64 public actor;
    address payable public controller;

    constructor() {
        _disableInitializers();
    }

    function initialize(uint64 actor_, address payable controller_) initializer public {
        actor = actor_;
        controller = controller_;
    }

    function changeOwner(address new_owner) internal {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddresses.fromActorID(PrecompilesAPI.resolveEthAddress(new_owner)));
    }

    function getAvailableBalances() internal returns (uint256 availableBalances) {
        (availableBalances, ) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor)));
    }

    function getVestingFunds() public returns (uint256 vestingFund) {
        MinerTypes.GetVestingFundsReturn memory res = MinerAPI.getVestingFunds(CommonTypes.FilActorId.wrap(actor));
        uint256 tmp = 0;
        for (uint i = 0; i < res.vesting_funds.length; i++) {
            (tmp, ) = BigInts.toUint256(res.vesting_funds[i].amount);
            vestingFund = vestingFund + tmp;
        }
    }

    function getPledge() external returns (uint256) {
        return FilAddressUtil.ethAddress(actor).balance.sub(getAvailableBalances()).sub(getVestingFunds());
    }

    function getSectorSize() external returns (uint256) {
        return uint256(MinerAPI.getSectorSize(CommonTypes.FilActorId.wrap(actor)));
    }

    function getMinerAvailableBalances() external returns (uint256) {
        return getAvailableBalances();
    }

    function transferOwner(address new_owner) external {
        require(controller == msg.sender, "err");
        changeOwner(new_owner);
    }

    function returnPledge(address new_owner, uint256 pledge) external {
        require(controller == msg.sender, "err");
        MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(pledge));
        controller.transfer(pledge);
        changeOwner(new_owner);
    }

    function reward() external returns (uint256 tmp) {
        require(controller == msg.sender, "err");
        (tmp, ) = BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(getAvailableBalances())));
        controller.transfer(tmp);
    }

    // function changeWorkerAddress(int64 new_expiration, address new_worker) public payable {
    //     MinerAPI.changeWorkerAddress(CommonTypes.FilActorId.wrap(actor), 
    //     MinerTypes.ChangeWorkerAddressParams(
    //         FilAddressUtil.fromEthAddress(new_worker),
    //         CommonTypes.ChainEpoch.wrap(new_expiration)
    //     );
    // }
}