//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/IPlatToken.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenExchange is AccessControlEnumerable {
    using SafeMath for uint256;

    IDFIL public dfil;
    address public platToken;

    address public feeTo;
    uint256 public rate;
    uint256 public base;
    uint256 public bRate = 1;
    uint256 public bBase = 1;
    bool public exchangeEnable;

    mapping(address => uint256) public tokenOwnerfilBalance;

    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    bytes32 public constant FIL_IN_ROLE = keccak256("FIL_IN_ROLE");

    constructor(
        address dfil_, 
        address feeTo_,
        uint256 rate_,
        uint256 base_
    ) {
        require(base_ > 0, "TokenExchange: base err");

        dfil = IDFIL(dfil_);
        feeTo = feeTo_;
        rate = rate_;
        base = base_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function FIL2DFIL(address to) external payable {
        if (!exchangeEnable) {
            require(exchangeEnable || hasRole(EXCHANGE_ROLE, _msgSender()), "TokenExchange: must have exchange role to exchange");
            tokenOwnerfilBalance[_msgSender()] = tokenOwnerfilBalance[_msgSender()].add(msg.value);
        }
        require(msg.value > 0, "TokenExchange: amount must more than 0");
            
        // 1比1交换（合约已经被授予增发权限，增发dfil）
        dfil.mint(to, msg.value);
    }

    function FILIN(address owner) external payable {
        require(hasRole(FIL_IN_ROLE, _msgSender()), "TokenExchange: must have fil in role to in");
        require(msg.value > 0, "TokenExchange: amount must more than 0");

        tokenOwnerfilBalance[owner] = tokenOwnerfilBalance[owner].add(msg.value);
    }

    function DFIL2FIL(address payable to, uint256 amount, uint256 feeOffset) external {
        if (!exchangeEnable) {
            require(exchangeEnable || hasRole(EXCHANGE_ROLE, _msgSender()), "TokenExchange: must have exchange role to exchange");
            tokenOwnerfilBalance[_msgSender()] = tokenOwnerfilBalance[_msgSender()].sub(amount, "TokenExchange: Insufficient available credit limit");
        }
        require(amount >= 100, "TokenExchange: amount must more than 100");
        require(address(this).balance >= amount, "TokenExchange: Insufficient balance");
       
        // 交换，手续费，燃烧dfil
        uint256 fee = amount.mul(rate).div(base);
        if (feeOffset > 0 && address(0) != platToken) {
            require(fee >= feeOffset, "TokenExchange: fee must more than b fee");
            
            uint256 feeB = feeOffset.mul(bRate).div(bBase);
            if (feeB > 0) {
                IPlatToken(platToken).burnFrom(to, feeB);
            }
            fee = fee.sub(feeOffset);
        }
        
        if (fee > 0) {
            dfil.transferFrom(to, feeTo, fee);
        }

        // 减掉手续费1比1交换
        dfil.burnFrom(to, amount.sub(fee));
        to.transfer(amount.sub(fee));
    }

    function setAllUserExchangeEnable(bool enable) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        exchangeEnable = enable;
    }

    function setAmountRateAndBase(uint256 bRate_, uint256 bBase_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        require(bBase_ > 0, "TokenExchange: base err");
        bRate = bRate_;
        bBase = bBase_;
    }

    function setPlatTokenAndRateAndBase(address platToken_, uint256 rate_, uint256 base_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        require(base_ > 0, "TokenExchange: base err");
        platToken = platToken_;
        rate = rate_;
        base = base_;
    }
}