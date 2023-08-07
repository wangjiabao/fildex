// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract BFIL is ERC20PresetMinterPauser{
    uint256 private immutable _cap;

    bytes32 public constant GRANT_MINTER_ROLE = keccak256("GRANT_MINTER_ROLE");
    bytes32 public constant GRANT_BURNER_ROLE = keccak256("GRANT_BURNER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(uint256 cap_) ERC20PresetMinterPauser("BFIL", "BF") {
        require(cap_ > 0, "ERC20Capped: cap is 0");
        _cap = cap_*10**decimals();
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
    function mint(address to, uint256 amount) public override  {
        require(ERC20.totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        super.mint(to, amount);
    }

    function burn(uint256 amount) public override  {
        
    }
   
    function burnFrom(address account, uint256 amount) public override  {
        require(hasRole(BURNER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have burner role to burn");
        super.burnFrom(account, amount);
    }

    function setMinter(address account) external {
        require(hasRole(GRANT_MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have grant minter role to grant");
        _setupRole(MINTER_ROLE, account);
    }

    function setBurner(address account) external {
        require(hasRole(GRANT_BURNER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have grant burner role to grant");
        _setupRole(BURNER_ROLE, account);
    }
}
