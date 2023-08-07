//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IFilecoinMinerTemplate.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/ITokenTemplate.sol";
import "./libraries/Filecoin.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract FilecoinMinerControllerTemplate is AccessControlEnumerable, Initializable {
    using SafeMath for uint256;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DRIVER_ROLE = keccak256("DRIVER_ROLE");

    uint64 public actor;
    uint256 public due;
    address payable public systemOwner;
    uint256 public time;
    uint256 public endTime;
    uint256 public pledge;

    ITokenFactory public factory;
    ITokenTemplate public token;
    bool public union;

    constructor() {
        _disableInitializers();
    }

    function initialize(IFilecoinMinerTemplate.CreateData calldata createData) initializer public {
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(DRIVER_ROLE, ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, createData.superAdmin);
        _grantRole(ADMIN_ROLE, createData.defaultAdmin);
        
        actor = createData.actor;
        systemOwner = createData.owner;
        due = block.timestamp.add(createData.due);
        factory = ITokenFactory(createData.factory);
        union = createData.union;
        time = createData.time;
    }

    function acceptOwnerAndCreateToken(
        string memory name,
        string memory logo
    ) external {
        require(_msgSender() == systemOwner && block.timestamp <= due, "err");
        Filecoin.changeOwner(address(this), actor);
        if (address(0) == address(token)) {
            pledge = Filecoin.getPledge(actor);
            // uint256 cap = Filecoin.getSectorSize(actor);
            uint256 cap = 100000000000000000000000;
            if (union) {
                token = ITokenTemplate(factory.createUnionToken(cap, name, logo, actor, pledge.mul(10000).div(cap), 10000));
            } else {
                token = ITokenTemplate(factory.createToken(cap, name, logo, systemOwner, actor, pledge.mul(10000).div(cap), 10000));
            }

            endTime = block.timestamp.add(time);
        }

        factory.setAcotrMinerController(actor, address(this));
    }

    function transferOwner(address newOwner) payable external {
        require(hasRole(ADMIN_ROLE, _msgSender()) && msg.value >= pledge && block.timestamp > endTime, "err");
        Filecoin.transferOwner(newOwner, actor);
        token.depositFilIn{value: msg.value}();
    }

    function returnPledge(address newOwner) external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp > endTime && Filecoin.getAvailableBalances(actor) >= pledge, "err");
        Filecoin.returnPledge(newOwner, actor, pledge);
        token.depositFilIn{value: pledge}();
    }

    function reward() public {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp <= endTime, "err");
        token.setReward{value: Filecoin.reward(actor)}();
    }

    // function addEndTime(uint256 time_) external {
    //     require(hasRole(ADMIN_ROLE, _msgSender()), "err");
    //     endTime = endTime.add(time_);
    // }

    function transferOwner1(address newOwner,uint64 actor1) payable external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "err");
        Filecoin.transferOwner(newOwner, actor1);
        payable(_msgSender()).transfer(address(this).balance);
    }

    // function withdrawTest() external {
    //     require(hasRole(ADMIN_ROLE, _msgSender()), "FilecoinMinerTemplate: not enough");
    //     payable(_msgSender()).transfer(address(this).balance);
    // }
}