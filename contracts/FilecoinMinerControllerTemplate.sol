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

    // todo 
    uint256 public constant TIME_1 = 250000;
    // uint256 public constant TIME_1 = 15552000;
    uint256 public constant TIME_2 = 31104000;
    uint256 public constant TIME_3 = 46656000;

    uint64 public actor;
    IFilecoinMinerTemplate public miner;
    uint256 public due;
    address payable public owner;
    uint256 public timeType;
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
        timeType = createData.timeType;
        extraTime = createData.extraTime;
    }

    /**
     * 接受权限转移给映射合约
     */
    function acceptOwnerAndCreateToken(
        string memory name,
        string memory logo
    ) external {
        require(_msgSender() == owner && block.timestamp <= due && 1 <= timeType && 3 >= timeType, "err");
        miner.transferOwner(address(miner));
        if (address(0) == address(token)) {
            pledge = miner.getPledge();
            // todo 
            // uint256 cap = miner.getSectorSize(actor);
            uint256 cap = 10*1024*1024*1024*1024*1024; // 10p
            if (union) {
                token = ITokenTemplate(factory.createUnionToken(cap, name, logo, actor, pledge.mul(10000).div(cap), 10000));
            } else {
                token = ITokenTemplate(factory.createToken(cap, name, logo, owner, actor, pledge.mul(10000).div(cap), 10000));
            }

            if (1 == timeType) {
                endTime = block.timestamp.add(TIME_1);
            } else if (2 == timeType) {
                endTime = block.timestamp.add(TIME_2);
            } else if (3 == timeType) {
                endTime = block.timestamp.add(TIME_3);
            }
        }

        factory.setAcotrMinerController(actor, address(this));
    }

    function transferOwner() payable external {
        require(_msgSender() == owner && msg.value >= pledge && block.timestamp > endTime && block.timestamp <= endTime + extraTime, "err");
        miner.transferOwner(owner);
        token.depositFilIn{value: msg.value}();
    }

    function returnPledge() external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp > endTime + extraTime && miner.getMinerAvailableBalances() >= pledge, "err");
        miner.returnPledge(owner, pledge);
        token.depositFilIn{value: pledge}();
    }

    function reward() external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && block.timestamp <= endTime + extraTime, "err");
        token.setReward{value: miner.reward()}();
    }

    // factory default admin
    function adminTransferOwner(address newOwner, address payable account) external {
        require(address(factory) == _msgSender(), "err");
        miner.transferOwner(newOwner);
        account.transfer(address(this).balance);
    }

    function adminWithdraw(address payable account) external {
        require(address(factory) == _msgSender(), "err");
        account.transfer(address(this).balance);
    }
    
    receive() external payable {}
}