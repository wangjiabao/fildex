//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/IPlatToken.sol";
import "./interfaces/ITokenFactory.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenExchange is AccessControlEnumerable {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GRANT_TOKEN_ROLE = keccak256("GRANT_TOKEN_ROLE");
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    ITokenFactory public factory;
    IDFIL public dfil;
    IPlatToken public platToken;
    address payable public feeTo;
    uint256 public allFee;

    uint256 public rate = 2;
    uint256 public base = 100;
    uint256 public bRate = 1;
    uint256 public bBase = 1;

    bool public exchangeEnableNoLimit;
    mapping(address => int256) public tokenOwnerFilIn;
    mapping(address => int256) public tokenOwnerFilOut;
    mapping(address => int256) public tokenOwnerFilBalance;
    mapping(address => int256) public tokenOwnerDfilBalance;

    uint256 public unionRate = 30;
    uint256 public unionBase = 100;
    EnumerableSet.AddressSet private _accountUnion;
    mapping(address => uint256) public accountUnionRate;
    EnumerableSet.AddressSet private _allowAccountUnion;
    mapping(address => uint256) public allowAccountUnionAmount;

    event FIL2DFILExchanged(address indexed user, uint256 amount);
    event REWARDFIL2DFILExchanged(address indexed token, address owner, uint256 amount);
    event WITHDRAWOWNERFILComplated(address indexed token, address owner, uint256 sellCostAmount, uint256 sellProfitAmount, uint256 feeOffset);
    event EXCHANGEOWNERFILComplated(address indexed token, address owner, uint256 sellCostAmount, uint256 sellProfitAmount);
    event WITHDRAWOWNERUNIONFILComplated(address indexed token, address owner, uint256 sellProfitAmount, uint256 feeOffset);
    event WITHDRAWPROPOSERUNIONFILComplated(address indexed token, address owner, uint256 sellCostAmount, uint256 sellDepositAmount, uint256 feeOffset);
    event FILINComplated(address indexed token, address owner, uint256 amount);
    event DFIL2FILExchanged(address indexed user, uint256 amount, uint256 relAmount, uint256 fee);
    event FILLOCKComplated(address indexed token, address owner, uint256 amount, uint256 sellAmount);
    event FILRECORDComplated(address indexed token, address owner, uint256 amount, uint256 sellAmount);
    event feeToWithdrawComplated(address indexed feeTo, uint256 amount);
    event AccountCreated(address indexed user, uint256 rate);
    event AccountRemoved(address indexed user);

    constructor(
        address factory_,
        address dfil_,
        address payable feeTo_
    ) {
        factory = ITokenFactory(factory_);
        dfil = IDFIL(dfil_);
        feeTo = feeTo_;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(TOKEN_ROLE, GRANT_TOKEN_ROLE);
        _grantRole(GRANT_TOKEN_ROLE, factory_);
    }

    function FIL2DFIL() external payable {
        require(address(0) != factory.getUserOwnerByAccount(_msgSender()), "TokenExchange: not exists user");
        require(msg.value >= base, "TokenExchange: amount must more");

        if (!factory.existsOwner(factory.getUserOwnerByAccount(_msgSender()))) {
            tokenOwnerFilIn[factory.getTop()] = tokenOwnerFilIn[factory.getTop()] + msg.value.toInt256();
            tokenOwnerFilBalance[factory.getTop()] = tokenOwnerFilBalance[factory.getTop()] + msg.value.toInt256();
            tokenOwnerDfilBalance[factory.getTop()] = tokenOwnerDfilBalance[factory.getTop()] + msg.value.toInt256();
        }

        tokenOwnerFilIn[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerFilIn[factory.getUserOwnerByAccount(_msgSender())] + msg.value.toInt256();
        tokenOwnerFilBalance[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerFilBalance[factory.getUserOwnerByAccount(_msgSender())] + msg.value.toInt256();
        tokenOwnerDfilBalance[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerDfilBalance[factory.getUserOwnerByAccount(_msgSender())] + msg.value.toInt256();
        
        dfil.mint(_msgSender(), msg.value);

        checkIfAllowAndSetAccountUnionWithAmount(factory.getUserOwnerByAccount(_msgSender()));

        emit FIL2DFILExchanged(_msgSender(), msg.value);
    }

    function DFIL2FIL(uint256 amount, uint256 feeOffset) external {
        require(address(0) != factory.getUserOwnerByAccount(_msgSender()), "TokenExchange: not exists user");
        require(amount >= base, "TokenExchange: amount must more");
        require(address(this).balance >= amount, "TokenExchange: Insufficient balance");

        if (!factory.existsOwner(factory.getUserOwnerByAccount(_msgSender()))) {
            tokenOwnerFilOut[factory.getTop()] = tokenOwnerFilOut[factory.getTop()] + amount.toInt256();
            tokenOwnerFilBalance[factory.getTop()] = tokenOwnerFilBalance[factory.getTop()] - amount.toInt256();
            tokenOwnerDfilBalance[factory.getTop()] = tokenOwnerDfilBalance[factory.getTop()] - amount.toInt256();
        }

        tokenOwnerFilOut[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerFilOut[factory.getUserOwnerByAccount(_msgSender())] + amount.toInt256();
        tokenOwnerFilBalance[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerFilBalance[factory.getUserOwnerByAccount(_msgSender())] - amount.toInt256();
        tokenOwnerDfilBalance[factory.getUserOwnerByAccount(_msgSender())] = tokenOwnerDfilBalance[factory.getUserOwnerByAccount(_msgSender())] - amount.toInt256();
        
        if (exchangeEnableNoLimit) {
            if (factory.existsOwner(factory.getUserOwnerByAccount(_msgSender()))) {
                require(0 <= tokenOwnerFilBalance[factory.getUserOwnerByAccount(_msgSender())], "TokenExchange: Insufficient available credit limit");
            } else {
                require(0 <= tokenOwnerFilBalance[factory.getTop()], "TokenExchange: Insufficient available credit limit");      
            }
        }

        uint256 fee = amount.mul(rate).div(base);
        if (feeOffset > bBase && address(0) != address(platToken)) {
            require(fee >= feeOffset, "TokenExchange: fee must more than b fee");
            
            uint256 feeB = feeOffset.mul(bRate).div(bBase);
            if (feeB > 0) {
                platToken.burnFrom(_msgSender(), feeB);
            }
            fee = fee.sub(feeOffset);
        }

        if (fee > 0) {
            allFee = allFee.add(fee);
            dfil.transferFrom(_msgSender(), address(this), fee);
        }

        dfil.burnFrom(_msgSender(), amount.sub(fee));
        payable(_msgSender()).transfer(amount.sub(fee));

        checkIfAllowAndSetAccountUnionWithAmount(factory.getUserOwnerByAccount(_msgSender()));

        emit DFIL2FILExchanged(_msgSender(), amount, amount.sub(fee), fee);
    }

    function ownerFilBalanceChange(address owner) external {
        require(address(factory) == _msgSender(), "TokenExchange: not factory");

        if (factory.existsOwner(factory.getUserOwnerByAccount(owner))) {
            tokenOwnerFilIn[factory.getTop()] = tokenOwnerFilIn[factory.getTop()] - tokenOwnerFilIn[owner];
            tokenOwnerFilOut[factory.getTop()] = tokenOwnerFilOut[factory.getTop()] - tokenOwnerFilOut[owner];
            tokenOwnerFilBalance[factory.getTop()] = tokenOwnerFilBalance[factory.getTop()] - tokenOwnerFilBalance[owner];
            tokenOwnerDfilBalance[factory.getTop()] = tokenOwnerDfilBalance[factory.getTop()] - tokenOwnerDfilBalance[owner];
        }

        checkIfAllowAndSetAccountUnionWithAmount(factory.getUserOwnerByAccount(factory.getTop()));
    }

    function feeToWithdraw() external {
        require(feeTo == _msgSender(), "TokenExchange: not feeTo");
        uint256 tmpAllFee = allFee;
        allFee = 0;

        dfil.burn(tmpAllFee);
        feeTo.transfer(tmpAllFee);

        emit feeToWithdrawComplated(feeTo, tmpAllFee);
    }

    function FILLOCK(address owner, uint256 amount, uint256 sellAmount) external {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role to in");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");

        tokenOwnerFilOut[owner] = tokenOwnerFilOut[owner] + amount.toInt256();
        tokenOwnerFilBalance[owner] = tokenOwnerFilBalance[owner] - amount.toInt256();
        tokenOwnerDfilBalance[owner] = tokenOwnerDfilBalance[owner] - sellAmount.toInt256();
        require(exchangeEnableNoLimit || 0 <= tokenOwnerFilBalance[owner], "TokenExchange: Insufficient fil balance");

        checkIfAllowAndSetAccountUnionWithAmount(owner);

        emit FILLOCKComplated(_msgSender(), owner, amount, sellAmount);
    }

    function FILRECORDANDMINTDFIL(address owner, uint256 amount, uint256 sellAmount) external {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role to in");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(amount >= sellAmount, "TokenExchange: amount err");

        tokenOwnerFilBalance[owner] = tokenOwnerFilBalance[owner] - amount.toInt256();
        tokenOwnerDfilBalance[owner] = tokenOwnerDfilBalance[owner] - sellAmount.toInt256();
        dfil.mint(owner, amount.sub(sellAmount));

        checkIfAllowAndSetAccountUnionWithAmount(owner);

        emit FILRECORDComplated(_msgSender(), owner, amount, sellAmount);
    }

    function WITHDRAWOWNERFIL(address payable owner, uint256 sellCostAmount, uint256 sellProfitAmount, uint256 feeOffset) external {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(0 < sellCostAmount && 0 < sellProfitAmount, "TokenExchange: amount must more than 0");

        uint256 fee = sellCostAmount.add(sellProfitAmount).mul(rate).div(base);
        if (feeOffset > bBase && address(0) != address(platToken)) {
            require(fee >= feeOffset, "TokenExchange: fee must more than b fee");
            
            uint256 feeB = feeOffset.mul(bRate).div(bBase);
            if (feeB > 0) {
                platToken.burnFrom(_msgSender(), feeB);
            }

            fee = fee.sub(feeOffset);
        }

        if (fee > 0) {
            allFee = allFee.add(fee);
            dfil.transferFrom(_msgSender(), address(this), fee);
        }

        dfil.burnFrom(_msgSender(), sellCostAmount.add(sellProfitAmount).sub(fee));
        owner.transfer(sellCostAmount.add(sellProfitAmount).sub(fee));

        emit WITHDRAWOWNERFILComplated(_msgSender(), owner, sellCostAmount, sellProfitAmount, feeOffset);
    }

    function WITHDRAWOWNERUNIONFIL(address payable owner, uint256 sellProfitAmount, uint256 feeOffset) external {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(0 < sellProfitAmount, "TokenExchange: amount must more than 0");

        uint256 fee = sellProfitAmount.mul(rate).div(base);
        if (feeOffset > bBase && address(0) != address(platToken)) {
            require(fee >= feeOffset, "TokenExchange: fee must more than b fee");
            
            uint256 feeB = feeOffset.mul(bRate).div(bBase);
            if (feeB > 0) {
                platToken.burnFrom(_msgSender(), feeB);
            }

            fee = fee.sub(feeOffset);
        }

        if (fee > 0) {
            allFee = allFee.add(fee);
            dfil.transferFrom(_msgSender(), address(this), fee);
        }

        dfil.burnFrom(_msgSender(), sellProfitAmount.sub(fee));
        owner.transfer(sellProfitAmount.sub(fee));

        emit WITHDRAWOWNERUNIONFILComplated(_msgSender(), owner, sellProfitAmount, feeOffset);
    }

    function WITHDRAWPROPOSERUNIONFIL(address payable owner, uint256 sellCostAmount, uint256 sellDepositAmount, uint256 feeOffset) external {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(0 < sellCostAmount && 0 < sellDepositAmount, "TokenExchange: amount must more than 0");

        uint256 fee = sellCostAmount.add(sellDepositAmount).mul(rate).div(base);
        if (feeOffset > bBase && address(0) != address(platToken)) {
            require(fee >= feeOffset, "TokenExchange: fee must more than b fee");
            
            uint256 feeB = feeOffset.mul(bRate).div(bBase);
            if (feeB > 0) {
                platToken.burnFrom(_msgSender(), feeB);
            }

            fee = fee.sub(feeOffset);
        }

        if (fee > 0) {
            allFee = allFee.add(fee);
            dfil.transferFrom(_msgSender(), address(this), fee);
        }

        dfil.burnFrom(_msgSender(), sellCostAmount.add(sellDepositAmount).sub(fee));
        owner.transfer(sellCostAmount.add(sellDepositAmount).sub(fee));

        emit WITHDRAWPROPOSERUNIONFILComplated(_msgSender(), owner, sellCostAmount, sellDepositAmount, feeOffset);
    }

    function FILIN(address owner) external payable {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(msg.value >= 0, "TokenExchange: amount err");

        tokenOwnerFilBalance[owner] = tokenOwnerFilBalance[owner] + msg.value.toInt256();

        checkIfAllowAndSetAccountUnionWithAmount(owner);
        
        emit FILINComplated(_msgSender(), owner, msg.value);
    }

    function REWARDFIL2DFIL(address owner) external payable {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");

        require(msg.value > 0, "TokenExchange: amount must more than 0");

        tokenOwnerFilIn[owner] = tokenOwnerFilIn[owner] + msg.value.toInt256();
        tokenOwnerFilBalance[owner] = tokenOwnerFilBalance[owner] + msg.value.toInt256();
        tokenOwnerDfilBalance[owner] = tokenOwnerDfilBalance[owner] + msg.value.toInt256();
        dfil.mint(_msgSender(), msg.value);

        checkIfAllowAndSetAccountUnionWithAmount(owner);

        emit REWARDFIL2DFILExchanged(_msgSender(), owner, msg.value);
    }

    function setAccountUnion(uint256 userDefineRate) external {
        require(factory.existsOwner(_msgSender()), "TokenFactory: not exists owner");
        require(userDefineRate >= 15 && userDefineRate <= 100, "TokenFactory: err rate");
        if (!_accountUnion.contains(_msgSender())) {
            _accountUnion.add(_msgSender());
        }
        accountUnionRate[_msgSender()] = userDefineRate;

        checkIfAllowAndSetAccountUnionWithAmount(_msgSender());
        emit AccountCreated(_msgSender(), userDefineRate);
    }

    function removeAccountUnion() external {
        require(factory.existsOwner(_msgSender()), "TokenFactory: not exists owner");
        if (_accountUnion.contains(_msgSender())) {
            _accountUnion.remove(_msgSender());
            delete accountUnionRate[_msgSender()];

            if (_allowAccountUnion.contains(_msgSender())) {
                _allowAccountUnion.remove(_msgSender());
                delete allowAccountUnionAmount[_msgSender()];
            }
        }

        emit AccountRemoved(_msgSender());
    }

    function checkIfAllowAndSetAccountUnionWithAmount(address owner) internal {
        if (!factory.existsOwner(owner)) {
            return;
        }
        
        if (!_accountUnion.contains(owner)) {
            return;
        }

        if (
            tokenOwnerDfilBalance[owner] > 0 
            && tokenOwnerFilBalance[owner] > 0
            && tokenOwnerDfilBalance[owner].toUint256().mul(unionRate).div(unionBase) < tokenOwnerFilBalance[owner].toUint256()
            && tokenOwnerDfilBalance[owner].toUint256().mul(accountUnionRate[owner]).div(unionBase) < tokenOwnerFilBalance[owner].toUint256()
        ) {
            if (!_allowAccountUnion.contains(owner)) {
                _allowAccountUnion.add(owner);
            }
            
            allowAccountUnionAmount[owner] = tokenOwnerFilBalance[owner].toUint256().sub(tokenOwnerDfilBalance[owner].toUint256().mul(accountUnionRate[owner]).div(unionBase));
        } else if (_allowAccountUnion.contains(owner)) {
            _allowAccountUnion.remove(owner);
            delete allowAccountUnionAmount[owner];
        }
    }

    function setFeeTo(address payable feeTo_) external {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenExchange: must have super admin role to set");
        feeTo = feeTo_;
    }

    function setAllUserExchangeEnable(bool enable) external {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenExchange: must have admin role to set");
        exchangeEnableNoLimit = enable;
    }

    function setPlatTokenAndRateAndBase(address platToken_, uint256 rate_, uint256 base_) external {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenExchange: must have super admin role to set");
        require(base_ > 0, "TokenExchange: base err");
        platToken = IPlatToken(platToken_);
        bRate = rate_;
        bBase = base_;
    }

    function setAmountRateAndBase(uint256 rate_, uint256 base_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "TokenExchange: must have admin role to set");
        require(base_ > 0, "TokenExchange: base err");
        rate = rate_;
        base = base_;
    }

    function setPlatTokenAmountRateAndBase(uint256 rate_, uint256 base_) external {
        require(hasRole(ADMIN_ROLE, _msgSender()), "TokenExchange: must have admin role to set");
        require(base_ > 0, "TokenExchange: base err");
        bRate = rate_;
        bBase = base_;
    }

    function setTokenRole(address token) external {
        grantRole(TOKEN_ROLE, token);
    }

    function getTokenOwnerFilBalance(address owner) external view returns (int256) {
        return tokenOwnerFilBalance[owner];
    }

    function getTokenOwnerDfilBalance(address owner) external view returns (int256) {
        return tokenOwnerDfilBalance[owner];
    }

    function getExchangeEnableNoLimit() external view returns (bool) {
        return exchangeEnableNoLimit;
    }

    function existsAccountUnion() external view returns (bool) {
        return _accountUnion.contains(_msgSender());
    }

    function getAccountUnion() external view returns (address[] memory) {
        return _accountUnion.values();
    }

    function getAllowAccountUnion() external view returns (address[] memory) {
        return _allowAccountUnion.values();
    }

    function getAllowAccountUnionLength() external view returns (uint256) {
        return _allowAccountUnion.length();
    }

    function getAllowAccountUnionAt(uint256 i) external view returns (address) {
        return _allowAccountUnion.at(i);
    }

    function getAllowAccountUnionAmount(address account) external view returns (uint256) {
        return allowAccountUnionAmount[account];
    }

    function getAllowAccountUnionAmountTotal() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < _allowAccountUnion.length(); i++) {
            total = total.add(allowAccountUnionAmount[_allowAccountUnion.at(i)]);
        }

        return total;
    }

    // default admin
    function withdrawAll() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        payable(_msgSender()).transfer(address(this).balance);
    }

    function setFactory(address factory_) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        factory = ITokenFactory(factory_);
    }

    // function withdrawTest() external {
    //     require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
    //     payable(_msgSender()).transfer(address(this).balance);
    // }
}