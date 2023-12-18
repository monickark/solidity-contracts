// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

import "./HederaResponseCodes.sol";
import "./IHederaTokenService.sol";
import "./HederaTokenService.sol";
import "./ExpiryHelper.sol";

contract AuctionContract is ExpiryHelper {
    /**
     * @notice NFT metadata along with bid details
     */
    struct Auction {
        address tokenId;
        int64 serialNumber;
        uint256 basePrice;
        address auctioner;
        address currentBidder;
        uint256 bidAmount;
    }

    mapping(address => mapping(int64 => mapping(address => Auction)))
        public mapAuction;

    /**
     * @notice createAuction
     * Function to start auction with first bid.
     * Validate signatures, stores NFT data and add first bid as well
     */
    // token owner is the caller
    function createAuction(
        address tokenId,
        int64 serialNumber,
        uint256 basePrice
    ) external {
        require(basePrice > 0, "Create Auction : Zero base price.");
        require(
            mapAuction[tokenId][serialNumber][msg.sender].auctioner ==
                address(0),
            "Auction already created."
        );
        Auction storage NftOnAuction = mapAuction[tokenId][serialNumber][
            msg.sender
        ];
        NftOnAuction.auctioner = msg.sender;
        NftOnAuction.bidAmount = basePrice;
        NftOnAuction.basePrice = basePrice;
    }

    /**
     * @notice placeBid
     * Function to place the bid on the nfts using native cryptocurrency and multiple erc20 token
     * @param _tokenId NFT unique ID
     * @param _price bid price
     * @param _auctioner Seller address
     */
    // anyone can call
    function placeBid(
        address _tokenId,
        int64 _serialNumber,
        uint256 _price,
        address _auctioner
    ) public payable {
        Auction storage NftOnAuction = mapAuction[_tokenId][_serialNumber][
            _auctioner
        ];
        require(
            _price >= NftOnAuction.basePrice,
            "Place Bid : Price Less Than the base price"
        );
        require(
            _price > NftOnAuction.bidAmount,
            "Place Bid : The price is less then the previous bid amount"
        );
        require(
            msg.value == _price,
            "Place Bid: Amount received and price should be same"
        );
        if (NftOnAuction.currentBidder != address(0)) {
            payable(NftOnAuction.currentBidder).transfer(
                NftOnAuction.bidAmount
            );
        }
        NftOnAuction.bidAmount = _price;
        NftOnAuction.currentBidder = msg.sender;
    }

    // admin account is the caller, allowance set to adminacc, bidwinner(NftOnAuction.currentBidder)
    function settleAuction(address _tokenId, int64 _serialNumber) public {
        Auction storage NftOnAuction = mapAuction[_tokenId][_serialNumber][
            msg.sender
        ];
        require(
            msg.sender == NftOnAuction.auctioner,
            "Settle Auction : Restricted to treasurer!"
        );
        payable(msg.sender).transfer(NftOnAuction.bidAmount);
        transferNonFungibleToken(
            _tokenId,
            msg.sender,
            NftOnAuction.currentBidder,
            _serialNumber
        );
    }

    function getCustomfee(address token)
        public
        returns (
            int64 responseCode,
            IHederaTokenService.FixedFee[] memory fixedFees,
            IHederaTokenService.FractionalFee[] memory fractionalFees,
            IHederaTokenService.RoyaltyFee[] memory royaltyFees
        )
    {
        //  return (responseCode, fixedFees, fractionalFees,  royaltyFees) =
        return HederaTokenService.getTokenCustomFees(token);
    }

    function transferNonFungibleToken(
        address token,
        address sender,
        address receiver,
        int64 serialNumber
    ) public {
        int256 responseCode = HederaTokenService.transferNFT(
            token,
            sender,
            receiver,
            serialNumber
        );

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Failed to create non-fungible token");
        }
    }
}
