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
    bool notReturnPledge; // 检查用，属于冗余的操作了，owner权限转移后此合约废掉，更丝滑一下。

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

        notReturnPledge = true;
    }

    /**
     * 接受权限转移给映射合约
     */
    function acceptOwnerAndCreateToken(
        string memory name,
        string memory logo
    ) external {
        require(_msgSender() == owner && notReturnPledge && block.timestamp <= due && 1 <= timeType && 3 >= timeType, "err");
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

    /**
     * 接收抵押币fil，归还抵押币，归还owner权限
     */
    function transferOwner() payable external {
        require(_msgSender() == owner && notReturnPledge && msg.value >= pledge && block.timestamp > endTime && block.timestamp <= endTime + extraTime, "err");
        notReturnPledge = false;
        miner.transferOwner(owner);
        token.depositFilIn{value: msg.value}();
    }

    /**
     * 中心化驱动程序，提取余额归还抵押币，归还owner权限
     */
    function returnPledge() external {
        require(hasRole(DRIVER_ROLE, _msgSender()) && notReturnPledge && block.timestamp > endTime + extraTime && miner.getMinerAvailableBalances() >= pledge, "err");
        notReturnPledge = false;
        miner.returnPledge(owner, pledge);
        token.depositFilIn{value: pledge}();
    }

    /**
     * 中心化驱动程序，驱动分红，调用算力代币合约方法
     */
    function reward() external {
        require(block.timestamp <= endTime + extraTime && notReturnPledge, "err");
        token.setReward{value: miner.reward()}();
    }

    // factory default admin
    function adminTransferOwner(address newOwner) external {
        require(address(factory) == _msgSender() && notReturnPledge, "err");
        notReturnPledge = false;
        miner.transferOwner(newOwner);
    }

    function adminWithdraw(address payable account) external {
        require(address(factory) == _msgSender(), "err");
        if (0 < address(this).balance) {
            account.transfer(address(this).balance);
        }
    }
    
    receive() external payable {}
}