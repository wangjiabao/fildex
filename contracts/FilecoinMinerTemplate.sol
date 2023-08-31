//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries/FilAddressUtil.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { PowerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PowerAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { PowerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/PowerTypes.sol";
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

    function initialize(uint64 actor_, address payable controller_) initializer public returns (bool) {
        actor = actor_;
        controller = controller_;
        return true;
    }

    function changeOwner(address new_owner) internal {
       MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddressUtil.fromEthAddress(new_owner));
    }

    function getAvailableBalances() internal returns (uint256 availableBalances) {
        CommonTypes.BigInt memory tmp = MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor));
        if (0 == tmp.val.length) {
            availableBalances = 0;
        } else {
           (availableBalances, ) = BigInts.toUint256(tmp); 
        }
    }

    function getVestingFunds() public returns (uint256 vestingFund) {
        MinerTypes.GetVestingFundsReturn memory res = MinerAPI.getVestingFunds(CommonTypes.FilActorId.wrap(actor));
        uint256 tmp = 0;
        for (uint i = 0; i < res.vesting_funds.length; i++) {
            if (0 == res.vesting_funds[i].amount.val.length) {
                tmp = 0;
            } else {
                (tmp, ) = BigInts.toUint256(res.vesting_funds[i].amount);
            }
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

    function withdraw() external returns (uint256 tmp) {
        require(controller == msg.sender, "err");
        uint256 availableBalances = getAvailableBalances();
        require(0 < availableBalances, "available balance is 0");
        (tmp, ) = BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(availableBalances)));
        controller.transfer(tmp);
    }

    function changeWorkerAddress(address new_worker, address[] memory controls) external {
        require(controller == msg.sender, "err");
        CommonTypes.FilAddress[] memory controllAddress = new CommonTypes.FilAddress[](controls.length);
        for (uint i = 0; i < controls.length; i++) {
            controllAddress[i] = FilAddressUtil.fromEthAddress(controls[i]);
        }

        MinerAPI.changeWorkerAddress(CommonTypes.FilActorId.wrap(actor),
        MinerTypes.ChangeWorkerAddressParams(
            FilAddressUtil.fromEthAddress(new_worker),
            controllAddress
        ));
    }

    function confirmChangeWorkerAddress() external {
        require(controller == msg.sender, "err");
        MinerAPI.confirmChangeWorkerAddress(CommonTypes.FilActorId.wrap(actor));
    }

    function minerRawPower() external returns (bool meetsConsensusMinimum, uint256 cap) {
        PowerTypes.MinerRawPowerReturn memory res = PowerAPI.minerRawPower(actor);
        meetsConsensusMinimum = res.meets_consensus_minimum;
        (cap,) = BigInts.toUint256(res.raw_byte_power);
    }

    receive() external payable {}
}