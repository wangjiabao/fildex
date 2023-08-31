//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonTypes } from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import { FilAddresses } from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import { PrecompilesAPI } from "@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

library FilAddressUtil {
    function isFilF0Address(address addr) internal pure returns (bool){
        if ((uint160(addr) >> 64) == 0xff0000000000000000000000) {
            return true;
        }

        return false;
    }

    function fromEthAddress(address addr) internal view returns (CommonTypes.FilAddress memory){
        if (isFilF0Address(addr)) {
            return FilAddresses.fromActorID(uint64(uint160(addr)));
        }

        return FilAddresses.fromActorID(PrecompilesAPI.resolveEthAddress(addr));
    }

    function bytesToAddress(bytes memory bys) internal pure returns (address addr) {
        require(bys.length == 20);
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function ethAddress(uint64 actor) internal pure returns (address) {
        return bytesToAddress(abi.encodePacked(hex"ff0000000000000000000000", actor));
    }
}