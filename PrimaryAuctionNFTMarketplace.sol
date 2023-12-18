/**
 * SPDX-License-Identifier: MIT
 * @author Accubits
 * @title PrimaryAuctionNFTMarketPlace
 */
pragma solidity 0.8.13;

import '@openzeppelin/contracts/interfaces/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

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
 * @title Primary Auction NFT MarketPlace
 * NFT MarketPlace contract to handle primary NFT sales with auction
 */
contract PrimaryAuctionNFTMarketPlace is AccessControlEnumerable, ReentrancyGuard, EIP712 {
  using SafeMath for uint256;
  using Address for address;
  using SafeERC20 for IERC20;

  /**
   * @notice To receive NFT metadata as a single argument
   */
  struct Metadata {
    uint256 tokenId;
    uint256 basePrice;
    uint256 salePrice;
    uint256 bidPrice;
    uint256 quantity;
    address erc20Token;
    address auctioner;
    address nftAddress;
    address royaltyReceiver;
    uint256 royaltyPercentage;
    string IPFSHash;
  }

  /**
   * @notice Additional NFT metadata needed for minting
   */
  struct NftInfo {
    address royaltyReceiver;
    uint256 royaltyPercentage;
    string IPFSHash;
  }

  /**
   * @notice NFT metadata along with bid details
   */
  struct Auction {
    uint256 tokenId;
    uint256 basePrice;
    uint256 salePrice;
    address erc20Token;
    uint256 quantity;
    address auctioner;
    address currentBidder;
    uint256 bidAmount;
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

  event AuctionCreated(
    uint256 indexed tokenId,
    address indexed nftAddress,
    address indexed auctioner,
    uint256 basePrice,
    uint256 salePrice,
    address erc20Token,
    uint256 quantity
  );

  event BidPlaced(
    uint256 indexed tokenId,
    address indexed tokenContract,
    address indexed auctioner,
    address bidder,
    address erc20Token,
    uint256 quantity,
    uint256 price
  );

  event AuctionSettled(
    uint256 indexed tokenId,
    address indexed tokenContract,
    address indexed auctioner,
    address heighestBidder,
    address erc20Token,
    uint256 quantity,
    uint256 heighestBid
  );

  event AuctionCancelled(
    uint256 indexed tokenId,
    address indexed tokenContract,
    address indexed auctioner,
    uint256 quantity,
    address erc20Token,
    uint256 heighestBid,
    address heighestBidder
  );

  event FundTransfer(Fee sellerProfit, Fee platformFee);
  event FundReceived(address indexed from, uint256 amount);

  mapping(address => mapping(uint256 => mapping(address => Auction))) private mapAuction;
  mapping(address => mapping(uint256 => NftInfo)) private mapNftInfo;
  mapping(address => Fee) creatorRoyalties;
  Fee private platformFee;

  /**
   * @notice Defining ADMIN ROLE and Interface IDs
   */
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes4 private ERC721InterfaceId = 0x80ac58cd;
  bytes4 private ERC1155InterfaceId = 0xd9b67a26;

  /**
    @notice For signature verification of Auction Typed Data
  */
  bytes32 public constant AUCTION_TYPEHASH =
    keccak256(
      'Auction(uint256 tokenId,uint256 basePrice,uint256 salePrice,uint256 quantity,address erc20Token,address seller,address nftAddress,address royaltyReceiver,uint256 royaltyPercentage,string IPFSHash)'
    );

  /**
   * @notice modifier to check admin rights.
   * contract owner and root admin have admin rights
   */
  modifier onlyOwner() {
    require(_isAdmin(), 'Restricted to admin');
    _;
  }

  /**
   * @notice callerNotAContract
   * Modifier to check given address is a contract address or not.
   */
  modifier callerNotAContract() {
    require(msg.sender == tx.origin, 'Caller cannot be a contract');
    _;
  }

  /**
   * @notice Constructor
   * Invokes EIP712 constructor with Domain - Used for signature verification
   * @param _platformFee Fee type. Fee percentage and Receiver address
   * @param _rootAdmin Root admin address
   */
  constructor(Fee memory _platformFee, address _rootAdmin) EIP712('PrimaryAuctionNFTMarketPlace', '0.0.1') {
    _setPlatformFee(_platformFee);
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ADMIN_ROLE, _rootAdmin);
  }

  /**
   * @notice setPlatformFee
   * Internal function to set platform fee percentage.
   * @param _platformFee Fee percentage
   * Must be given as percentage * 100
   */
  function _setPlatformFee(Fee memory _platformFee) internal {
    require(_platformFee.percentageValue <= 5000, 'Fee: max allowed perecentage is 50');
    platformFee = _platformFee;
  }

  /**
   * @notice isAdmin
   * Function to check does the msg.sender has admin role.
   * @return bool
   */
  function _isAdmin() internal view returns (bool) {
    return (hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
  }

  /**
   * @notice isNFT
   * Function to check if the given address is an NFT.
   * Checks for ERC721 or ERC1155 interface support
   * @param _nftAddress Take erc721 and erc1155 address
   * @return bool
   */
  function _isNFT(address _nftAddress) internal view returns (bool) {
    return (IERC721(_nftAddress).supportsInterface(ERC721InterfaceId) || IERC1155(_nftAddress).supportsInterface(ERC1155InterfaceId));
  }

  /**
   * @notice setAuctionDetails
   * Function to set the auction details
   * @param _tokenId NFT unique ID
   * @param _basePrice Unit base price, lowest bid value
   * @param _salePrice Unit sale price, for instant buy
   * @param _quantity Total number of tokens in sale
   * @param _erc20Token ERC20 token address, which can be used to buy this NFT
   * @param _auctioner Seller address
   * @param _nftAddress ERC721 or ERC1155 address
   */
  function _setAuctionDetails(
    uint256 _tokenId,
    uint256 _basePrice,
    uint256 _salePrice,
    uint256 _quantity,
    address _erc20Token,
    address _auctioner,
    address _nftAddress
  ) internal {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];
    NftOnAuction.tokenId = _tokenId;
    NftOnAuction.basePrice = _basePrice;
    NftOnAuction.salePrice = _salePrice;
    NftOnAuction.erc20Token = _erc20Token;
    NftOnAuction.quantity = _quantity;
    NftOnAuction.auctioner = _auctioner;
  }

  /**
   * @notice setNftInfo
   * Function to save additional nft informations to mint
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _tokenId NFT unique ID
   * @param _ipfsHash IPFS Hash of NFT
   * @param _royaltyReceiver Royalty receiver address
   * @param _royaltyAmount Royalty amount
   */
  function _setNftInfo(
    address _nftAddress,
    uint256 _tokenId,
    string memory _ipfsHash,
    address _royaltyReceiver,
    uint256 _royaltyAmount
  ) internal {
    NftInfo storage NftInfoStored = mapNftInfo[_nftAddress][_tokenId];

    // Storing basic nft informations only if it is not already stored.
    if (bytes(NftInfoStored.IPFSHash).length == 0) {
      NftInfoStored.IPFSHash = _ipfsHash;
      NftInfoStored.royaltyReceiver = _royaltyReceiver;
      NftInfoStored.royaltyPercentage = _royaltyAmount;
    }
  }

  /**
   * @notice createAuction
   * Function to start auction with first bid.
   * Validate signatures, stores NFT data and add first bid as well
   * @param _metadata Details of NFT in Metadata format
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function createAuction(Metadata memory _metadata, bytes calldata _signature) external payable nonReentrant {
    _setAuctionDetails(
      _metadata.tokenId,
      _metadata.basePrice,
      _metadata.salePrice,
      _metadata.quantity,
      _metadata.erc20Token,
      _metadata.auctioner,
      _metadata.nftAddress
    );

    _validateMetadata(_metadata.tokenId, _metadata.auctioner, _metadata.nftAddress, _signature);
    require(_metadata.salePrice > 0, 'Create Auction: Zero sale price.');
    require(_metadata.basePrice > 0, 'Create Auction : Zero base price.');

    _setNftInfo(_metadata.nftAddress, _metadata.tokenId, _metadata.IPFSHash, _metadata.royaltyReceiver, _metadata.royaltyPercentage);

    placeBid(_metadata.tokenId, _metadata.bidPrice, _metadata.nftAddress, _metadata.auctioner, _signature);

    emit AuctionCreated(
      _metadata.tokenId,
      _metadata.nftAddress,
      _metadata.auctioner,
      _metadata.basePrice,
      _metadata.salePrice,
      _metadata.erc20Token,
      _metadata.quantity
    );
  }

  /**
   * @notice placeBid
   * Function to place the bid on the nfts using native cryptocurrency and multiple erc20 token
   * @param _tokenId NFT unique ID
   * @param _price bid price
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function placeBid(
    uint256 _tokenId,
    uint256 _price,
    address _nftAddress,
    address _auctioner,
    bytes calldata _signature
  ) public payable callerNotAContract {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];

    _validateMetadata(_tokenId, _auctioner, _nftAddress, _signature);
    require(!_isAdmin(), 'Place Bid: Admin Can Not Place Bid');
    require(msg.sender != NftOnAuction.auctioner, 'Place Bid : Seller not allowed to place bid');
    require(_price >= NftOnAuction.basePrice, 'Place Bid : Price Less Than the base price');
    require(_price > NftOnAuction.bidAmount, 'Place Bid : The price is less then the previous bid amount');

    if (NftOnAuction.erc20Token == address(0)) {
      require(msg.value == _price, 'Place Bid: Amount received and price should be same');
      require(msg.value > NftOnAuction.bidAmount, 'Place Bid: Amount received should be grather than the current bid');
      if (NftOnAuction.currentBidder != address(0)) {
        payable(NftOnAuction.currentBidder).transfer(NftOnAuction.bidAmount);
      }
    } else {
      uint256 checkAllowance = IERC20(NftOnAuction.erc20Token).allowance(msg.sender, address(this));
      require(checkAllowance >= _price, 'Place Bid : Allowance is Less then Price');
      IERC20(NftOnAuction.erc20Token).safeTransferFrom(msg.sender, address(this), _price);
      if (NftOnAuction.currentBidder != address(0)) {
        IERC20(NftOnAuction.erc20Token).safeTransfer(NftOnAuction.currentBidder, NftOnAuction.bidAmount);
      }
    }

    NftOnAuction.bidAmount = _price;
    NftOnAuction.currentBidder = msg.sender;

    emit BidPlaced(_tokenId, _nftAddress, _auctioner, msg.sender, NftOnAuction.erc20Token, NftOnAuction.quantity, _price);
  }

  /**
   * @notice instantBuyNFT
   * Function to buy the NFT on auction instantly.
   * Current bid must be less than sale price.
   * Accept native cryptocurrency or erc20 tokens.
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function instantBuyNFT(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner,
    bytes calldata _signature
  ) external payable nonReentrant {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];

    _validateMetadata(_tokenId, _auctioner, _nftAddress, _signature);
    require(!_isAdmin(), 'Auction Instant Buy: Admin not allowed to perform purchase');
    require(msg.sender != NftOnAuction.auctioner, 'Auction Instant Buy: Seller not allowed to perform purchase');
    require(NftOnAuction.salePrice > NftOnAuction.bidAmount, 'Auction Instant Buy: Bid exceeds sale price');

    if (NftOnAuction.erc20Token == address(0)) {
      require(msg.value == NftOnAuction.salePrice, 'Auction Instant Buy: Amount received and sale price should be same');

      if (NftOnAuction.currentBidder != address(0)) {
        payable(NftOnAuction.currentBidder).transfer(NftOnAuction.bidAmount);
      }
    } else {
      uint256 checkAllowance = IERC20(NftOnAuction.erc20Token).allowance(msg.sender, address(this));

      require(checkAllowance >= NftOnAuction.salePrice, 'Auction Instant Buy: Allowance is Less then Price');

      IERC20(NftOnAuction.erc20Token).safeTransferFrom(msg.sender, address(this), NftOnAuction.salePrice);

      if (NftOnAuction.currentBidder != address(0)) {
        IERC20(NftOnAuction.erc20Token).safeTransfer(NftOnAuction.currentBidder, NftOnAuction.bidAmount);
      }
    }

    address buyer = msg.sender;

    _NftAuction(_tokenId, _nftAddress, _auctioner, buyer, NftOnAuction);
  }

  /**
   * @notice instantBuyNFTwithFiat
   * This function can only be called by the admin account
   * The fiat payment will be converted into to crypto via on-ramp and transferred to the contract for
   * administering the payment split and token transfer on-chain
   * IMPORTANT: It should only be called after the right amount of crypto/token should received in the contract
   * The transfer should be confirmed off chain before calling this function
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _buyer Buyer address
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function instantBuyNFTwithFiat(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner,
    address _buyer,
    bytes calldata _signature
  ) external payable onlyOwner nonReentrant {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];

    _validateMetadata(_tokenId, _auctioner, _nftAddress, _signature);
    require(NftOnAuction.salePrice > NftOnAuction.bidAmount, 'Auction Instant Buy: Bid exceeds sale price');
    require(_buyer != NftOnAuction.auctioner, 'Auction Instant Buy : Seller not allowed to perform purchase');
    require(NftOnAuction.salePrice > NftOnAuction.bidAmount, 'Auction Instant Buy: bid exceeds sale price');

    if (NftOnAuction.erc20Token == address(0)) {
      if (NftOnAuction.currentBidder != address(0)) {
        payable(NftOnAuction.currentBidder).transfer(NftOnAuction.bidAmount);
      }
    } else {
      if (NftOnAuction.currentBidder != address(0)) {
        IERC20(NftOnAuction.erc20Token).safeTransfer(NftOnAuction.currentBidder, NftOnAuction.bidAmount);
      }
    }

    _NftAuction(_tokenId, _nftAddress, _auctioner, _buyer, NftOnAuction);
  }

  /**
   * @notice NftAuction
   * Manage auction instant purchase general logic
   * Minting the NFT and transfering various funds.
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _buyer Buyer address
   */
  function _NftAuction(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner,
    address _buyer,
    Auction memory NftOnAuction
  ) internal {
    NftInfo storage NftInfoStored = mapNftInfo[_nftAddress][_tokenId];

    _mintNFT(
      _buyer,
      _nftAddress,
      _tokenId,
      NftOnAuction.quantity,
      NftInfoStored.royaltyReceiver,
      NftInfoStored.royaltyPercentage,
      NftInfoStored.IPFSHash
    );

    _fundTransfer(NftOnAuction.salePrice, NftOnAuction.erc20Token, true, NftOnAuction.auctioner);

    emit AuctionSettled(
      NftOnAuction.tokenId,
      _nftAddress,
      _auctioner,
      _buyer,
      NftOnAuction.erc20Token,
      NftOnAuction.quantity,
      NftOnAuction.salePrice
    );

    delete mapAuction[_nftAddress][_tokenId][_auctioner];
  }

  /**
   * @notice fundTransfer
   * Manage fund transfers on purchase of NFT
   * @param _price Total price
   * @param _tokenErc20 ERC20 token address
   * @param _isDirectPurchase Instant buy or settle auction
   * @param _seller Seller address
   */
  function _fundTransfer(
    uint256 _price,
    address _tokenErc20,
    bool _isDirectPurchase,
    address _seller
  ) internal {
    uint256 sellerProfit;
    uint256 platformProfit;

    if (platformFee.percentageValue > 0) {
      platformProfit = _price.mul(platformFee.percentageValue).div(10000);
    }

    sellerProfit = _price.sub(platformProfit);

    if (_tokenErc20 == address(0)) {
      if (platformFee.receiver != address(0) && platformProfit > 0) {
        (bool isPlatformFeeTransferSuccess, ) = payable(platformFee.receiver).call{ value: platformProfit }('');
        require(isPlatformFeeTransferSuccess, 'Fund Transfer: Transfer to platform fee receiver failed.');
      }
      (bool isSellerTransferSuccess, ) = payable(_seller).call{ value: sellerProfit }('');
      require(isSellerTransferSuccess, 'Fund Transfer: Transfer to seller failed.');
    } else {
      if (_isDirectPurchase) {
        if (platformFee.receiver != address(0) && platformProfit > 0) {
          IERC20(_tokenErc20).safeTransferFrom(msg.sender, platformFee.receiver, platformProfit);
        }
        IERC20(_tokenErc20).safeTransferFrom(msg.sender, _seller, sellerProfit);
      } else {
        if (platformFee.receiver != address(0) && platformProfit > 0) {
          IERC20(_tokenErc20).safeTransfer(platformFee.receiver, platformProfit);
        }
        IERC20(_tokenErc20).safeTransfer(_seller, sellerProfit);
      }
    }
    emit FundTransfer(Fee(_seller, sellerProfit), Fee(platformFee.receiver, platformProfit));
  }

  /**
   * @notice mintNFT
   * Calling ERC721 or ERC1155 Mint function
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
   * @notice settleAuction
   * Function to settle auction.
   * Must be called by admin or auctioneer
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function settleAuction(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner,
    bytes calldata _signature
  ) public nonReentrant {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];
    NftInfo storage NftInfoStored = mapNftInfo[_nftAddress][_tokenId];

    _validateMetadata(_tokenId, _auctioner, _nftAddress, _signature);
    require(_isAdmin() || msg.sender == NftOnAuction.auctioner, 'Settle Auction : Restricted to auctioner or admin!');

    if (NftOnAuction.currentBidder != address(0)) {
      _mintNFT(
        NftOnAuction.currentBidder,
        _nftAddress,
        _tokenId,
        NftOnAuction.quantity,
        NftInfoStored.royaltyReceiver,
        NftInfoStored.royaltyPercentage,
        NftInfoStored.IPFSHash
      );

      _fundTransfer(NftOnAuction.bidAmount, NftOnAuction.erc20Token, false, NftOnAuction.auctioner);
    } else {
      _mintNFT(
        NftOnAuction.auctioner,
        _nftAddress,
        _tokenId,
        NftOnAuction.quantity,
        NftInfoStored.royaltyReceiver,
        NftInfoStored.royaltyPercentage,
        NftInfoStored.IPFSHash
      );

      _fundTransfer(NftOnAuction.bidAmount, NftOnAuction.erc20Token, false, NftOnAuction.auctioner);
    }

    emit AuctionSettled(
      NftOnAuction.tokenId,
      _nftAddress,
      _auctioner,
      NftOnAuction.currentBidder,
      NftOnAuction.erc20Token,
      NftOnAuction.quantity,
      NftOnAuction.bidAmount
    );

    delete mapAuction[_nftAddress][_tokenId][_auctioner];
  }

  /**
   * @notice cancelAuction
   * Function to cancel the auction
   * Must be called by admin or auctioneer
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @param _signature Metadata signature signed by admin during NFT creation on platform
   */
  function cancelAuction(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner,
    bytes calldata _signature
  ) external nonReentrant {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];

    _validateMetadata(_tokenId, _auctioner, _nftAddress, _signature);
    require(_isAdmin() || msg.sender == NftOnAuction.auctioner, 'Cancel Auction: Restricted to auctioner or admin!');

    /// Return bid if there is any
    if (NftOnAuction.currentBidder != address(0)) {
      if (NftOnAuction.erc20Token == address(0)) {
        payable(NftOnAuction.currentBidder).transfer(NftOnAuction.bidAmount);
      } else {
        IERC20(NftOnAuction.erc20Token).safeTransfer(NftOnAuction.currentBidder, NftOnAuction.bidAmount);
      }
    }

    emit AuctionCancelled(
      _tokenId,
      _nftAddress,
      _auctioner,
      NftOnAuction.quantity,
      NftOnAuction.erc20Token,
      NftOnAuction.bidAmount,
      NftOnAuction.currentBidder
    );

    delete mapAuction[_nftAddress][_tokenId][_auctioner];
  }

  /**
   * @notice getAuction
   * Function to get auction details
   * @param _tokenId NFT unique ID
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _auctioner Seller address
   * @return Auction Auction data
   */
  function getAuction(
    uint256 _tokenId,
    address _nftAddress,
    address _auctioner
  ) external view returns (Auction memory) {
    Auction storage nftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];
    return (nftOnAuction);
  }

  /**
   * @notice hashTypedData
   * Function to hash the nft metadata
   * @param tokenId NFT unique ID
   * @param auctioner Seller address
   * @param nftAddress ERC721 or ERC1155 address
   * @return Hash Hash of metadata
   */
  function _hashTypedData(
    uint256 tokenId,
    address auctioner,
    address nftAddress
  ) internal view returns (bytes32) {
    Auction storage NftOnAuction = mapAuction[nftAddress][tokenId][auctioner];
    NftInfo storage NftInfoStored = mapNftInfo[nftAddress][tokenId];
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            AUCTION_TYPEHASH,
            tokenId,
            NftOnAuction.basePrice,
            NftOnAuction.salePrice,
            NftOnAuction.quantity,
            NftOnAuction.erc20Token,
            NftOnAuction.auctioner,
            nftAddress,
            NftInfoStored.royaltyReceiver,
            NftInfoStored.royaltyPercentage,
            keccak256(bytes(NftInfoStored.IPFSHash))
          )
        )
      );
  }

  /**
   * @notice getSigner
   * Function To extract signer address from signature
   * @param digest Data hash
   * @param signature Signature
   * @return signer Signer address
   */
  function _getSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
    address signer = ECDSA.recover(digest, signature);
    return signer;
  }

  /**
   * @notice verifySignature
   * Function to perform signature verification
   * @param tokenId NFT unique ID
   * @param auctioner Seller address
   * @param nftAddress ERC721 or ERC1155 address
   * @param signature Metadata signed by admin during NFT creation on platform
   * @return boolean Verification status
   */
  function _verifySignature(
    uint256 tokenId,
    address auctioner,
    address nftAddress,
    bytes calldata signature
  ) internal view returns (bool) {
    address signer = _getSigner(_hashTypedData(tokenId, auctioner, nftAddress), signature);
    require(hasRole(ADMIN_ROLE, signer) || hasRole(DEFAULT_ADMIN_ROLE, signer), 'Signature verification failed!');
    return true;
  }

  /**
   * @notice validateMetadata
   * Function to perform general validations
   * @param _tokenId NFT unique ID
   * @param _auctioner Seller address
   * @param _nftAddress ERC721 or ERC1155 address
   * @param _signature Metadata signed by admin during NFT creation on platform
   * @return boolean Verification status
   */
  function _validateMetadata(
    uint256 _tokenId,
    address _auctioner,
    address _nftAddress,
    bytes calldata _signature
  ) internal view returns (bool) {
    Auction storage NftOnAuction = mapAuction[_nftAddress][_tokenId][_auctioner];

    require(msg.sender != address(0), 'Genaral Validation: Zero Sender Address');
    require(_nftAddress != address(0), 'Genaral Validation: Zero NFT Address');
    require(_auctioner != address(0), 'Genaral Validation: Zero Auctioner Address ');
    require(_isNFT(_nftAddress), 'Genaral Validation: Not confirming to an NFT contract');
    require(NftOnAuction.quantity != 0, 'Genaral Validation: Zero Quantity');
    require(NftOnAuction.tokenId == _tokenId, 'Genaral Validation: Token id is not on auction');

    _verifySignature(_tokenId, _nftAddress, _auctioner, _signature);

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
