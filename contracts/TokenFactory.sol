//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/IKey.sol";
import "./interfaces/ITokenTemplate.sol";
import "./interfaces/IFilecoinMinerControllerTemplate.sol";
import "./interfaces/IFilecoinMinerTemplate.sol";
import "./interfaces/ITokenExchange.sol";
import "./interfaces/IPlatToken.sol";
import "./interfaces/ITokenBankReward.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenFactory is AccessControlEnumerable {
    using Clones for address;
    using SafeCast for uint256;
    using SafeMath for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant CALL_PAIR_SETTER_ROLE = keccak256("CALL_PAIR_SETTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATE_TOKEN_ROLE = keccak256("CREATE_TOKEN_ROLE");

    uint public defaultAdminRoleLimit;

    address public superAdmin;
    address public defaultAdmin;
    uint256 public idoStartTime = 5*24*3600;

    IDFIL public dfil;
    IKey public key;
    ITokenBankReward public bankRewardDfil;
    ITokenExchange public tokenExchange;
    address public filecoinMinerControllerTemplate;
    address public filecoinMinerTemplate;
    address public tokenTemplate;
    address public tokenUnionTemplate;
    address public swapFactory;
    address public callPair;

    // 用户的集合
    address payable public top;
    EnumerableSet.AddressSet private _users;
    mapping(address => uint256) public usersAt;
    mapping(address => address) public userWithTopUsers;
    mapping(address => EnumerableSet.AddressSet) private _userWithLowUsers;

    // 节点商的集合
    EnumerableSet.AddressSet private _checkOwners;
    EnumerableSet.AddressSet private _owners;

    // 用户与节点商的关联
    mapping(address => address) public userWithTokenOwner;
    mapping(address => EnumerableSet.AddressSet) private _tokenOwnerUsers;

    // 节点商的节点集合，节点与控制合约的关联
    EnumerableSet.UintSet private _topUnionAcotrMiners;
    mapping(uint64 => IFilecoinMinerControllerTemplate.CheckData) private _topUnionAcotrMinersCheckData;
    mapping(address => EnumerableSet.UintSet) private _tokenOwnerAcotrMiners;
    mapping(address => mapping(uint64 => IFilecoinMinerControllerTemplate.CheckData)) private _tokenOwnerAcotrMinersCheckData;
    mapping(address => mapping(uint64 => address)) public ownerActorCurrentControllers;
    mapping(address => IFilecoinMinerControllerTemplate.CheckData) public controllerCheckData;
    mapping(uint64 => address) public acotrMinerController; // 节点与控制合约的映射

    EnumerableSet.AddressSet private _tokens;
    mapping(address => EnumerableSet.AddressSet) private _tokenOwnerTokens;
    EnumerableSet.AddressSet private _topUnionTokens;

    event UserCreated(address indexed user);
    event CheckOwnerCreated(address indexed owner);
    event OwnerCreated(address indexed owner);
    event OwnerAcotrMinersCreated(address indexed owner, uint64 miner);
    event TopAcotrMinersCreated(address indexed owner, uint64 miner);
    event ActorMinerControllerCreated(address indexed owner, address controller, address miner);
    event TokenCreated(address indexed owner, address token);
    event UnionTokenCreated(address indexed owner, address token);

    modifier onlyDefaultAdminRole() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "TokenFactory: must have default admin role to set");
        require(block.timestamp <= defaultAdminRoleLimit, "TokenFactory: default admin role expired");
        _;
    }

    modifier onlySuperAdminRole() {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "TokenFactory: must have super admin role to set");
        _;
    }

    modifier onlyAdminRole() {
        require(hasRole(ADMIN_ROLE, _msgSender()), "TokenFactory: must have admin role to set");
        _;
    }

    modifier onlyCallPairSetterRole() {
        require(hasRole(CALL_PAIR_SETTER_ROLE, _msgSender()), "TokenFactory: must have call pair setter role to set");
        _;
    }

    constructor(
        address dfil_,
        address key_,
        address filecoinMinerControllerTemplate_,
        address filecoinMinerTemplate_,
        address tokenTemplate_,
        address tokenUnionTemplate_,
        address bankRewardDfil_,
        address payable top_,
        address defaultAdmin_,
        uint256 defaultAdminRoleLimit_
    ) {
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());
        _grantRole(CALL_PAIR_SETTER_ROLE, _msgSender());

        superAdmin = _msgSender();
        defaultAdminRoleLimit = defaultAdminRoleLimit_;
        dfil = IDFIL(dfil_);
        key = IKey(key_);
        filecoinMinerControllerTemplate = filecoinMinerControllerTemplate_;
        filecoinMinerTemplate = filecoinMinerTemplate_;
        tokenTemplate = tokenTemplate_;
        tokenUnionTemplate = tokenUnionTemplate_;
        bankRewardDfil = ITokenBankReward(bankRewardDfil_);
        defaultAdmin = defaultAdmin_;

        top = top_;
        _users.add(top);
        usersAt[top] = block.timestamp;
        userWithTopUsers[top] = top;
        userWithTokenOwner[top] = top;
        _owners.add(top);
    }

    /**
     * 新增用户
     */
    function setUser(address recommendAccount) external {
        require(_msgSender() != recommendAccount, "TokenFactory: error address");
        require(!_users.contains(_msgSender()), "TokenFactory: exists user");
        require(_users.contains(recommendAccount), "TokenFactory: not exists recommend user");

        _users.add(_msgSender());
        usersAt[_msgSender()] = block.timestamp;
        userWithTopUsers[_msgSender()] = recommendAccount; 
        _userWithLowUsers[recommendAccount].add(_msgSender());

        if (top == recommendAccount) {
            userWithTokenOwner[_msgSender()] = _msgSender();
        } else {
            userWithTokenOwner[_msgSender()] = userWithTokenOwner[recommendAccount];
            _tokenOwnerUsers[userWithTokenOwner[recommendAccount]].add(_msgSender()); 
        }

        emit UserCreated(_msgSender());
    }

    /**
     * 用户创建成为节点商申请，仅限1级用户
     */
    function createCheckOwner() external {
        require(!_checkOwners.contains(_msgSender()), "TokenFactory: exists request message");
        require(!_owners.contains(_msgSender()), "TokenFactory: exists owner");
        require(top == userWithTopUsers[_msgSender()], "TokenFactory: recommend user is not top user");

        _checkOwners.add(_msgSender());
        emit CheckOwnerCreated(_msgSender());
    }

    /**
     * 管理员移除申请
     */
    function removeCheckOwner(address owner) external onlyAdminRole {
        if (_checkOwners.contains(owner)) {
            _checkOwners.remove(owner);
        }
    }

    /**
     * 管理员通过用户成为节点商申请，创建用户节点商信息
     */
    function createTokenOwner(address payable owner) external onlyAdminRole {
       require(address(0) != owner, "TokenFactory: onwer zero address");
        require(!_owners.contains(owner), "TokenFactory: exists owner");
        require(top == userWithTopUsers[owner], "TokenFactory: recommend is not top");
        require(address(0) != address(tokenExchange), "TokenFactory: not exists token exchange");
        
        if (_checkOwners.contains(owner)) {
            _checkOwners.remove(owner);
        }

        _owners.add(owner);
        tokenExchange.ownerFilBalanceChange(owner);

        emit OwnerCreated(owner);
    }

    /**
     * 节点商创建发售独立算力节点申请
     */
    function createTokenOwnerAcotrMiners(
        uint64 actor,
        uint256 costRatePerToken,
        uint256 costBasePerToken,
        uint256 profitRatePerToken,
        uint256 profitBasePerToken,
        uint256 timeType
    ) external {
        require(_owners.contains(_msgSender()), "TokenFactory: not exists owner");
        if (!_tokenOwnerAcotrMiners[_msgSender()].contains(actor)) {
            _tokenOwnerAcotrMiners[_msgSender()].add(actor);
            _tokenOwnerAcotrMinersCheckData[_msgSender()][actor] = IFilecoinMinerControllerTemplate.CheckData(
                costRatePerToken,
                costBasePerToken,
                profitRatePerToken,
                profitBasePerToken,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                timeType
            );
            ownerActorCurrentControllers[_msgSender()][actor] = address(0);
        }

        emit OwnerAcotrMinersCreated(_msgSender(), actor);
    }

    /**
     * 顶级用户（发行商）创建发售联合算力节点申请
     */
    function createTopAcotrMiners(
        uint64 actor,
        uint256 costRatePerToken,
        uint256 costBasePerToken,
        uint256 profitRatePerToken,
        uint256 profitBasePerToken,
        uint256 timeType
    ) external {
        require(top == _msgSender(), "TokenFactory: not top");
        if (!_topUnionAcotrMiners.contains(actor)) {
            _topUnionAcotrMiners.add(actor);
            _topUnionAcotrMinersCheckData[actor] = IFilecoinMinerControllerTemplate.CheckData(
                costRatePerToken,
                costBasePerToken,
                profitRatePerToken,
                profitBasePerToken,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                timeType

            );
            ownerActorCurrentControllers[top][actor] = address(0);
        }

        emit TopAcotrMinersCreated(top, actor);
    }

    /**
     * 移除独立算力发售申请
     */
    function removeTokenOwnerAcotrMiners(address owner, uint64 actor) external onlyAdminRole {
        if (_tokenOwnerAcotrMiners[owner].contains(actor)) {
            _tokenOwnerAcotrMiners[owner].remove(actor);
            delete _tokenOwnerAcotrMinersCheckData[owner][actor];
            delete ownerActorCurrentControllers[owner][actor];
        }
    }

    /**
     * 移除联合算力发售申请
     */
    function removeTopAcotrMiners(uint64 actor) external onlyAdminRole {
        if (_topUnionAcotrMiners.contains(actor)) {
            _topUnionAcotrMiners.remove(actor);
            delete _topUnionAcotrMinersCheckData[actor];
            delete ownerActorCurrentControllers[top][actor];
        }
    }

    /**
     * 通过申请并创建算力映射节点合约，映射节点合约的控制器合约
     */
    function createActorMinerController(
        IFilecoinMinerControllerTemplate.CreateControllerData memory createControllerData
    ) external onlyAdminRole returns (address filecoinControllerMiner, address filecoinMiner) {
        uint256 tmpTimeType;
        if (createControllerData.union) {
            require(_topUnionAcotrMiners.contains(createControllerData.actor), "TokenFactory: not exists actor miner");
            tmpTimeType = _topUnionAcotrMinersCheckData[createControllerData.actor].timeType;
        } else {
            require(_tokenOwnerAcotrMiners[createControllerData.owner].contains(createControllerData.actor), "TokenFactory: not exists actor miner");
            tmpTimeType =  _tokenOwnerAcotrMinersCheckData[createControllerData.owner][createControllerData.actor].timeType;
        }
        
        filecoinControllerMiner = filecoinMinerControllerTemplate.clone();
        require(address(0) != filecoinControllerMiner, "TokenFactory: invalid token address");
        filecoinMiner = filecoinMinerTemplate.clone();
        require(address(0) != filecoinMiner, "TokenFactory: invalid token address");

        require(IFilecoinMinerControllerTemplate(filecoinControllerMiner).initialize(IFilecoinMinerControllerTemplate.CreateData(
            superAdmin,
            _msgSender(),
            createControllerData.owner,
            createControllerData.actor,
            filecoinMiner,
            createControllerData.due,
            address(this),
            createControllerData.union,
            tmpTimeType,
            createControllerData.extraTime
        )), "TokenFactory: init err");

        require(IFilecoinMinerTemplate(filecoinMiner).initialize(createControllerData.actor, payable(filecoinControllerMiner)), "TokenFactory: init err");

        _grantRole(CREATE_TOKEN_ROLE, filecoinControllerMiner);
        ownerActorCurrentControllers[createControllerData.owner][createControllerData.actor] = filecoinControllerMiner;
        
        uint256 stakeType;
        if (1 == createControllerData.stakeType) {
            stakeType = 1;
        } else if (2 == createControllerData.stakeType) {
            stakeType = 2;
        }

        require(1 == createControllerData.rewardRate.add(createControllerData.rewardOwnerRate).add(createControllerData.rewardBankRate).div(createControllerData.rewardBase), "TokenFactory: reward rate err");

        if (createControllerData.union) {
            controllerCheckData[filecoinControllerMiner] = IFilecoinMinerControllerTemplate.CheckData(
                _topUnionAcotrMinersCheckData[createControllerData.actor].costRatePerToken,
                _topUnionAcotrMinersCheckData[createControllerData.actor].costBasePerToken,
                _topUnionAcotrMinersCheckData[createControllerData.actor].profitRatePerToken,
                _topUnionAcotrMinersCheckData[createControllerData.actor].profitBasePerToken,
                stakeType,
                createControllerData.stakeTypeRate,
                createControllerData.stakeTypeBase,
                createControllerData.rewardOwnerRate,
                createControllerData.rewardRate,
                createControllerData.rewardBase,
                createControllerData.rewardBankRate,
                tmpTimeType
            );
        } else {
            controllerCheckData[filecoinControllerMiner] = IFilecoinMinerControllerTemplate.CheckData(
                _tokenOwnerAcotrMinersCheckData[createControllerData.owner][createControllerData.actor].costRatePerToken,
                _tokenOwnerAcotrMinersCheckData[createControllerData.owner][createControllerData.actor].costBasePerToken,
                _tokenOwnerAcotrMinersCheckData[createControllerData.owner][createControllerData.actor].profitRatePerToken,
                _tokenOwnerAcotrMinersCheckData[createControllerData.owner][createControllerData.actor].profitBasePerToken,
                stakeType,
                createControllerData.stakeTypeRate,
                createControllerData.stakeTypeBase,
                createControllerData.rewardOwnerRate,
                createControllerData.rewardRate,
                createControllerData.rewardBase,
                createControllerData.rewardBankRate,
                tmpTimeType
            );
        }

        emit ActorMinerControllerCreated(createControllerData.owner, filecoinControllerMiner, filecoinMiner);
    }

    /**
     * 节点控制器合约调用，权限转移给节点映射合约时触发，绑定当前节点号和控制器 
     */
    function setAcotrMinerController(uint64 actor, address controller) external {
        require(hasRole(CREATE_TOKEN_ROLE, _msgSender()), "Token: must have create token role to set");
        acotrMinerController[actor] = controller;
    }

    /**
     * 节点控制器合约调用，权限转移给节点映射合约时触发，创建算力合约
     */
    function createToken(
        uint256 cap,
        string memory name,
        string memory logo,
        address payable owner,
        uint64 actor,
        uint256 pledge
    ) external returns (address token) {
        require(hasRole(CREATE_TOKEN_ROLE, _msgSender()), "TokenFactory: must have create token role to create");
        require(_owners.contains(owner), "TokenFactory: not exists owner");
        require(address(0) != address(tokenExchange), "TokenFactory: not exists token exchange");
        require(address(0) != defaultAdmin, "TokenFactory: not exists default admin");
        
        token = tokenTemplate.clone();
        require(address(0) != token, "TokenFactory: invalid token address");

        tokenExchange.setTokenRole(token);
        if (dfil.getWhiteEnable()) {
            dfil.setWhite(token, true);
        }
        key.setBurner(token);
        bankRewardDfil.setRewarder(token);

        require(ITokenTemplate(token).initialize(
            ITokenTemplate.CreateData(
                idoStartTime,
                cap,
                name,
                logo,
                address(dfil), 
                address(key), 
                address(tokenExchange), 
                address(bankRewardDfil),
                actor,
                superAdmin,
                defaultAdmin,
                owner,
                controllerCheckData[_msgSender()].costRatePerToken,
                controllerCheckData[_msgSender()].costBasePerToken,
                controllerCheckData[_msgSender()].profitRatePerToken,
                controllerCheckData[_msgSender()].profitBasePerToken,
                pledge,
                _msgSender(),
                swapFactory,
                callPair,
                controllerCheckData[_msgSender()].stakeType,
                controllerCheckData[_msgSender()].stakeTypeRate,
                controllerCheckData[_msgSender()].stakeTypeBase,
                controllerCheckData[_msgSender()].rewardOwnerRate,
                controllerCheckData[_msgSender()].rewardBase,
                controllerCheckData[_msgSender()].rewardRate,
                controllerCheckData[_msgSender()].rewardBase,
                controllerCheckData[_msgSender()].rewardBankRate,
                controllerCheckData[_msgSender()].rewardBase
            )
        ), "TokenFactory: init err");
    
        _tokens.add(token);
        _tokenOwnerTokens[owner].add(token);

        emit TokenCreated(owner, token);
    }

    /**
     * 节点控制器合约调用，权限转移给节点映射合约时触发，创建联合算力合约
     */
    function createUnionToken(
        uint256 cap,
        string memory name,
        string memory logo,
        uint64 actor,
        uint256 pledge
    ) external returns (address token) {
        require(hasRole(CREATE_TOKEN_ROLE, _msgSender()), "TokenFactory: must have create token role to create");
        require(address(0) != address(tokenExchange), "TokenFactory: not exists token exchange");
        require(address(0) != defaultAdmin, "TokenFactory: not exists default admin");

        token = tokenUnionTemplate.clone();
        require(address(0) != token, "TokenFactory: invalid token address");

        tokenExchange.setTokenRole(token);
        if (dfil.getWhiteEnable()) {
            dfil.setWhite(token, true);
        }

        key.setBurner(token);
        bankRewardDfil.setRewarder(token);

        require(ITokenTemplate(token).initialize(
            ITokenTemplate.CreateData(
                idoStartTime,
                cap,
                name,
                logo,
                address(dfil), 
                address(key), 
                address(tokenExchange), 
                address(bankRewardDfil),
                actor,
                superAdmin,
                defaultAdmin,
                top,
                controllerCheckData[_msgSender()].costRatePerToken,
                controllerCheckData[_msgSender()].costBasePerToken,
                controllerCheckData[_msgSender()].profitRatePerToken,
                controllerCheckData[_msgSender()].profitBasePerToken,
                pledge,
                _msgSender(),
                swapFactory,
                callPair,
                controllerCheckData[_msgSender()].stakeType,
                controllerCheckData[_msgSender()].stakeTypeRate,
                controllerCheckData[_msgSender()].stakeTypeBase,
                controllerCheckData[_msgSender()].rewardOwnerRate,
                controllerCheckData[_msgSender()].rewardBase,
                controllerCheckData[_msgSender()].rewardRate,
                controllerCheckData[_msgSender()].rewardBase,
                controllerCheckData[_msgSender()].rewardBankRate,
                controllerCheckData[_msgSender()].rewardBase
            )
        ), "TokenFactory: init err");

        _topUnionTokens.add(token);

        emit UnionTokenCreated(top, token);
    }

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }

    function existsUser(address account) external view returns (bool) {
        return _users.contains(account);
    }

    function getLowUsers(address account) external view returns (address[] memory) {
        return _userWithLowUsers[account].values();
    }

    function getTop() external view returns (address) {
        return top;
    }

    function getCheckOwners() external view returns (address[] memory) {
        return _checkOwners.values();
    }

    function existsCheckOwner(address owner) external view returns (bool) {
        return _checkOwners.contains(owner);
    }

    function getOwners() external view returns (address[] memory) {
        return _owners.values();
    }

    function existsOwner(address owner) external view returns (bool) {
        return _owners.contains(owner);
    }

    function getOwnerUsers(address owner) external view returns (address[] memory) {
        return _tokenOwnerUsers[owner].values();
    }

    function getUserOwner() external view returns (address) {
        return userWithTokenOwner[_msgSender()];
    }

    function getUserOwnerByAccount(address account) external view returns (address) {
        return userWithTokenOwner[account];
    }

    function getOwnerActorMiners(address owner) external view returns (uint256[] memory) {
        return _tokenOwnerAcotrMiners[owner].values();
    }

    function getTokenOwnerActorMinersCheckData(address owner, uint64 actor) external view returns (IFilecoinMinerControllerTemplate.CheckData memory) {
        return _tokenOwnerAcotrMinersCheckData[owner][actor];
    }

    function getTopActorMiners() external view returns (uint256[] memory) {
        return _topUnionAcotrMiners.values();
    }

    function getTopActorMinersCheckData(uint64 actor) external view returns (IFilecoinMinerControllerTemplate.CheckData memory) {
        return _topUnionAcotrMinersCheckData[actor];
    }

    function existsOwnerActorMiner(address owner, uint64 actor) external view returns (bool) {
        return _tokenOwnerAcotrMiners[owner].contains(actor);
    }
    
    function getTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    function getTopUnionTokens() external view returns (address[] memory) {
        return _topUnionTokens.values();
    }

    function existsToken(address token) external view returns (bool) {
        return _tokens.contains(token);
    }

    function existsTopUnionToken(address token) external view returns (bool) {
        return _topUnionTokens.contains(token);
    }

    function getTokenOwnerTokens(address owner) external view returns (address[] memory) {
        return _tokenOwnerTokens[owner].values();
    }

    function getOwnerActorCurrentControllers(address account, uint64 actor) external view returns (address) {
        return ownerActorCurrentControllers[account][actor];
    }

    function getCheckOwnersByIndex(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _checkOwners.length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _checkOwners.at(i);
        }

        return data;
    }

    function getOwnersByIndex(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _owners.length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _owners.at(i);
        }

        return data;
    }

    function getOwnerAcotrMinersByIndex(address owner, uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        require(startIndex >= 0 && endIndex <= _tokenOwnerAcotrMiners[owner].length() && endIndex >= startIndex, "TokenFactory: index err");

        uint256[] memory data = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _tokenOwnerAcotrMiners[owner].at(i);
        }

        return data;
    }

    function getTopAcotrMinersByIndex(uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        require(startIndex >= 0 && endIndex <= _topUnionAcotrMiners.length() && endIndex >= startIndex, "TokenFactory: index err");

        uint256[] memory data = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _topUnionAcotrMiners.at(i);
        }

        return data;
    }

    function getTokensByIndex(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _tokens.length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _tokens.at(i);
        }

        return data;
    }

    function getTopUnionTokensByIndex(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _topUnionTokens.length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _topUnionTokens.at(i);
        }

        return data;
    }

    function getUsersByIndex(uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _users.length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _users.at(i);
        }

        return data;
    }

    function getUserWithLowUsersByIndex(address user, uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _userWithLowUsers[user].length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _userWithLowUsers[user].at(i);
        }

        return data;
    }

    function getTokenOwnerUsersByIndex(address owner, uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _tokenOwnerUsers[owner].length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _tokenOwnerUsers[owner].at(i);
        }

        return data;
    }

    function getTokenOwnerTokensByIndex(address owner, uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        require(startIndex >= 0 && endIndex <= _tokenOwnerTokens[owner].length() && endIndex >= startIndex, "TokenFactory: index err");

        address[] memory data = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            data[i - startIndex] = _tokenOwnerTokens[owner].at(i);
        }

        return data;
    }

    // super admin
    function setIdoStartTime(uint256 timeStamp) external onlySuperAdminRole {
        idoStartTime = timeStamp;  
    }

    function setDefaultAdmin(address defaultAdmin_) external onlySuperAdminRole {
        defaultAdmin = defaultAdmin_;  
    }

    // call pair setter
    function setCallPair(address callPair_) external onlyCallPairSetterRole {
        callPair =  callPair_;
    }

    // default admin
    function setTokenExchange(address tokenExchange_) external onlyDefaultAdminRole {
        tokenExchange = ITokenExchange(tokenExchange_);
    }

    function setSwapFactory(address swapFactory_) external onlyDefaultAdminRole {
        swapFactory = swapFactory_;
    }

    function setT(address t) external onlyDefaultAdminRole {
        tokenTemplate = t;
    }

    function setTu(address t) external onlyDefaultAdminRole {
        tokenUnionTemplate = t;
    }

    function setF(address f) external onlyDefaultAdminRole {
        filecoinMinerControllerTemplate = f;
    }

    function setFM(address f) external onlyDefaultAdminRole {
        filecoinMinerTemplate = f;
    }

    function setB(address b) external onlyDefaultAdminRole {
        bankRewardDfil = ITokenBankReward(b);
    }

    function transferOwnerFilecoinMinerController(address controller, address newOwner) external onlyDefaultAdminRole {
        IFilecoinMinerControllerTemplate(controller).adminTransferOwner(newOwner);
    }

    function withdrawFilecoinMinerController(address controller, address payable account) external onlyDefaultAdminRole {
        IFilecoinMinerControllerTemplate(controller).adminWithdraw(account);
    }

    function returnPledge(address controller) payable external onlyDefaultAdminRole {
        IFilecoinMinerControllerTemplate(controller).returnPledge();
    }
}