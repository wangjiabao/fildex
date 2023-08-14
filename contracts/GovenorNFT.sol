// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IKey.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";

contract GovenorNFT is AccessControlEnumerable, ERC721, EIP712, ERC721Enumerable, ERC721Votes {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    uint256 start;
    uint256 private _cap = 10000;
    IKey public key;
    Counters.Counter private _tokenIdTracker;

    constructor(address key_, address account, uint256 start_) ERC721("GovenorNFT", "GovenorNFT") EIP712("GovenorNFT", "1") {
        start = start_;
        key = IKey(key_);
        for (uint256 i = 0; i < 10; i++) {
            safeMint(account);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

     /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    function _mint(address to, uint256 tokenId) internal override {
        super._mint(to, tokenId);
        require(totalSupply() <= cap(), "GovenorNFT: cap exceeded");
    }

    function exchange(uint256 amount) public {
        require(start <= block.timestamp, "GovenorNFT: not open");
        require(amount.mul(100) >= key.totalSupply(), "GovenorNFT: amount not enough");
        key.burnFrom(_msgSender(), amount);
        safeMint(_msgSender());
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
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Votes) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerable, ERC721, ERC721Enumerable) returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }
}