//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { SendAPI } from "@zondax/filecoin-solidity/contracts/v0.8/SendAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

library FilAddressUtil {
    function isFilF0Address(address addr) internal pure returns (bool){
        if ((uint160(addr) >> 64) == 0xff0000000000000000000000) {
            return true;
        }

        return false;
    }

    function fromEthAddress(address addr) internal pure returns (CommonTypes.FilAddress memory){
        if (isFilF0Address(addr)) {
            return FilAddresses.fromActorID(uint64(uint160(addr)));
        }

        return FilAddresses.fromEthAddress(addr);
    }
}
contract a {
    // using BigInts for *;

    uint64 public actor = 1000;
    uint64 public ownerActor;

    uint256 public minerBalance;
    uint256 public availableBalance;
    uint256 public vestingFund;
    uint256 public size;


    function acceptOwner() external {
        changeOwner(address(this));
        getAll();
    }

    function changeOwner(address new_owner) internal {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddresses.fromActorID(PrecompilesAPI.resolveEthAddress(new_owner)));
    }

    function changeOtherOwner(address new_owner) external {
        changeOwner(new_owner);
    }

    function withdrawBalance(uint256 amount) public returns (uint256, bool) {
        return BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(amount)));
    }

    function changeBeneficiary(int64 new_expiration, int256 new_quota, address new_beneficairy) public payable {
        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(actor), 
        MinerTypes.ChangeBeneficiaryParams(
            FilAddressUtil.fromEthAddress(new_beneficairy), 
            BigInts.fromInt256(new_quota), 
            CommonTypes.ChainEpoch.wrap(new_expiration)));
    }

    function getOwner() public returns (uint64) {
        MinerTypes.GetOwnerReturn memory ownerInfo = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(actor));
        ownerActor = PrecompilesAPI.resolveAddress(ownerInfo.owner);

        return ownerActor;
    }

    function isControllingAddress() public returns (bool) {
        return MinerAPI.isControllingAddress(CommonTypes.FilActorId.wrap(actor), FilAddressUtil.fromEthAddress(address(this)));
    }

    function getAll() public {
        (availableBalance, ) = BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor)));
        getVestingFunds();

        size = MinerAPI.getSectorSize(CommonTypes.FilActorId.wrap(actor));

    }

    function bytesToAddress(bytes memory bys) internal pure returns (address addr) {
        require(bys.length == 20);
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function ethAddress(uint64 actor1) internal pure returns (address) {
        return bytesToAddress(abi.encodePacked(hex"ff0000000000000000000000", actor1));
    }

    function getBalance(uint64 actor1) public {
        minerBalance = ethAddress(actor1).balance;
    }

    function getAvailableBalances() public returns (uint256, bool) {
        return BigInts.toUint256(MinerAPI.getAvailableBalance(CommonTypes.FilActorId.wrap(actor)));
    }

    function getSectorSize() public returns (uint64) {
        return MinerAPI.getSectorSize(CommonTypes.FilActorId.wrap(actor));
    }

    function getVestingFunds() public {
        MinerTypes.GetVestingFundsReturn memory res = MinerAPI.getVestingFunds(CommonTypes.FilActorId.wrap(actor));
        uint256 tmp = 0;
        for (uint i = 0; i < res.vesting_funds.length; i++) {
            (tmp, ) = BigInts.toUint256(res.vesting_funds[i].amount);
            vestingFund = vestingFund + tmp;
        }
    }
}