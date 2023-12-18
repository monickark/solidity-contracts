/**
 * SPDX-License-Identifier: MIT
 * @author Accubits
 * @title PrimaryFixedPriceNFTMarketPlace
 */
pragma solidity 0.8.13;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';

/**
 * @notice ERC1155 interface to support custom functionalites
 */
interface ERC1155 {
  struct Royalties {
    address payable account;
    uint256 percentage;
  }

  function mint(
    address receiver,
    uint256 collectibleId,
    uint256 ntokens,
    bytes memory IPFS_hash,
    Royalties calldata royalties
  ) external;

  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 ntokens,
    bytes calldata data
  ) external;
}

/**
 * @notice ERC721 interface to support custom functionalites
 */
interface ERC721 {
  struct Royalties {
    address payable account;
    uint256 percentage;
  }

  function mint(
    address receiver,
    uint256 collectibleId,
    string memory IPFSHash,
    Royalties calldata royalties
  ) external;
}

/**
 * @title Primary Fixed Price NFT MarketPlace
 * NFT MarketPlace contract to handle primary NFT sales with fixed price
 */
contract PrimaryFixedPriceNFTMarketPlace is AccessControlEnumerable, ReentrancyGuard, EIP712 {
  using SafeMath for uint256;
  using Address for address;

  /**
   * @notice To store NFT metadata
   */
  struct Metadata {
    uint256 tokenId;
    uint256 price;
    uint256 quantity;
    address erc20Token;
    address seller;
    address nftAddress;
    address royaltyReceiver;
    uint256 royaltyPercentage;
    string IPFSHash;
  }

  struct Fee {
    address receiver;
    uint256 percentageValue;
  }

  event NftSold(
    uint256 indexed tokenId,
    address indexed nftAddress,
    address indexed seller,
    uint256 price,
    address erc20Token,
    address buyer,
    uint256 quantity
  );

  event FundTransfer(Fee sellerProfit, Fee platformFee);

  mapping(address => mapping(uint256 => mapping(address => Metadata))) private mapSale;
  Fee private platformFee;

  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes4 private ERC721InterfaceId = 0x80ac58cd; // Interface Id of ERC721
  bytes4 private ERC1155InterfaceId = 0xd9b67a26; // Interface Id of ERC1155

  /**
    @notice For signature verification of Fixed Price Typed Data
  */
  bytes32 public constant FIXED_PRICE_TYPEHASH =
    keccak256(
      'FixedPrice(uint256 tokenId,uint256 price,uint256 quantity,address erc20Token,address seller,address nftAddress,address royaltyReceiver,uint256 royaltyPercentage,string IPFSHash)'
    );

  /**
   * @notice modifier to check admin rights.
   * contract owner and root admin have admin rights
   */
  modifier onlyAdmin() {
    require(_isAdmin(), 'Restricted to owner');
    _;
  }

  /**
   * @notice Constructor
   * Invokes EIP712 constructor with Domain - Used for signature verification
   * @param _platformFee Fee type. Fee percentage and Receiver address
   * @param _rootAdmin Root admin address
   */
  constructor(Fee memory _platformFee, address _rootAdmin) EIP712('PrimaryFixedPriceNFTMarketPlace', '0.0.1') {
    _setPlatformFee(_platformFee);
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, _rootAdmin);
  }

  /**
   * @notice To set platform fee and fee receiver
   * @param _platformFee Fee and fee receiver details
   */
  function PlatformFee(Fee memory _platformFee) external onlyAdmin {
    _setPlatformFee(_platformFee);
  }

  /**
   * @notice SetSaleDetails
   *         For storing NFT details on sale
   * @param _tokenId NFT unique ID
   * @param _price Unit price
   * @param _quantity Total number of tokens in sale
   * @param _erc20Token ERC20 token address, which can be used to buy this NFT
   * @param _seller Seller address
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _royaltyReceiver Royalty receiver address
   * @param _royaltyPercentage Royalty percentage
   * @param _IPFSHash IPFS Hash of NFT
   */
  function _setSaleDetails(
    uint256 _tokenId,
    uint256 _price,
    uint256 _quantity,
    address _erc20Token,
    address _seller,
    address _nftAddress,
    address _royaltyReceiver,
    uint256 _royaltyPercentage,
    string memory _IPFSHash
  ) internal {
    Metadata storage NftForSale = mapSale[_nftAddress][_tokenId][_seller];

    /// Giving the ability to increase the quantity if the item is already listed
    /// Otherwise create a new listing
    if (NftForSale.quantity > 0) {
      NftForSale.quantity += _quantity;
    } else {
      NftForSale.tokenId = _tokenId;
      NftForSale.price = _price;
      NftForSale.quantity = _quantity;
      NftForSale.erc20Token = _erc20Token;
      NftForSale.seller = _seller;
      NftForSale.nftAddress = _nftAddress;
      NftForSale.royaltyReceiver = _royaltyReceiver;
      NftForSale.royaltyPercentage = _royaltyPercentage;
      NftForSale.IPFSHash = _IPFSHash;
    }
  }

  /**
   * @notice buyNft
   *         For buying NFT using native coin or ERC20 tokens.
   * @param _metadata Details of NFT in Metadata format
   * @param _purchasingQuantity Purchasing amount of tokens
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function buyNft(
    Metadata memory _metadata,
    uint256 _purchasingQuantity,
    bytes calldata _signature
  ) public payable nonReentrant {
    require(_purchasingQuantity > 0, "BuyNfts: Can't Buy Zero NFTs");
    require(_purchasingQuantity <= _metadata.quantity, 'BuyNfts: Exceeds max quantity');

    _setSaleDetails(
      _metadata.tokenId,
      _metadata.price,
      _metadata.quantity,
      _metadata.erc20Token,
      _metadata.seller,
      _metadata.nftAddress,
      _metadata.royaltyReceiver,
      _metadata.royaltyPercentage,
      _metadata.IPFSHash
    );

    _verifyNFT(_metadata, _signature);

    uint256 buyAmount = _metadata.price.mul(_purchasingQuantity);
    address buyer = msg.sender;

    if (_metadata.erc20Token == address(0)) {
      require(msg.value >= buyAmount, 'BuyNfts: Insufficient fund');
      /// else means for erc20 token
    } else {
      require(IERC20(_metadata.erc20Token).allowance(buyer, address(this)) >= buyAmount, 'BuyNfts: Less allowance');
      IERC20(_metadata.erc20Token).transferFrom(buyer, address(this), buyAmount);
    }
    _NftSale(_metadata.tokenId, _metadata.nftAddress, _metadata.seller, buyAmount, buyer, _purchasingQuantity);
  }

  /**
   * @notice This function can only be called by the admin account
   * The fiat payment will be converted into to crypto via on-ramp and transferred to the contract for
   * administering the payment split and token transfer on-chain
   * IMPORTANT: It should only be called after the right amount of crypto/token should received in the contract
   * The transfer should be confirmed off chain before calling this function
   * @param _metadata Details of NFT in Metadata format
   * @param _purchasingQuantity Purchasing amount of tokens
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   * @param _buyer NFT receiver address
   */
  function fiatPurchase(
    Metadata memory _metadata,
    uint256 _purchasingQuantity,
    bytes calldata _signature,
    address _buyer
  ) public payable onlyAdmin nonReentrant {
    require(_purchasingQuantity > 0, "BuyNfts: Can't Buy Zero NFTs");
    require(_purchasingQuantity <= _metadata.quantity, 'BuyNfts: Exceeds max quantity');

    _setSaleDetails(
      _metadata.tokenId,
      _metadata.price,
      _metadata.quantity,
      _metadata.erc20Token,
      _metadata.seller,
      _metadata.nftAddress,
      _metadata.royaltyReceiver,
      _metadata.royaltyPercentage,
      _metadata.IPFSHash
    );

    _verifyNFT(_metadata, _signature);

    uint256 buyAmount = _metadata.price.mul(_purchasingQuantity);
    address buyer = _buyer;

    _NftSale(_metadata.tokenId, _metadata.nftAddress, _metadata.seller, buyAmount, buyer, _purchasingQuantity);
  }

  /**
   * @notice Mint NFT
   *         Calling ERC20 or ERC1155 Mint function
   * @param _receiver NFT Receiver
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _tokenId NFT unique ID
   * @param _quantity Purchasing amount of tokens
   * @param _royaltyReceiver Royalty receiver address
   * @param _royaltyPercentage Royalty percentage
   * @param _ipfsHash IPFS Hash of NFT
   */
  function _mintNFT(
    address _receiver,
    address _nftAddress,
    uint256 _tokenId,
    uint256 _quantity,
    address _royaltyReceiver,
    uint256 _royaltyPercentage,
    string memory _ipfsHash
  ) internal {
    if (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId)) {
      ERC721.Royalties memory royalties = ERC721.Royalties(payable(_royaltyReceiver), _royaltyPercentage);
      ERC721(_nftAddress).mint(_receiver, _tokenId, _ipfsHash, royalties);
    } else if (IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId)) {
      ERC1155.Royalties memory royalties = ERC1155.Royalties(payable(_royaltyReceiver), _royaltyPercentage);
      ERC1155(_nftAddress).mint(_receiver, _tokenId, _quantity, bytes(_ipfsHash), royalties);
    }
  }

  /**
   * @notice Supports Interface
   *         Function to check wether the contract support specific interface
   * @param interfaceId Interface type
   * @return boolean
   */
  function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /**
   * @notice Is Admin
   *         Checks if the msg.sender has admin roles assigned
   * @return boolean
   */
  function _isAdmin() internal view returns (bool) {
    return (hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
  }

  /**
   * @notice PlatformFee
   *         Internal function to set platform fee and fee receiver
   * @param _platformFee Fee and fee receiver details
   */
  function _setPlatformFee(Fee memory _platformFee) internal {
    require(_platformFee.percentageValue <= 5000, 'Fee: max allowed perecentage is 50');
    platformFee = _platformFee;
  }

  /**
   * @notice Pay Out
   *         To debit fees during NFT purchase
   * @param _price Fee
   * @param _currency Type of currency
   * @param _seller Seller address
   */
  function _payOut(
    uint256 _price,
    address _currency,
    address _seller
  ) internal {
    uint256 sellerProfit;
    uint256 platformProfit;

    if (platformFee.percentageValue > 0) {
      platformProfit = _price.mul(platformFee.percentageValue).div(10000);
    }
    sellerProfit = _price.sub(platformProfit);

    if (_currency == address(0)) {
      if (platformFee.receiver != address(0) && platformProfit > 0) {
        (bool isPlatformFeeTransferSuccess, ) = payable(platformFee.receiver).call{ value: platformProfit }('');
        require(isPlatformFeeTransferSuccess, 'Transfer to platform fee receiver failed.');
      }
      (bool isSellerTransferSuccess, ) = payable(_seller).call{ value: sellerProfit }('');
      require(isSellerTransferSuccess, 'Transfer to seller failed.');
    } else {
      if (platformFee.receiver != address(0) && platformProfit > 0) {
        IERC20(_currency).transfer(platformFee.receiver, platformProfit);
      }
      IERC20(_currency).transfer(_seller, sellerProfit);
    }
    emit FundTransfer(Fee(_seller, sellerProfit), Fee(platformFee.receiver, platformProfit));
  }

  /**
   * @notice NFT Sale
   *         To handle mint and payout
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _seller Seller address
   * @param _buyAmount Total amount
   * @param _buyer Receiver address
   * @param _purchasingQuantity Purchasing amount of tokens
   */
  function _NftSale(
    uint256 _tokenId,
    address _nftAddress,
    address _seller,
    uint256 _buyAmount,
    address _buyer,
    uint256 _purchasingQuantity
  ) internal {
    Metadata storage nftOnSaleStorage = mapSale[_nftAddress][_tokenId][_seller];

    _mintNFT(
      _buyer,
      _nftAddress,
      _tokenId,
      _purchasingQuantity,
      nftOnSaleStorage.royaltyReceiver,
      nftOnSaleStorage.royaltyPercentage,
      nftOnSaleStorage.IPFSHash
    );
    _payOut(_buyAmount, nftOnSaleStorage.erc20Token, _seller);

    nftOnSaleStorage.quantity = nftOnSaleStorage.quantity - _purchasingQuantity;

    if (nftOnSaleStorage.quantity == 0) {
      delete mapSale[_nftAddress][_tokenId][_seller];
    }
    emit NftSold(_tokenId, _nftAddress, _seller, nftOnSaleStorage.price, nftOnSaleStorage.erc20Token, _buyer, _purchasingQuantity);
  }

  /**
   * @notice Is NFT
   *         Checks if the nft address specified is ERC721 or ERC1155
   * @param _nftAddress NFT Contract address
   * @return boolean
   */
  function _isNFT(address _nftAddress) internal view returns (bool) {
    require(_nftAddress != address(0), 'isNFT: Zero Address');
    return (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId) || IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId));
  }

  /**
   * @notice Hash Mint Data
   *         To hash the nft metadata
   * @param tokenId NFT unique ID
   * @param seller Seller address
   * @param nftAddress ERC721 or ERC1155 address
   * @return Hash Hash of metadata
   */
  function _hashTypedData(
    uint256 tokenId,
    address seller,
    address nftAddress
  ) internal view returns (bytes32) {
    Metadata storage NftForSale = mapSale[nftAddress][tokenId][seller];
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            FIXED_PRICE_TYPEHASH,
            tokenId,
            NftForSale.price,
            NftForSale.quantity,
            NftForSale.erc20Token,
            NftForSale.seller,
            NftForSale.nftAddress,
            NftForSale.royaltyReceiver,
            NftForSale.royaltyPercentage,
            keccak256(bytes(NftForSale.IPFSHash))
          )
        )
      );
  }

  /**
   * @notice Verify Minter
   *         To extract signer address from signature
   * @param digest Data hash
   * @param signature Signature
   * @return Signer Signer address
   */
  function _verifyMinter(bytes32 digest, bytes memory signature) internal pure returns (address) {
    address signer = ECDSA.recover(digest, signature);
    return signer;
  }

  /**
   * @notice Verify NFT
   *         To peerform signature verification and common validaitons
   * @param metadata NFT details in metadata format
   * @param signature Metadata signed by admin during NFT creation on platform
   * @return boolean Verification status
   */
  function _verifyNFT(Metadata memory metadata, bytes calldata signature) internal view returns (bool) {
    require(msg.sender != address(0), 'BuyNfts: Zero Address');
    require(metadata.quantity > 0, 'BuyNfts: Wont Accept Zero Quantity');
    require(_isNFT(metadata.nftAddress), 'BuyNfts: Invalid NFT Address');
    require(msg.sender != metadata.seller, 'BuyNfts : Owner Is Not Allowed To Buy Nfts');
    require(metadata.seller != address(0), 'Sell Nfts: Zero Address');
    require(!_isAdmin(), 'BuyNfts: Admin Cannot Buy Nfts');
    require(metadata.price > 0, 'BuyNfts: Wont Accept Zero Price');

    address signer = _verifyMinter(_hashTypedData(metadata.tokenId, metadata.seller, metadata.nftAddress), signature);
    require(hasRole(ADMIN_ROLE, signer) || hasRole(DEFAULT_ADMIN_ROLE, signer), 'NFT Signature verification failed!');

    return true;
  }

  /**
   * @notice Receive fund to this contract, usually for the purpose of fiat on-ramp
   * for EOA transfer
   */
  receive() external payable {
    emit FundReceived(msg.sender, msg.value);
  }

  /**
   * @notice Receive fund to this contract, usually for the purpose of fiat on-ramp
   * for contract transfer
   */
  fallback() external payable {
    emit FundReceived(msg.sender, msg.value);
  }
}
