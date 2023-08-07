// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

contract Ownable {
    address private _owner;
    address private _pendingOwner;

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() public {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        delete _pendingOwner;
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function acceptOwnership() external {
        address sender = msg.sender;
        require(pendingOwner() == sender, "Ownable: caller is not the new owner");
        _transferOwnership(sender);
    }
}