pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MiddleWare{
    
    struct Auction {
        address seller;         // Current owner of NFT
        uint128 startingPrice;  // Price (in wei) at beginning of auction
        uint128 buyNowPrice;  // Price (in wei) at beginning of auction
        uint64 auctionEndTime;  // Duration (in seconds) of auction
        uint64 startedAt;       // Time when auction started 
        uint128 highestBid;      // Price at end of auction
        address highestBidder;   // winner of the auction
        address platformCommissionReciever;
        uint64 platformCommission;
        bool active; //status of the Auction
    }
    
    mapping (uint256 => Auction) tokenIdToAuction;
    // mapping(address => mapping(uint => uint)) public pendingReturn;
    
    address private admin;      
    address private owner;      
    ERC20 private tokenerc20;         
    ERC721 private tokenerc721;
    
    modifier onlyOwner {
        require(msg.sender == owner, "Sender not Owner.");
        _;
    }
    
    modifier onlyAdmin{
        require(msg.sender == admin, "Sender not Admin.");
        _;
    }
    
    // bool public ended = false;
    
    event AuctionCreated(uint256 tokenId, address _seller, uint256 startingPrice, uint256 duration);
    event AuctionSuccessful(uint256 tokenId, uint256 highestPrice, address winner, address seller);
    event Buy(uint256 tokenId, uint256 buyNowtPrice, address buyer, address seller);
    event HighstBidIncrease(uint256 tokenId, address bidder, uint amount);
    
    constructor(address _admin, ERC20 _token, ERC721 _nfttoken){
        owner = msg.sender;
        admin = _admin;
        tokenerc20 = _token; 
        tokenerc721 = _nfttoken;
    }
    
    event Deposit(address indexed from, uint indexed id, uint indexed _value);

    fallback() external{  }
     
    function currentOwner() public view virtual returns (address) {
        return owner;
    }
    
    function currentAdmin() public view virtual returns (address) {
        return admin;
    }
    
    function transferOwnership(address _newOwner)onlyOwner external returns(bool) {
        owner = _newOwner;
        return true;
    }
    
    function updateAdmin(address _newAdmin)onlyOwner external returns(bool){
        admin = _newAdmin;
        return true;
    }
    
    function deposit(uint256 _id, uint256 amount) external returns (bool) {
        require(amount > 0, "Value needs to be not 0");
        tokenerc20.transferFrom(msg.sender, admin, amount);
        emit Deposit(msg.sender, _id, amount);
        return true;
    }
    
    function createAuction(address _seller, uint256 _assetId, uint256 _startingPrice,uint256 _buyNowPrice, uint256 _auctionEndTime, address _platformCommissionReciever, uint256 _platformCommission)onlyAdmin public{
        _auctionEndTime = block.timestamp + _auctionEndTime;
        
        Auction memory auction = Auction( 
                _seller,
                uint128(_startingPrice),
                uint128(_buyNowPrice),
                uint64(_auctionEndTime),
                uint64(block.timestamp),
                uint128(_startingPrice),
                _seller,
                address(_platformCommissionReciever),
                uint64(_platformCommission),
                true
            );
        
        require(auction.auctionEndTime >= 1 minutes);
        tokenIdToAuction[_assetId] = auction;

        emit AuctionCreated(_assetId, _seller, _startingPrice, _auctionEndTime);
    }
    
    function bid(uint amount, uint _assetId) public{
        
        Auction storage auction = tokenIdToAuction[_assetId];
        require(block.timestamp <= auction.auctionEndTime, "This auction is already ended!");
        require(amount > auction.highestBid, "There is already a highr or equal bid");
        require(msg.sender!=auction.seller, "You are the seller and cannot bid");
        
        if(auction.highestBid != 0 && auction.seller !=auction.highestBidder){
            tokenerc20.transfer(auction.highestBidder, auction.highestBid);
            // pendingReturn[auction.highstBidder][_assetId] += auction.highstBid;
        }
        
        auction.highestBidder = msg.sender;
        auction.highestBid = uint128(amount);
        
        tokenerc20.transferFrom(msg.sender, address(this), amount);
        emit HighstBidIncrease(_assetId, msg.sender, amount);
    }
    
    // function withdraw(uint _assetId) public returns(bool){ 
    //     require(pendingReturn[msg.sender][_assetId]>0, "Nothing to withdraw");
        
    //     uint256 amount = pendingReturn[msg.sender][_assetId];
    //     if(amount > 0){
    //         pendingReturn[msg.sender][_assetId] = 0;
    //         tokenerc20.transfer(msg.sender, amount);
    //     }
    //     return true;
    // }
    
    function auctionEnd(uint _assetId)onlyAdmin public{
        Auction storage auction = tokenIdToAuction[_assetId];
        require(auction.active, "This auction is already ended!");
        // require(block.timestamp >= auction.auctionEndTime, "The auction is not ended yet!");
        
        if(auction.highestBidder!=auction.seller){
            if(auction.platformCommission!=0){
                // settling the platform commission
            tokenerc20.transfer(auction.platformCommissionReciever, auction.highestBid / 10000 * auction.platformCommission);
            }
            
            // settling the bid amount to seller
            tokenerc20.transfer(auction.seller, auction.highestBid / 10000 * (10000 - auction.platformCommission));
        }
        
        // trasfering the auction product to the winner
        tokenerc721.transferFrom(address(this),auction.highestBidder, _assetId);
        
        auction.active = false;
        emit AuctionSuccessful(_assetId, auction.highestBid, auction.highestBidder, auction.seller);
    }
    
    function buy(uint _amount, address _buyer, uint _assetId) onlyAdmin public{
        Auction storage auction = tokenIdToAuction[_assetId];
        
        require(auction.active, "This auction is already ended!");
        require(_amount == auction.buyNowPrice, "The amount is less to buy this asset!");
        require(_amount!=0, "The amount cannot be zero!");
        
        if(auction.highestBidder!=auction.seller){
            tokenerc20.transfer(auction.highestBidder, auction.highestBid);
        }
        tokenerc20.transferFrom(_buyer, auction.seller, auction.buyNowPrice);
        tokenerc721.transferFrom(address(this), _buyer, _assetId);
        
        auction.active = false;
        emit Buy(_assetId, auction.buyNowPrice, _buyer, auction.seller);
    }
    
    function getHighestBidder(uint _assetId)public view returns(address){
        Auction storage auction = tokenIdToAuction[_assetId];
        return(auction.highestBidder);
    }
    
    function getHighestBid(uint _assetId)public view returns(uint){
        Auction storage auction = tokenIdToAuction[_assetId];
        return(auction.highestBid);
    }
    
    function getAuctionStatus(uint _assetId)public view returns(bool){
        Auction storage auction = tokenIdToAuction[_assetId];
        return(auction.active);
    }
    
    function getAuctionDuration(uint _assetId)public view returns(uint){
        Auction storage auction = tokenIdToAuction[_assetId];
        return (auction.auctionEndTime);
    }
    function getBuyNowPrice(uint _assetId)public view returns(uint){
        Auction storage auction = tokenIdToAuction[_assetId];
        return (auction.buyNowPrice);
    }
    function getPlatformCommisionReciever(uint _assetId)public view returns(address){
        Auction storage auction = tokenIdToAuction[_assetId];
        return (auction.platformCommissionReciever);
    }
    function getPlatformCommision(uint _assetId)public view returns(uint){
        Auction storage auction = tokenIdToAuction[_assetId];
        return (auction.platformCommission);
    }
}