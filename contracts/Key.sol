//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract Key is ERC20PresetMinterPauser {
    
    bytes32 public constant GRANT_BURNER_ROLE = keccak256("GRANT_BURNER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor() ERC20PresetMinterPauser("KEY", "key") {
        _setRoleAdmin(BURNER_ROLE, GRANT_BURNER_ROLE);
    }

    function burn(uint256 amount) public override {}
   
    function burnFrom(address account, uint256 amount) public override  {
        require(hasRole(BURNER_ROLE, _msgSender()), "Key: must have burner role to burn");
        super.burnFrom(account, amount);
    }

    // tokenFactory
    function setBurner(address account) external {
        grantRole(BURNER_ROLE, account);
    }
}