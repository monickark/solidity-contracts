// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "./GAX_Artbits.sol";
import "./proxy/ArtbitsProxy.sol";

/**
 * @title ERC721Minter
 * @dev This Contract is used to interact with ERC721 Contract
 */
contract GAX_FNFT is ERC721Upgradeable {
    using StringsUpgradeable for uint256;

    struct NFT_Asset {
        uint256 nftAssetId;
        address nftAsset_owner;
        address erc20_addr;
        string artist;
    }

    string private _baseTokenURI;
    address public superAdmin;
    address public gaxAdmin;
    address public artbitAddr;

    uint256 public whiteList_count;
    uint256 public dexList_count;
    uint256 internal totalCommission;
    uint256 internal totalRoyalty;
    uint256 public erc20decimals;

    mapping(uint256 => NFT_Asset) private nftAssets;
    mapping(uint256 => string) private _tokenURIs;
    mapping(address => bool) private whiteList_addresses;
    mapping(address => bool) private dex_addresses;

    event ArtbitsMinted(
        uint256 indexed tokenId,
        address indexed _contractAddress,
        string _uri
    );

    event ArtbitTransferred(
        address sender,
        address recepient,
        uint256 assetId,
        uint256 amount
    );
    
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _BaseUri,
        address _gaxAdmin,        
        address _artbitAddr
    ) public virtual initializer {
        __ERC721_init(_name, _symbol);
        __Context_init_unchained();
        __ERC165_init_unchained();
        _baseTokenURI = _BaseUri;
        gaxAdmin = _gaxAdmin;
        artbitAddr = _artbitAddr;
        superAdmin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == gaxAdmin, "Caller is not Admin.");
        _;
    }

    modifier onlySuperAdmin() {
        require(msg.sender == superAdmin, "Caller is not Super Admin.");
        _;
    }

    modifier onlyArtbitToken(uint256 tokenId) {
        address artbitAddress = nftAssets[tokenId].erc20_addr;
        require(msg.sender == artbitAddress, "unauthorized");
        _;
    }

    function changeOwnership(address _newOwner) external onlyAdmin {
        require(_newOwner != address(0), "Invalid address!");
        gaxAdmin = _newOwner;
    }

    function changeSuperadmin(address _newAdmin) external onlySuperAdmin {
        require(_newAdmin != address(0), "Invalid address!");
        superAdmin = _newAdmin;
    }

    function changeArtbitAddress(address _newAddress) external onlySuperAdmin {
        require(_newAddress != address(0), "Invalid address!");
        artbitAddr = _newAddress;
    }

    /**
     * @notice This method is used to mint a token
     * @param _dex_rp dex royalty percentage for the nftAsset
     * @param _p2p_rp peer2peer royalty percentage for the nftAsset
     * @param _noOfArtbits totalsupply of erc20
     * @param _artist Artist of the asse
     */

    function mintToken(
        string memory _name,
        string memory _symbol,
        uint256 _tokenId,
        uint256 _dex_rp,
        uint256 _p2p_rp,
        uint256 _noOfArtbits,
        string memory _artist,
        string memory _uri
    ) external onlyAdmin {
        // nft mint
        _safeMint(gaxAdmin, _tokenId);
        _setTokenURI(_tokenId, _uri);

        // erc20 mint
        address artbitInstanceAdr = address(
                    _createProxy(
                        artbitAddr,
                        abi.encodeWithSignature(
                            "initialize(string,string,uint256,address,address,uint256,uint256,uint256)",
                            _name,
                            _symbol,
                            _noOfArtbits,
                            gaxAdmin,
                            address(this),
                            _tokenId,
                            _dex_rp,
                            _p2p_rp
                        )
                    )
        );

      //NFT_Asset update
        NFT_Asset memory newNft = NFT_Asset(
            _tokenId,
            gaxAdmin,
            artbitInstanceAdr,
            _artist
        );
        nftAssets[_tokenId] = newNft;
       emit ArtbitsMinted(_tokenId, artbitInstanceAdr, _uri);
    }

    function transferToken(
        address _to,
        uint256 _assetId,
        uint256 _artBits
    ) external onlyAdmin {
        GAX_Artbits artbitInstance = getartbitInstance(_assetId);
        artbitInstance.transferPlatform(msg.sender, _to, _artBits);
        emit ArtbitTransferred(msg.sender, _to, _assetId, _artBits);
    }

    function getartbitInstance(uint256 _nftAssetId)
        public
        view
        returns (GAX_Artbits)
    {
        NFT_Asset memory nftAsset = nftAssets[_nftAssetId];
        GAX_Artbits artbitInstance = GAX_Artbits(nftAsset.erc20_addr);
        return artbitInstance;
    }

    function checkArtbitUserBalance(uint256 _nftAssetId, address userAddr)
        public
        view
        returns (uint256)
    {
        NFT_Asset memory nftAsset = nftAssets[_nftAssetId];
        GAX_Artbits artbitInstance = GAX_Artbits(nftAsset.erc20_addr);
        return artbitInstance.balanceOf(userAddr);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function getTotCommissionAmt() external view returns (uint256) {
        return totalCommission;
    }

    function addCommissionAmt(uint256 amt, uint256 tokenId) external onlyArtbitToken(tokenId) {
        totalCommission += amt;
    }

    function getTotRoyaltyAmt() external view returns (uint256) {
        return totalRoyalty;
    }

    function addRoyaltyAmt(uint256 amt, uint256 tokenId) external onlyArtbitToken(tokenId) {
        totalRoyalty += amt;
    }

    /** WHITELISTED ADDRESSES MANAGEMENT */
    function addWhiteListAddresses(address _whiteListAddr) external onlyAdmin {
        require(isWhitelisted(_whiteListAddr), "Address already whitelisted.");
        whiteList_count++;
        whiteList_addresses[_whiteListAddr] = true;
    }

    function removeWhiteListAddresses(address _whiteListAddr)
        external
        onlyAdmin
    {
        require(!isWhitelisted(_whiteListAddr), "Address not whitelisted.");
        whiteList_count--;
        whiteList_addresses[_whiteListAddr] = false;
    }

    function isWhitelisted(address _whitelistedAddr)
        public
        view
        returns (bool)
    {
        return whiteList_addresses[_whitelistedAddr];
    }

    /** DEX ADDRESSES MANAGEMENT */
    function addDexAddresses(address _dexAddr) external onlyAdmin {
        require(isDexAddress(_dexAddr), "Address already added as Dex.");
        dexList_count++;
        dex_addresses[_dexAddr] = true;
    }

    function removeDexAddresses(address _dexAddr) external onlyAdmin {
        require(!isDexAddress(_dexAddr), "Address not added as Dex.");
        dexList_count--;
        dex_addresses[_dexAddr] = false;
    }

    function isDexAddress(address _dexAddress) public view returns (bool) {
        return dex_addresses[_dexAddress];
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(_baseTokenURI).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length == 0) {
            // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
            return string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
        }

        return string(abi.encodePacked(_baseTokenURI, _tokenURI));
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI)
        internal
        virtual
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );

        bytes memory tempBytes = bytes(_tokenURI);
        if (tempBytes.length > 0) _tokenURIs[tokenId] = _tokenURI;
    }

    // function getnftAsset(uint256 _tokenId) public view returns(NFT_Asset memory, string memory){
    //     return (nftAssets[_tokenId], tokenURI(_tokenId));
    // }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Upgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @notice Allows to create new proxy contact and execute a message call to the new proxy within one transaction.
    /// @param singleton Address of singleton contract.
    /// @param data Payload for message call sent to new proxy contract.
    function _createProxy(address singleton, bytes memory data)
        internal
        returns (ArtbitsProxy proxy)
    {
        proxy = new ArtbitsProxy(singleton);
        if (data.length > 0)
            // solhint-disable-next-line no-inline-assembly
            assembly {
                if eq(
                    call(gas(), proxy, 0, add(data, 0x20), mload(data), 0, 0),
                    0
                ) {
                    revert(0, 0)
                }
            }
      //  emit ProxyCreation(proxy, singleton);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
