// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IKey.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";

contract GovenorNFT is AccessControlEnumerable, ERC721, EIP712,  ERC721Votes {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    uint256 start;
    uint256 private _cap = 10000;
    uint256 public totalSupply;
    IKey public key;
    Counters.Counter private _tokenIdTracker;
    bool init;
    address public initAccount;

    constructor(address key_, address account, uint256 start_) ERC721("GovenorNFT", "GovenorNFT") EIP712("GovenorNFT", "1") {
        start = start_;
        key = IKey(key_);
        initAccount = account;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

     /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    function _mint(address to, uint256 tokenId) internal override {
        require(totalSupply.add(1) <= cap(), "GovenorNFT: cap exceeded");
        super._mint(to, tokenId);
        totalSupply = totalSupply.add(1);
    }

    function _init() internal {
        for (uint256 i = 0; i < 10; i++) {
            safeMint(initAccount);
        }
        init = true; 
    }

    function exchange(uint256 amount) public {
        require(start <= block.timestamp, "GovenorNFT: not open");
        require(amount >= key.totalSupply().div(100), "GovenorNFT: amount not enough");

        if (!init) {
            _init();
        }

        key.burnFrom(_msgSender(), amount);
        safeMint(_msgSender());

        if (1 > totalSupply%2){
            safeMint(initAccount);
        }
    }

    function exchangeMore(uint256 amount) external  {
        uint256 currentTotalSupply = key.totalSupply();
        while(amount >= currentTotalSupply.div(100)) {
            exchange(currentTotalSupply.div(100));
            amount = amount.sub(currentTotalSupply.div(100)); 
            currentTotalSupply = key.totalSupply();
        }
    }

    function safeMint(address _to) private {
        _safeMint(_to,_tokenIdTracker.current());
        _tokenIdTracker.increment();
    }

    // The following functions are overrides required by Solidity.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Votes) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerable, ERC721) returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }
}