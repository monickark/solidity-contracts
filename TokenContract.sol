// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;
 
import './HederaResponseCodes.sol';
import './IHederaTokenService.sol';
import './HederaTokenService.sol';
import './ExpiryHelper.sol';
 
contract TokenCreator is ExpiryHelper{
 
   function createNonFungible(
           string memory name,
           string memory symbol,
           string memory memo,
           uint32 maxSupply,
           uint32 autoRenewPeriod
       ) external payable returns (address, IHederaTokenService.TokenKey[] memory){
 
       // Instantiate the list of keys we'll use for token create
        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        // use the helper methods in KeyHelper to create basic key
        keys[0] = createSingleKey(HederaTokenService.SUPPLY_KEY_TYPE, KeyHelper.CONTRACT_ID_KEY, address(this));

        IHederaTokenService.HederaToken memory token;
        token.name = name;
        token.symbol = symbol;
        token.memo = memo;
        token.treasury = address(this);
        token.tokenSupplyType = true; // set supply to FINITE
        token.tokenKeys = keys;
        token.maxSupply = maxSupply;
        token.freezeDefault = false;
        token.expiry = createAutoRenewExpiry(address(this), autoRenewPeriod); // Contract automatically renew by himself
 
       (int responseCode, address createdToken) = HederaTokenService.createNonFungibleToken(token);
 
       if(responseCode != HederaResponseCodes.SUCCESS){
           revert("Failed to create non-fungible token");
       }
       return (createdToken, keys);
   }

    function mintNonFungibleToken(
           address token,
           bytes[] memory metadata
       ) public returns (int responseCode, uint64 newTotalSupply, int64[] memory serialNumbers)  {
        (responseCode, newTotalSupply, serialNumbers) = HederaTokenService.mintToken(token, 0, metadata);
       
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert();
        }
    }

    function transferNonFungibleToken(
           address token,
           address sender,
           address receiver,
           int64 serialNumber
       ) external payable {
 
       (int responseCode) = 
       HederaTokenService.transferNFT(token, sender, receiver, serialNumber);
 
       if(responseCode != HederaResponseCodes.SUCCESS){
           revert("Failed to create non-fungible token");
       }
   }

    function associateNonFungibleToken(
           address account,
           address token
       ) external {
 
       (int responseCode) = 
       HederaTokenService.associateToken(account, token);
 
       if(responseCode != HederaResponseCodes.SUCCESS){
           revert("Failed to create non-fungible token");
       }
   }
 
}