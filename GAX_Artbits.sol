// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./GAX_FNFT.sol";
import "./proxy/Singleton.sol";

contract GAX_Artbits is Singleton, ERC20Upgradeable {
    uint256 public nftId;
    uint256 public dex_rp;
    uint256 public p2p_rp;
    uint256 public no_of_artbits;

    address public nftOwner;

    bool isAssetUpdate;

    GAX_FNFT public gaxInstance;

    
    mapping(address => bool) private dexPair_addresses;
    mapping(address => address) private dex_lp_pairAddr;

    constructor() initializer {}

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _gaxAdmin,
        address _gaxAddress,
        uint256 _tokenId,
        uint256 _dex_rp,
        uint256 _p2p_rp
    ) public virtual initializer {
        __ERC20_init(_name, _symbol);
        _mint(_gaxAdmin, _initialSupply);
        gaxInstance = GAX_FNFT(_gaxAddress);
        setArtbitAsset(_tokenId, _gaxAdmin, _dex_rp, _p2p_rp, _initialSupply);
    }

    modifier onlyAdmin() {
        require(msg.sender == gaxInstance.gaxAdmin(), "Caller is not Admin.");
        _;
    }

    modifier onlySuperAdmin() {
        require(msg.sender == gaxInstance.superAdmin(), "Unauthorized.");
        _;
    }

    modifier onlyNFT() {
        require(msg.sender == address(gaxInstance), "unauthorized");
        _;
    }

    function setArtbitAsset(
        uint256 _nftId,
        address _nftOwner,
        uint256 _dex_rp,
        uint256 _p2p_rp,
        uint256 _artbits
    ) internal {
        require(!isAssetUpdate, "Asset already updated");
        nftId = _nftId;
        nftOwner = _nftOwner;
        dex_rp = _dex_rp;
        p2p_rp = _p2p_rp;
        no_of_artbits = _artbits;
        isAssetUpdate = true;
    }

    function updateArtbitPercentage(uint256 _p2p_rp, uint256 _dex_rp)
        public
        onlyNFT
        returns (bool)
    {
        p2p_rp = _p2p_rp;
        dex_rp = _dex_rp;
        return true;
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        transferArtbits(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {        
        transferArtbits(sender, recipient, amount); 
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

    function transferPlatform(
        address sender,
        address recipient,
        uint256 amount
    ) public onlyNFT returns (bool) {
        transferArtbits(sender, recipient, amount);
        return true;
    }

    function transferArtbits(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        uint256 transferAmount;
        address gaxAdmin = gaxInstance.gaxAdmin();
        // whitelist transaction no commission fee
        if (
            gaxInstance.isWhitelisted(sender) ||
            gaxInstance.isWhitelisted(recipient) ||
            recipient == gaxAdmin ||
            sender == gaxAdmin 
            // add liquidity for dex cant count here

        ) {
            transferAmount = amount;            
            gaxInstance.callBackTransferToken(sender, recipient, nftId, amount, 0, transferAmount, 0, "whitelist", msg.sender,address(0));
        }
        // add liquidity in dex
        else if(gaxInstance.isDexAddress(msg.sender)) {
            transferAmount = amount;     
          //  gaxInstance.callBackTransferToken(sender, recipient, nftId, amount, 0, transferAmount, 0, "addLiquidity", msg.sender);  
            dexPair_addresses[recipient] = true;   
            dex_lp_pairAddr[recipient]=msg.sender;  
        }
        // DEX transaction NFT_Asset owner receive royalty
        else if (dexPair_addresses[sender]) {            
            uint256 drp = dex_rp; 
            if(dex_rp == 0) {drp = gaxInstance.dex_rp();}
            uint256 royalty_amt = (drp * amount) / 10000; // admin royalty amt
            _transfer(sender, nftOwner, royalty_amt);
            gaxInstance.addRoyaltyAmt(royalty_amt, nftId); // add royalty amount to NFT_Asset owner wallet
            transferAmount = amount - royalty_amt; // AB sent to client
            address dexRouter = dex_lp_pairAddr[sender];
            gaxInstance.callBackTransferToken(sender, recipient, nftId, amount, royalty_amt, transferAmount, drp , "DEX", msg.sender, dexRouter);
        } else {
           uint256 p2p = p2p_rp;  
           if(p2p_rp == 0) {p2p = gaxInstance.p2p_rp();}
            uint256 commission = (p2p * amount) / 10000; // admin commission amt
            _transfer(sender, nftOwner, commission);
            transferAmount = amount - commission; // AB sent to client
            gaxInstance.addCommissionAmt(commission, nftId); // add commission amount to NFT_Asset owner wallet            
            gaxInstance.callBackTransferToken(sender, recipient, nftId, amount, commission, transferAmount, p2p, "P2P", msg.sender,address(0));
        }
        _transfer(sender, recipient, transferAmount);
        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function upgradeSingleton(address _singleton) external onlySuperAdmin {
        singleton = _singleton;
    }
}
