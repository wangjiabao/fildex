//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDFIL.sol";
import "./interfaces/ITokenExchange.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TokenOwnerTemplate is Initializable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _users; // 全部用户
    mapping(address => uint256) public usersAt;
    mapping(address => address) private _userWithTopUsers;// 用户上级
    mapping(address => EnumerableSet.AddressSet) private _userWithLowUsers;// 用户下级

    address private _factory; // 工厂
    ITokenExchange public pool; // 兑换池

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address pool_
    ) initializer public {
        require(address(0) == _factory, "TokenOwnerTemplate: factory is not zero address");

        _factory = msg.sender;
        pool = ITokenExchange(pool_);
        _users.add(owner_);
        usersAt[owner_] = block.timestamp;
    }

    // 工厂合约调用绑定用户关系
    function setUser(address account, address recommendAccount) external {
        require(_factory == msg.sender, "TokenOwnerTemplate: not factory");
        require(!_users.contains(account), "TokenOwnerTemplate: exists user");
        require(_users.contains(recommendAccount), "TokenOwnerTemplate: not exists recommend user");
        require(account != recommendAccount, "TokenOwnerTemplate: error address");

        _users.add(account);
        usersAt[account] = block.timestamp;
        _userWithTopUsers[account] = recommendAccount; 
        _userWithLowUsers[recommendAccount].add(account);
    }

    // 获取用户
    function exsitsUser(address account) external view returns (bool) {
        return _users.contains(account);
    }

    function getUsers() external view returns (address[] memory) {
        return _users.values();
    }

    function getUsersAt(address account) external view returns (uint256) {
        return usersAt[account];
    }

    function getLowUsers(address account) external view returns (address[] memory) {
        return _userWithLowUsers[account].values();
    }

    function getTopUser(address account) external view returns (address) {
        return _userWithTopUsers[account];
    }

    function FIL2DFIL() external payable {
        require(_users.contains(msg.sender), "TokenOwnerTemplate: not exists user");
        require(msg.value >= 100, "TokenOwnerTemplate: amount must more than 100");

        pool.FIL2DFIL{value: msg.value}(msg.sender);
    }

    function DFIL2FIL(address payable to, uint256 amount, uint256 offset) external {
        require(_users.contains(msg.sender), "TokenOwnerTemplate: not exists user");
        require(_users.contains(to), "TokenOwnerTemplate: not exists user");
        require(amount >= 100, "TokenOwnerTemplate: amount must more than 100");

        pool.DFIL2FIL(to, amount, offset);
    }
}