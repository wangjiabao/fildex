// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract DFIL is ERC20PresetMinterPauser {
    uint256 private immutable _cap;

    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant GRANT_WHITE_ROLE = keccak256("GRANT_WHITE_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    bool public whiteEnable = true;
    mapping(address => bool) public white;

    constructor(uint256 cap_) ERC20PresetMinterPauser("DFIL", "dfil") {
        require(cap_ > 0, "DFIL: cap is 0");
        _cap = cap_*10**decimals();

        _grantRole(SUPER_ADMIN_ROLE, _msgSender());
        _grantRole(GRANT_WHITE_ROLE, _msgSender());
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function mint(address to, uint256 amount) public override {
        require(ERC20.totalSupply() + amount <= cap(), "DFIL: cap exceeded");
        super.mint(to, amount);
    }

    function burn(uint256 amount) public override {
        require(hasRole(BURNER_ROLE, _msgSender()), "DFIL: must have burner role to burn");
        super.burn(amount);
    }
   
    function burnFrom(address account, uint256 amount) public override {
        require(hasRole(BURNER_ROLE, _msgSender()), "DFIL: must have burner role to burn");
        super.burnFrom(account, amount);
    }
    
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        require(!whiteEnable || white[from] || white[to], "DFIL: not exists white");
        super._transfer(from, to, amount);
    }

    function setWhiteEnable() external {
        require(hasRole(SUPER_ADMIN_ROLE, _msgSender()), "DFIL: must have super admin role to set");
        whiteEnable = true;
    }

    function setWhite(address account, bool enable) external {
        require(hasRole(GRANT_WHITE_ROLE, _msgSender()), "DFIL: must have grant white role to set");
        white[account] = enable;
    }

    function getWhiteEnable() external view returns(bool) {
        return whiteEnable;
    }
}
