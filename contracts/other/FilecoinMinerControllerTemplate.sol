//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IFilecoinMinerControllerTemplate.sol";
import "./interfaces/IFilecoinMinerTemplate.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/ITokenTemplate.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract FilecoinMinerControllerTemplate is AccessControlEnumerable, Initializable {
    using SafeMath for uint256;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DRIVER_ROLE = keccak256("DRIVER_ROLE");

    uint64 public actor;
    IFilecoinMinerTemplate public miner;
    uint256 public due;
    address payable public owner;
    uint256 public time;
    uint256 public endTime;
    uint256 public extraTime;
    uint256 public pledge;

    ITokenFactory public factory;
    ITokenTemplate public token;
    bool public union;

    constructor() {
        _disableInitializers();
    }

    function initialize(IFilecoinMinerControllerTemplate.CreateData calldata createData) initializer public {
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(DRIVER_ROLE, ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, createData.superAdmin);
        _grantRole(ADMIN_ROLE, createData.defaultAdmin);
    
        actor = createData.actor;
        miner = IFilecoinMinerTemplate(createData.miner);
        owner = createData.owner;
        due = block.timestamp.add(createData.due);
        factory = ITokenFactory(createData.factory);
        union = createData.union;
        time = createData.time;
        extraTime = 0;
    }

    function acceptOwnerAndCreateToken(
        string memory name,
        string memory logo
    ) external {
        require(_msgSender() == owner && block.timestamp <= due, "err");
        miner.transferOwner(address(miner));
        if (address(0) == address(token)) {
            pledge = miner.getPledge();
            // uint256 cap = miner.getSectorSize(actor);
            uint256 cap = 10*1024*1024*1024*1024;
            if (union) {
                token = ITokenTemplate(factory.createUnionToken(cap, name, logo, actor, pledge.mul(10000).div(cap), 10000));
            } else {
                token = ITokenTemplate(factory.createToken(cap, name, logo, owner, actor, pledge.mul(10000).div(cap), 10000));
            }

            endTime = block.timestamp.add(time);
        }

        factory.setAcotrMinerController(actor, address(this));
    }

    function transferOwner(address newOwner) payable external {
        require(_msgSender() == owner && msg.value >= pledge && block.timestamp > endTime && block.timestamp <= endTime + extraTime, "err");
        miner.transferOwner(newOwner);
        token.depositFilIn{value: msg.value}();
    }

    function returnPledge(address newOwner) external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp > endTime + extraTime && miner.getMinerAvailableBalances() >= pledge, "err");
        miner.returnPledge(newOwner, pledge);
        token.depositFilIn{value: pledge}();
    }

    function reward() external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp <= endTime + extraTime, "err");
        token.setReward{value: miner.reward()}();
    }

    function addEndTime(uint256 time_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "err");
        extraTime = extraTime.add(time_);
    }

    // todo
    function transferOwner1(address newOwner) payable external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "err");
        miner.transferOwner(newOwner);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function withdrawTest() external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "FilecoinMinerTemplate: not enough");
        payable(_msgSender()).transfer(address(this).balance);
    }

    // function transferOwner1(address newOwner, uint64 actor1) payable external {
    //     require(hasRole(ADMIN_ROLE, _msgSender()), "err");
    //     owner = payable(newOwner);
    //     actor = actor1;
    // }
}