//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IFilecoinMinerControllerTemplate.sol";
import "./interfaces/IFilecoinMinerTemplate.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/ITokenTemplate.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FilecoinMinerControllerTemplate is Initializable {
    using SafeMath for uint256;

    uint256 public constant TIME = 7776000;
    uint256 public constant TIME_LIMIT = 2592000;

    uint64 public actor;
    IFilecoinMinerTemplate public miner;
    uint256 public due;
    address payable public owner;
    uint256 public timeType;
    uint256 public rewardStartTime;
    uint256 public rewardStartTimeLimit;
    uint256 public endTime;
    uint256 public extraTime;
    uint256 public pledge;
    bool public notReturnPledge; // 检查用，属于冗余的操作了，owner权限转移后此合约废掉，更丝滑一下。

    bool public meetsConsensusMinimum;
    uint256 public cap; // 扇区大小

    ITokenFactory public factory;
    ITokenTemplate public token;
    bool public union;


    constructor() {
        _disableInitializers();
    }

    function initialize(IFilecoinMinerControllerTemplate.CreateData calldata createData) initializer public returns (bool) {
        actor = createData.actor;
        miner = IFilecoinMinerTemplate(createData.miner);
        owner = createData.owner;
        due = block.timestamp.add(createData.due);
        factory = ITokenFactory(createData.factory);
        union = createData.union;
        timeType = createData.timeType;
        extraTime = createData.extraTime;
        rewardStartTimeLimit = createData.rewardStartTime;
        notReturnPledge = true;
        return true;
    }

    /**
     * 接受权限转移给映射合约
     */
    function acceptOwnerAndCreateToken(
        string memory name,
        string memory logo
    ) external {
        require(msg.sender == owner && notReturnPledge && block.timestamp <= due && 12 >= timeType, "err");
        miner.transferOwner(address(miner));
        if (address(0) == address(token)) {
            pledge = miner.getPledge();

            (meetsConsensusMinimum, cap) = miner.minerRawPower();
            cap = cap.mul(10);
            if (union) {
                token = ITokenTemplate(factory.createUnionToken(cap, name, logo, actor, pledge));
            } else {
                token = ITokenTemplate(factory.createToken(cap, name, logo, owner, actor, pledge));
            }

            endTime = block.timestamp.add(TIME+TIME_LIMIT*timeType);
            rewardStartTime = block.timestamp.add(rewardStartTimeLimit);

            factory.setAcotrMinerController(actor, address(this));
        }
    }

    /**
     * 接收抵押币fil，归还抵押币，归还owner权限
     */
    function transferOwner(address newOwner) payable external {
        if (
            block.timestamp > endTime && 
            block.timestamp <= endTime + extraTime && 
            notReturnPledge && 
            msg.sender == owner
        ) { // 到期和加时内，抵押币未还且输入金额满足抵押币
            miner.transferOwner(newOwner);
            token.depositFilIn{value: msg.value}();
            require(token.getDepositAllIn(), "not enough deposit");

            notReturnPledge = false;
            return;
        } else if (!notReturnPledge && msg.sender == owner) { // 抵押币已还，未接受owner转移，换账户接受
            miner.transferOwner(newOwner);
            return;
        }  else if (block.timestamp > endTime + extraTime) { // 加时后，提够抵押币，不限制，可以一直提
            uint256 tmpCurrentPledge = miner.withdraw();
            token.depositFilIn{value: tmpCurrentPledge}();
            if (token.getDepositAllIn()) {
                notReturnPledge = false;
            }
            return;
        }
            
        require(false, "not enough");     
    }

    /**
     * 中心化驱动程序，驱动分红，调用算力代币合约方法
     */
    function reward() external {
        require(block.timestamp > rewardStartTime && block.timestamp <= endTime + extraTime && notReturnPledge, "err");
        token.setReward{value: miner.withdraw()}();
    }

    function changeWorkerAddress(address new_worker, address[] memory controls) external {
        require(msg.sender == owner, "err");
        miner.changeWorkerAddress(new_worker, controls);
    }

    function confirmChangeWorkerAddress() external {
        require(msg.sender == owner, "err");
        miner.confirmChangeWorkerAddress();
    }

    function minerRawPower() external {
        require(msg.sender == owner && !meetsConsensusMinimum, "err");
        (meetsConsensusMinimum, cap) = miner.minerRawPower();
        cap = cap.mul(10);
    }

    // factory default admin
    function adminTransferOwner(address newOwner) external {
        require(msg.sender == address(factory), "err");
        miner.transferOwner(newOwner);
    }

    function returnPledge() payable external {
        token.depositFilIn{value: msg.value}();
    }

    function adminWithdraw(address payable account) external {
        require(msg.sender ==  address(factory), "err");
        if (0 < address(this).balance) {
            account.transfer(address(this).balance);
        }
    }

    function adminReward() payable external {
        require(msg.sender ==  address(factory), "err");
        token.setReward{value: msg.value}();
    }
    
    receive() external payable {}
}