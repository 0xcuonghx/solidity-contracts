// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./EIP712Validator.sol";

contract ERC721LazyMint is ERC721, ReentrancyGuard, Ownable, EIP712Validator {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {}

    function safeMint() public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
    }

    function lazyMint(
        Mint721Data calldata data,
        bytes calldata signature
    ) external payable nonReentrant {
        require(data.to != address(0), "invalid destination");
        uint256 tokenId = _tokenIdCounter.current();

        // Verify data
        _verify(data, signature);

        _safeMint(data.to, tokenId);

        _tokenIdCounter.increment();
    }

    function _isValidSigner(
        address signer
    ) internal view virtual override returns (bool) {
        return msg.sender == signer;
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
}
