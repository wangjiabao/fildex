//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IPlatToken.sol";
import "./interfaces/ITokenFactory.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenExchange is AccessControlEnumerable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant GRANT_TOKEN_ROLE = keccak256("GRANT_TOKEN_ROLE");
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    uint256 public defaultAdminRoleLimit;

    // 理财地址和金额
    address public dao;
    address payable public manager;
    uint256 public managerAmount;

    ITokenFactory public factory;
    IDFIL public dfil;
    IPlatToken public platToken;

    uint256 public rate = 2;
    uint256 public base = 1000;
    uint256 public bRate = 1;
    uint256 public bBase = 1;
    address payable public feeTo;
    uint256 public allFee;

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
    event EXCHANGEOWNERFILComplated(address indexed token, address owner, uint256 sellCostAmount, uint256 sellProfitAmount);
    event WITHDRAWFILComplated(address indexed token, address owner, uint256 amount, uint256 feeOffset);
    event FILINComplated(address indexed token, address owner, uint256 amount);
    event DFIL2FILExchanged(address indexed user, uint256 amount, uint256 relAmount, uint256 fee);
    event FILLOCKComplated(address indexed token, address owner, uint256 amount, uint256 sellAmount);
    event FILRECORDComplated(address indexed token, address owner, uint256 amount, uint256 sellAmount);
    event feeToWithdrawComplated(address indexed feeTo, uint256 amount);
    event AccountCreated(address indexed user, uint256 rate);
    event AccountRemoved(address indexed user);
    event ManagerWithdrawForFilComplated(address indexed manager, uint amount);

    modifier onlyDefaultAdminRole() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenExchange: must have default admin role to set");
        require(block.timestamp <= defaultAdminRoleLimit, "TokenExchange: default admin role expired");
        _;
    }

    modifier onlySuperAdminRole() {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenExchange: must have super admin role to set");
        _;
    }

    constructor(
        address factory_,
        address dao_,
        address dfil_,
        address payable feeTo_,
        uint256 defaultAdminRoleLimit_
    ) {
        factory = ITokenFactory(factory_);
        dfil = IDFIL(dfil_);
        feeTo = feeTo_;
        dao = dao_;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(TOKEN_ROLE, GRANT_TOKEN_ROLE);
        _grantRole(GRANT_TOKEN_ROLE, factory_);

        defaultAdminRoleLimit = defaultAdminRoleLimit_;
    }

    /**
     * fil进，更新节点商流动性
     */
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

    /**
     * fil出，更新节点商流动性，平台币抵消手续费
     */
    function DFIL2FIL(uint256 amount, uint256 feeOffset) external nonReentrant {
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
        if (address(this).balance < amount.sub(fee)) {
            require(callManagerForFil(amount.sub(fee).sub(address(this).balance)), "TokenExchange: fil not enough");
        }
        payable(_msgSender()).transfer(amount.sub(fee));

        checkIfAllowAndSetAccountUnionWithAmount(factory.getUserOwnerByAccount(_msgSender()));

        emit DFIL2FILExchanged(_msgSender(), amount, amount.sub(fee), fee);
    }

    /**
     * 工厂合约调用，成为节点商时，流动性独立到节点商下，顶级用户移除相应的流动性数据，更新节点商流动性
     */
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

    /**
     * 算力合约调用，联合算力发售，更新节点商流动性，并判断是否额度够用异常返回
     */
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

    /**
     * 算力合约调用，独立算力发售，更新节点商流动性
     */
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

    /**
     * 算力合约调用，独立发售/联合发售，提现节点商售卖金额/提现发行商售卖金额，平台币抵消手续费
     */
    function WITHDRAWFIL(address payable owner, uint256 amount, uint256 feeOffset) external nonReentrant {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(0 < amount, "TokenExchange: amount must more than 0");

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
        if (address(this).balance < amount.sub(fee)) {
            require(callManagerForFil(amount.sub(fee).sub(address(this).balance)), "TokenExchange: fil not enough");
        }
        owner.transfer(amount.sub(fee));

        emit WITHDRAWFILComplated(_msgSender(), owner, amount, feeOffset);
    }

    /**
     * 算力合约调用，归还抵押币
     */
    function FILIN(address owner) external payable {
        require(hasRole(TOKEN_ROLE, _msgSender()), "TokenExchange: must have token role");
        require(factory.existsOwner(factory.getUserOwnerByAccount(owner)), "TokenExchange: not owner");
        require(msg.value >= 0, "TokenExchange: amount err");

        tokenOwnerFilBalance[owner] = tokenOwnerFilBalance[owner] + msg.value.toInt256();

        checkIfAllowAndSetAccountUnionWithAmount(owner);
        
        emit FILINComplated(_msgSender(), owner, msg.value);
    }

    /**
     * 算力合约调用，收益分红fil进
     */
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

    /**
     * 设置联合算力开启
     */
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

    /**
     * 设置联合算力关闭
     */
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

    /**
     * 流动性检测并更新数据方法
     */
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

    /**
     * 节点商提现
     */
    function feeToWithdraw() external nonReentrant {
        require(feeTo == _msgSender(), "TokenExchange: not feeTo");
        require(0 < allFee, "TokenExchange: fee not enough");

        uint256 tmpAllFee = allFee;
        allFee = 0;
        dfil.burn(tmpAllFee);
        if (address(this).balance < tmpAllFee) {
            require(callManagerForFil(tmpAllFee.sub(address(this).balance)), "TokenExchange: fil not enough");
        }
        feeTo.transfer(tmpAllFee);

        emit feeToWithdrawComplated(feeTo, tmpAllFee);
    }

    /**
     * 理财提现
     */
    function managerWithdrawForFil(uint256 amount) external nonReentrant {
        require(manager == _msgSender(), "TokenExchange: not manager");
        require(address(this).balance >= amount, "TokenExchange: not enough");

        managerAmount = managerAmount.add(amount);
        manager.transfer(amount);
        emit ManagerWithdrawForFilComplated(_msgSender(), amount);
    }

    /**
     * 从理财处取得fil
     */
    function callManagerForFil(uint256 amount) internal returns (bool) {
        if (address(0) == manager) {
            return false;
        }

        if (0 == managerAmount) {
            return false;
        }

        uint256 balanceFil = address(this).balance;
        IManager(manager).repay(amount);
        if (address(this).balance >= balanceFil.add(amount)) {
            managerAmount = managerAmount.sub(amount);
            return true;
        }

        return false;
    }

    // dao
    function setManager(address payable manager_) external {
        require(dao == _msgSender(), "TokenExchange: not dao");
        require(address(0) != manager_, "TokenExchange: err manager");
        manager = manager_;
    }

    function withdrawAndDeleteManager() external {
        require(dao == _msgSender(), "TokenExchange: not dao");
        callManagerForFil(managerAmount);
        manager = payable(address(0));
        managerAmount = 0;
    }

    // tokenFactory
    function setTokenRole(address token) external {
        grantRole(TOKEN_ROLE, token);
    }

    // super admin
    function setFee(uint256 rate_) external onlySuperAdminRole {
        require(20 >= rate, "TokenExchange: rate err");
        rate = rate_;
    }

    function setFeeTo(address payable feeTo_) external onlySuperAdminRole {
        feeTo = feeTo_;
    }

    function setAllUserExchangeEnable(bool enable) external onlySuperAdminRole {
        exchangeEnableNoLimit = enable;
    }

    function setPlatTokenAndRateAndBase(address platToken_, uint256 rate_, uint256 base_) external onlySuperAdminRole {
        require(base_ > 0, "TokenExchange: base err");
        platToken = IPlatToken(platToken_);
        bRate = rate_;
        bBase = base_;
    }

    // default admin
    function withdrawAll() external onlyDefaultAdminRole nonReentrant {
        callManagerForFil(managerAmount);
        payable(_msgSender()).transfer(address(this).balance);
    }

    function setFactory(address factory_) external onlyDefaultAdminRole {
       factory = ITokenFactory(factory_);
    }

    receive() external payable {}
}