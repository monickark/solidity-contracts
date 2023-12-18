// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct ReservoirToken {
    address tokenAddress;
    uint256 tokenValue;
}

contract TokenReservoir is OwnableUpgradeable {
    address private GameManager;

    string[] public reservoirTokens;
    uint256 public tokenCount;
    mapping(string => ReservoirToken) public reservoirTokenList;
    mapping(string => bool) private reservoirTokenFlag;
    mapping(string => bool) public isReservoirTokenAvailable;

    function initialize() public initializer {
        __Ownable_init();
    }

    function setGameManager(address _challengeContract) external onlyOwner {
        GameManager = _challengeContract;
    }

    function getGameManager() public view onlyOwner returns (address) {
        return GameManager;
    }

    function addReservoirToken(
        string calldata name_,
        address address_,
        uint256 tokenValue_
    ) external onlyOwner returns (bool) {
        if (reservoirTokenFlag[name_]) revert('Token already exist'); // already there
        reservoirTokenList[name_].tokenAddress = address_;
        reservoirTokenList[name_].tokenValue = tokenValue_;
        reservoirTokenFlag[name_] = true;
        isReservoirTokenAvailable[name_] = true;
        reservoirTokens.push(name_);
        tokenCount++;
        return true;
    }

    function getTokenCount() public view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < tokenCount; i++) {
            if (isReservoirTokenAvailable[reservoirTokens[i]] == true) {
                count++;
            }
        }
        return count;
    }

    function getTokenList() public view onlyOwner returns (string[] memory) {
        uint256 count = getTokenCount();
        string[] memory tokenlist = new string[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < tokenCount; i++) {
            if (isReservoirTokenAvailable[reservoirTokens[i]] == true) {
                tokenlist[j] = reservoirTokens[i];
                j++;
            }
        }
        return tokenlist;
    }

    function updateTokenValue(string calldata name_, uint256 tokenValue_)
        external
        onlyOwner
        returns (bool)
    {
        if (!(reservoirTokenFlag[name_])) revert("Token doesn't exist"); // not there
        reservoirTokenList[name_].tokenValue = tokenValue_;
        return true;
    }

    function updateTokenAddress(string calldata name_, address tokenAddress_)
        external
        onlyOwner
        returns (bool)
    {
        if (!(reservoirTokenFlag[name_])) revert("Token doesn't exist"); // not there
        reservoirTokenList[name_].tokenAddress = tokenAddress_;
        return true;
    }

    function enableDisableReservoirToken(string calldata name_, bool enable_)
        external
        onlyOwner
        returns (bool)
    {
        if (!(reservoirTokenFlag[name_])) return false; // not there
        isReservoirTokenAvailable[name_] = enable_;
        return true;
    }

 

    function getTokenValue(string memory name_) public view returns (uint256) {
        ReservoirToken memory reservoirToken = reservoirTokenList[name_];
        return reservoirToken.tokenValue;
    }

    function getTokenAddress(string memory name_)
        public
        view
        returns (address)
    {
        ReservoirToken memory reservoirToken = reservoirTokenList[name_];
        return reservoirToken.tokenAddress;
    }

    function approveToken(address _tokenAddress)
        external
        onlyOwner
        returns (bool)
    {
        uint256 tokenBalance = IERC20(_tokenAddress).balanceOf(address(this));
        IERC20(_tokenAddress).approve(GameManager, tokenBalance);
        return true;
    }
}
