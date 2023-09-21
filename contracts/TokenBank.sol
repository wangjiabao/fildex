//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/ITokenBankReward.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenBank is AccessControlEnumerable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");

    IDFIL public dfil;
    ITokenBankReward public keyReward;
    ITokenBankReward public dfilReward;
    EnumerableSet.AddressSet private _rewardCoins;
    mapping(address => bool) public rewardCoinsType; // 类型，按次false，按金额true

    uint256 public total;
    mapping(address => uint256) public userBalance;
    mapping(address => uint256[]) public userBalanceRecord;

    event InDfil(address indexed account, uint256 amount);
    event OutDfil(address indexed account, uint256 amount);
    event Reward(address indexed account);

    modifier onlySuperAdminRole() {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenFactory: must have super admin role to set");
        _;
    }

    constructor(address dfil_, address keyReward_, address dfilReward_) {
        dfil = IDFIL(dfil_);
        keyReward = ITokenBankReward(keyReward_);
        dfilReward = ITokenBankReward(dfilReward_);

        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
    }

    /**
     * 质押dfil
     */
    function inDfil(uint256 amount) external {
        require(amount > 0, "TokenBank: amount err");
        
        dfil.transferFrom(_msgSender(), address(this), amount);

        keyReward.record(_msgSender(), amount);
        dfilReward.record(_msgSender(), amount);
        if (_rewardCoins.length() > 0) {
            for (uint256 i = 0; i < _rewardCoins.length(); i++) {
                ITokenBankReward(_rewardCoins.at(i)).record(_msgSender(), amount);
            }
        }

        userBalance[_msgSender()] = userBalance[_msgSender()].add(amount);
        userBalanceRecord[_msgSender()].push(amount);
        total = total.add(amount);

        emit InDfil(_msgSender(), amount);
    }

    /**
     * 全部解压
     */
    function outAllDfil() external {
        require(userBalance[_msgSender()] > 0, "TokenBank: amount err");

        keyReward.outRecord(_msgSender());
        dfilReward.outRecord(_msgSender());
        if (_rewardCoins.length() > 0) {
            for (uint256 i = 0; i < _rewardCoins.length(); i++) {
                ITokenBankReward(_rewardCoins.at(i)).outRecord(_msgSender());
            }
        }

        uint256 amount = userBalance[_msgSender()];
        delete userBalance[_msgSender()];
        delete userBalanceRecord[_msgSender()];
        total = total.sub(amount);

        dfil.transfer(_msgSender(), amount);

        emit OutDfil(_msgSender(), amount);
    }

    /**
     * 解压某一个
     */
    function outDfil(uint256 at) external {
        uint256 amount = userBalanceRecord[_msgSender()][at];
        require(amount > 0, "TokenBank: amount err");

        keyReward.outRecordKeyAt(_msgSender(), at);
        dfilReward.outRecord(_msgSender(), amount);
        if (_rewardCoins.length() > 0) {
            for (uint256 i = 0; i < _rewardCoins.length(); i++) {
                if (rewardCoinsType[_rewardCoins.at(i)]) {
                    ITokenBankReward(_rewardCoins.at(i)).outRecord(_msgSender(), amount);
                } else {
                    ITokenBankReward(_rewardCoins.at(i)).outRecordKeyAt(_msgSender(), at);
                }
            }
        }

        if (amount >= userBalance[_msgSender()]) {
            amount = userBalance[_msgSender()];
            delete userBalance[_msgSender()];
        } else {
            userBalance[_msgSender()] = userBalance[_msgSender()].sub(amount);
        }

        total = total.sub(amount);
        delete userBalanceRecord[_msgSender()][at];

        dfil.transfer(_msgSender(), amount);

        emit OutDfil(_msgSender(), amount);
    }

    /**
     * 提取收益
     */
    function reward() external {
        keyReward.reward(_msgSender());
        dfilReward.reward(_msgSender());
        if (_rewardCoins.length() > 0) {
            for (uint256 i = 0; i < _rewardCoins.length(); i++) {
                ITokenBankReward(_rewardCoins.at(i)).reward(_msgSender());
            }
        }

        emit Reward(_msgSender());
    }

    function getUserBalanceRecordAt(address account, uint256 at) external view returns (uint256) {
        return userBalanceRecord[account][at];
    }

    function getUserBalanceRecordLength(address account) external view returns (uint256) {
        return userBalanceRecord[account].length;
    }

    function getUserBalance(address account) external view returns (uint256) {
        return userBalance[account];
    }

    function getRewardCoins() external view returns (address[] memory) {
        return _rewardCoins.values();
    }

    // super admin
    function addRewardCoin(address coin, bool stakeType) external onlySuperAdminRole {
        _rewardCoins.add(coin);
        rewardCoinsType[coin] = stakeType;
    }

    function removeRewardCoin(address coin) external onlySuperAdminRole {
        _rewardCoins.remove(coin);
    }
}