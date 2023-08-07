//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IFilecoinMinerTemplate.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/ITokenTemplate.sol";
import "./libraries/FilAddressUtil.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import { MinerAPI } from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import { SendAPI } from "@zondax/filecoin-solidity/contracts/v0.8/SendAPI.sol";
import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { MinerTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { BigInts } from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

contract FilecoinMinerTemplate is AccessControlEnumerable, Initializable {
    // using BigInts for *;
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REWARD_ROLE = keccak256("REWARD_ROLE");

    uint64 public actor = 1000;

    address payable public systemOwner;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public due;
    uint256 public pledge;

    uint256 public cap1;

    ITokenFactory public factory;
    ITokenTemplate public token;
    bool public union;


    function acceptOwnerAndCreateToken(
    ) external {
        
        changeOwner(address(this));

        if (address(0) == address(token)) {
            pledge = FilAddressUtil.ethAddress(actor).balance.sub(getAvailableBalances()).sub(getVestingFunds());
            cap1 = uint256(getSectorSize());
            // if (union) {
            //     token = ITokenTemplate(factory.createUnionToken(cap, name, logo, actor, costRatePerToken, costBasePerToken, profitRatePerToken, profitBasePerToken, pledge.mul(10000).div(cap), 10000));
            // } else {
            //     token = ITokenTemplate(factory.createToken(cap, name, logo, systemOwner, actor, costRatePerToken, costBasePerToken, profitRatePerToken, profitBasePerToken, pledge.mul(10000).div(cap), 10000));
            // }

            startTime = block.timestamp;
            // endTime = startTime.add(46656000);
            endTime = startTime.add(40);
        }
    }

    function transferOwner(address new_owner) payable external {
        // token.depositFilIn{value: msg.value}();
        changeOwner(new_owner);
    }

    function getAll() external {
        pledge = FilAddressUtil.ethAddress(actor).balance.sub(getAvailableBalances()).sub(getVestingFunds());
    }

    function changeOwner(address new_owner) internal {
        MinerAPI.changeOwnerAddress(CommonTypes.FilActorId.wrap(actor), FilAddresses.fromActorID(PrecompilesAPI.resolveEthAddress(new_owner)));
    }

    function reward(uint256 amount) public {
        require(hasRole(REWARD_ROLE, _msgSender()), "FilecoinMinerTemplate: must have reward role to set");
        uint256 tmp = 0; 
        (tmp, ) = BigInts.toUint256(MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromUint256(amount)));
        token.setReward{value: tmp}();
    }

    function getSectorSize() public returns (uint64) {
        return MinerAPI.getSectorSize(CommonTypes.FilActorId.wrap(actor));
    }

    function getAvailableBalances() public returns (uint256 availableBalances) {
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

    function withdrawTest() external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "FilecoinMinerTemplate: not enough");
        payable(_msgSender()).transfer(address(this).balance);
    }
}