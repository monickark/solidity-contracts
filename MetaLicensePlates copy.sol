// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";

contract MetaLicensePlatesUpgrade is
    ERC721AUpgradeable,
    ERC2981Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using Strings for uint256;

    bytes32 public merkleRoot;
    mapping(address => bool) public whitelistClaimed;

    string public uri;

    uint256 public mintPrice;
    uint256 public maxSupply;
    uint256 public maxPerWallet;

    bool public paused;
    bool public whitelistMintEnabled;
    bool public publicMintEnabled;
    bool public privateMintEnabled;

    address payable public withdrawWallet;
    address payable public royaltyOwner;

    uint96 revenueShareInBips;

    /**
     * @dev Emitted when while mint `quantity` no of token 
     * from `tokenId` to `tokenOwner`.
     */
    event TokenMinted(uint256 quantity, uint256 indexed tokenId, address tokenOwner);

    /**
     * @dev Emitted when owner mint `quantity` no of token 
     * from `tokenId` to `tokenOwner`.
     */
    event TokenMintedForAddress(uint256 quantity, uint256 indexed tokenId, address tokenOwner);

    /**
     * @dev Emitted when admin mint `quantity` no of token from `
     * tokenId` to whitelisted users `tokenOwner`.
     */
    event WhitelistedTokenMinted(uint256 quantity, uint256 indexed tokenId, address tokenOwner);

    /**
     * @dev Emitted when admin mint `quantity` no of token from 
     * `tokenId` to whitelisted users `tokenOwner`.
     */
    event TokenTransferred(uint256 indexed tokenId, address sender, address receiver);
  
    /**
     * @dev Emitted when Revenue share transferred while transfer token for token `tokenId` 
     * to `tokenOwner`.
     */
    event RevenueShareTransferred(
        uint256 _tokenId,
        uint256 saleAmt,
        uint256 revenueShare,
        address _receiver
    );  

    /**
     * @dev Initializes the contract 
     * ***PARAMETERS***
     *  token name
     *  token symbol
     *  mint price
     *  max token supply
     *  maximum token per wallet
     *  withdrawl wallet adddress
     *  token url,
     *  revenue share percentage in bips
     *  royalty fee percentage in bips 
     *
     *  initialize default values
     *  Set royalty info and transfer ownership
     */
    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _mintPrice,
        uint256 _maxSupply,
        uint256 _maxPerWallet,
        address payable _withdrawWallet,
        string memory _uri,
        uint96 _revenueShareInBips,
        uint96 _royaltyFeesInBips,
        address payable _royaltyOwner
    ) public initializerERC721A initializer {
        __ERC721A_init(_tokenName, _tokenSymbol);
        __Ownable_init();
        setMintPrice(_mintPrice);
        seturi(_uri);
        transferOwnership(_msgSender());
        maxSupply = _maxSupply;
        maxPerWallet = _maxPerWallet;
        withdrawWallet = _withdrawWallet;
        paused = false;
        whitelistMintEnabled = true;
        publicMintEnabled = false;
        privateMintEnabled = true;
        revenueShareInBips = _revenueShareInBips;
        royaltyOwner = _royaltyOwner;
        setRoyaltyInfo(_royaltyOwner, _royaltyFeesInBips);
    }
    
     /**
     * @dev to check the provided quantity is exceeded with already minted nfts
     */
    modifier mintCompliance(uint256 _quantity) {
        require(
            totalSupply() + _quantity <= maxSupply,
            "Max supply exceeded, Sold out!"
        );
        _;
    }

    /**
     * @dev to check the msg.value is enough to mint token by multiplying mint price & quantity
     */
    modifier mintPriceCompliance(uint256 _quantity) {
        require(msg.value >= mintPrice * _quantity, "Wrong value!");
        _;
    }

    /**
     * @dev mint `_quantity` amount of token to caller `_msgSender()`.
     *
     * check the `quantity` not exceeded total supply using `mintComplier` modifier
     * check the `msg.value` ia greater than than price to mint uding `mintPriceCompliance` modifier
     *
     * Emits a {TokenMinted} event.
     */
    function mint(uint256 _quantity)
        external
        payable
        mintCompliance(_quantity)
        mintPriceCompliance(_quantity)
    {
        require(!paused, "The contract is paused!");
        require(publicMintEnabled, "minting not enabled");
        require(
            (balanceOf(_msgSender()) + _quantity) <= maxPerWallet,
            "Exceed max per wallet"
        );
        _safeMint(_msgSender(), _quantity);
        emit TokenMinted(_quantity, _nextTokenId(), _msgSender());
    }

    /**
     * @dev mint `_quantity` amount of token to a address `_receiver` from owner .
     *
     * check the `quantity` not exceeded total supply using `mintComplier` modifier
     *
     * add receiver in _tokenOwnerList & mint token
     * Emits a {TokenMintedForAddress} event.
     */
    function mintForAddress(uint256 _quantity, address _receiver)
        external
        mintCompliance(_quantity)
        onlyOwner
    {
        require(privateMintEnabled, "private minting not enabled");
        require(
            balanceOf(_receiver) + _quantity < maxPerWallet,
            "Exceed max per wallet"
        );
        _safeMint(_receiver, _quantity);        
        emit TokenMintedForAddress(_quantity, _nextTokenId(), _msgSender());
    }

    /**
     * @dev mint `_quantity` amount of token to a whitelist address `_msgSender()` .
     *
     * Note: `_merkleProof` is the proof of merkle tree to identify the caller is whitelisted using merkle root.
     * Emits a {WhitelistedTokenMinted} event.
     */
    function whitelistMint(uint256 _quantity, bytes32[] calldata _merkleProof)
        external
        payable
        mintCompliance(_quantity)
        mintPriceCompliance(_quantity)
    {
        // Verify whitelist requirements
        require(whitelistMintEnabled, "whitelist sale is not enabled!");
        require(!whitelistClaimed[_msgSender()], "Already claimed!");
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
        require(
            MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, leaf),
            "Invalid proof!"
        );
        whitelistClaimed[_msgSender()] = true;
        _safeMint(_msgSender(), _quantity);
        emit WhitelistedTokenMinted(_quantity, _nextTokenId(), _msgSender());
    }

    /**
     * @dev transfers `tokenId` token from `_msgSender()` to `_receiver`.
     *
     * Emits a {TokenTransferred} event.
     */
    function transfer(uint256 _tokenId, address _receiver) external {
        require(_exists(_tokenId), "Token not existed");
        safeTransferFrom(_msgSender(), _receiver, _tokenId);
        emit TokenTransferred(_tokenId, _msgSender(), _receiver);
    }

    /**
     * @dev transfer revenue share amount to the owner of the token
     * token `_tokenId` using sale amount `_saleAmt` from caller.
     *
     * Emits a {RevenueShareTransferred} event.
     */
    function transferRevenueShare(uint256 _tokenId, uint256 _saleAmt)
        external
        payable
    {      
        require(_msgSender() == royaltyOwner, "Invalid royalty owner.");
        uint256 _revenueShare = calcRevenueShare(_tokenId, _saleAmt);
        require(_revenueShare == msg.value, "Invalid Revenue share");        
        address user = ownerOf(_tokenId);
        (bool success, ) = payable(user).call{value: _revenueShare}("");
        require(success, "Transfer failed");
        emit RevenueShareTransferred(
            _tokenId,
            _saleAmt,
            _revenueShare,
            user
        );
    }

     /**
     * @dev withdraw contract balance to `withdrawWallet`.
     */   
    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = withdrawWallet.call{value: address(this).balance}("");
        require(success, "withdraw failed");
    }   

    /**
     * @dev set mint price for token.
     **/
    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    /**
     * @dev set url for token.
     **/
    function seturi(string memory _uri) public onlyOwner {
        uri = _uri;
    }

    /*** VIEW FUNCTIONS ***/

     /**
     * @dev calculate & returns revenue share amount for token id `_tokenId` using sale amount `_saleAmt`.
     *
     * Note: Check token id already minted and return revenue share amount
     */
    function calcRevenueShare(uint256 _tokenId, uint256 _saleAmt)
        public
        view
        returns (uint256)
    {
        require(_exists(_tokenId), "Token not existed");
        return (_saleAmt * revenueShareInBips) / _feeDenominator();
    }

    /**
     * @dev get balance of the contract.
     **/
    function getBalance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev toggle the pause/unpause for nft minting.
     **/
    function setPaused(bool _state) external onlyOwner {
        paused = _state;
    }

    /**
     * @dev set merkle root hash.
     **/
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev toggle the whitelist minting enable or not for nft minting.
     **/
    function setWhitelistMintEnabled(bool _state) external onlyOwner {
        whitelistMintEnabled = _state;
    }

     /**
     * @dev toggle the public minting enable or not for nft minting.
     **/
    function setPublicMintEnabled(bool _publicMintEnabled_) external onlyOwner {
        publicMintEnabled = _publicMintEnabled_;
    }

    /**
     * @dev toggle the private minting enable or not for nft minting.
     **/
    function setPrivateMintEnabled(bool _privateMintEnabled_)
        external
        onlyOwner
    {
        privateMintEnabled = _privateMintEnabled_;
    }

    /**
     * @dev set maximum no of token can mint using this contract.
     **/
    function updateMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    /**
     * @dev update wallet of the amount withdrawl account from contract.
     **/
    function updateWithdraWallet(address payable _withdrawWallet)
        external
        onlyOwner
    {
        withdrawWallet = _withdrawWallet;
    }

    /**
     * @dev update How many tokens maximum a wallet can mint.
     **/
    function updateMaxPerWallet(uint256 _maxPerWallet) external onlyOwner {
        maxPerWallet = _maxPerWallet;
    }

    /**
     * @dev get token URI of the specified token `_tokenId`.
     **/
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        ".json"
                    )
                )
                : "";
    }    

    /**
     * @dev set royalty percentage to the royalty owner.
     **/
    function setRoyaltyInfo(address _receiver, uint96 _royaltyFeesInBips)
        public
        onlyOwner
    {
        _setDefaultRoyalty(_receiver, _royaltyFeesInBips);
        royaltyOwner = payable(_receiver);
    }

    /**
     * @dev view base url of the tokens.
     **/
    function _baseURI() internal view virtual override returns (string memory) {
        return uri;
    }

     /**
     * @dev See {IERC2981-supportsInterface}.
     */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721AUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
