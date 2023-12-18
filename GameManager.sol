// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IGameToken.sol";
import "./interface/ITokenReservoir.sol";

struct RakeDistribution {
    uint256 xmannaReward;
    uint256 userReward;
    uint256 gameDeveloperReward;
    uint256 channelOperatorReward;
    address xmannaRewardAddress;
    address userRewardAddress;
    address gameDeveloperRewardAddress;
    address channelOperatorRewardAddress;
}

struct PlayOption {
    uint256 rakePercentage;
    uint256 gameCharges;
    uint256 noOfPlayers;
    string gameId;
    string playOptionType;
}

struct FundTaken {
    uint256 usd;
    uint256 bonus;
    string tokenId;
    uint256 tokenValue;
}

contract GameManager is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public reservoirContractAddress;
    address public challengeContractAddress;
    address public deathmatchContractAddress;

    mapping(string => RakeDistribution) public rakeDistValues;
    mapping(string => bool) public rakeDistFlags;

    mapping(string => PlayOption) public playOptValues;
    mapping(string => bool) private playOptFlags;
    mapping(string => bool) public isPlayOptAvailable;

    mapping(string => string[]) public gameIdPlayOptions;

    function initialize() public initializer {
        __Ownable_init();
    }

     //Set Contract Addresses
    function setContractAddresses(address _reservoir, address _challenge, address _deathmatch) external returns (bool) {
        if (_reservoir == address(0) || _challenge == address(0) || _deathmatch == address(0)) revert('Address cannot be empty');
        reservoirContractAddress = _reservoir;
        challengeContractAddress = _challenge;
        deathmatchContractAddress = _deathmatch;
        return true;
    }

    function onlyGameContract() internal view{
        if(msg.sender == challengeContractAddress || msg.sender == deathmatchContractAddress)
        return;
        else revert('Only game contracts can call this function');
    }

    // Rake Distribution CRUD
    function _setRakeDistribution(
        string calldata rakeId_,
        RakeDistribution calldata rakeDistValues_
    ) internal {
        require(
            rakeDistValues_.xmannaReward +
                rakeDistValues_.userReward +
                rakeDistValues_.gameDeveloperReward +
                rakeDistValues_.channelOperatorReward ==
                100,
            "distributions did not add up to 100"
        );
        rakeDistFlags[rakeId_] = true;
        rakeDistValues[rakeId_] = rakeDistValues_;
    }

    function createRakeDistribution(
        string calldata rakeId_,
        RakeDistribution calldata rakeDistValues_
    ) external onlyOwner returns (bool) {
        if (rakeDistFlags[rakeId_]) return false; // already there
        _setRakeDistribution(rakeId_, rakeDistValues_);
        return true;
    }

    function updateRakeDistribution(
        string calldata rakeId_,
        RakeDistribution calldata rakeDistValues_
    ) external onlyOwner returns (bool) {
        if (!rakeDistFlags[rakeId_]) return false; // already there
        _setRakeDistribution(rakeId_, rakeDistValues_);
        return true;
    }

    function getRakeDistribution(string calldata rakeId_)
        public
        view
        returns (RakeDistribution memory)
    {
        return rakeDistValues[rakeId_];
    }

    // Play Option CRUD

    function _setPlayOption(
        string calldata playOptionId_,
        PlayOption calldata value_
    ) internal {
        require(value_.rakePercentage <= 50, "charges should not be gt 50");
        require(value_.gameCharges > 0, "charges should be gt 0");
        require(value_.noOfPlayers > 0, "no of players should be gt 0");
        playOptFlags[playOptionId_] = true;
        isPlayOptAvailable[playOptionId_] = true;
        playOptValues[playOptionId_] = value_;
    }

    function createPlayOption(
        string calldata playOptionId_,
        PlayOption calldata value_
    ) external onlyOwner returns (bool) {
        if (playOptFlags[playOptionId_]) return false; // already there
        _setPlayOption(playOptionId_, value_);
        gameIdPlayOptions[value_.gameId].push(playOptionId_);
        return true;
    }

    function updatePlayOption(
        string calldata playOptionId_,
        PlayOption calldata value_
    ) external onlyOwner returns (bool) {
        if (!playOptFlags[playOptionId_]) return false; // already there
        _setPlayOption(playOptionId_, value_);
        return true;
    }

    function enableDisablePlayOpton(string calldata playOptionId_, bool enable_)
        external
        onlyOwner
        returns (bool)
    {
        if (!playOptFlags[playOptionId_]) return false;
        isPlayOptAvailable[playOptionId_] = enable_;
        return true;
    }

    function getPlayOption(string calldata playOptionId_)
        public
        view
        returns (PlayOption memory)
    {
        return playOptValues[playOptionId_];
    }

    function getPlayOptionByGameId(string calldata gameId_)
        public
        view
        returns (string[] memory)
    {
        return gameIdPlayOptions[gameId_];
    }

    //take funds
    function takeFunds(
        string calldata tokenId,
        uint256 gameCharges,
        address player
    ) external returns (FundTaken memory) {
       
        onlyGameContract();
        ITokenReservoir xReservoir = ITokenReservoir(reservoirContractAddress);
        //check input values
        require(gameCharges > 0, "Game chargegreater than 0");
        require(player != address(0), "Invalid player addr");
        require(xReservoir.isReservoirTokenAvailable(tokenId), "Unsupported Token");

        FundTaken memory fundTaken = FundTaken(0, 0, "", 0);
        address usd = xReservoir.getTokenAddress("usd");
        address bonus = xReservoir.getTokenAddress("bonus");
        address playerAddress = player;
        uint256 charge = gameCharges;
        string memory playerToken = tokenId;

        //check which token
        if (
            keccak256(abi.encodePacked((tokenId))) ==
            keccak256(abi.encodePacked(("usd")))
        ) {
            IGameToken xUSD = IGameToken(usd);
            IGameToken xBonus = IGameToken(bonus);
            uint256 requiredXUSD = (charge.mul(90)).div(100);
            uint256 requiredXBonus = (charge.mul(10)).div(100);
            uint256 usdBalance = xUSD.balanceOf(playerAddress);
            uint256 bonusBalance = xBonus.balanceOf(playerAddress);
            uint256 usdToTake = 0;
            uint256 bonusToTake = 0;

            // have enough usd
            if (usdBalance >= requiredXUSD) {
                usdToTake = requiredXUSD;
                // have enough bonus
                if (bonusBalance >= requiredXBonus) {
                    bonusToTake = requiredXBonus;
                }
                // have enough usd + additional but not enough bonus
                else if (bonusBalance > 0) {
                    bonusToTake = bonusBalance;
                    usdToTake = usdToTake.add(requiredXBonus.sub(bonusToTake));
                } else {
                    usdToTake = usdToTake.add(requiredXBonus);
                }
            }
            // have less usd for the game
            else if (usdBalance < requiredXUSD) {
                if (usdBalance > 0) {
                    usdToTake = usdBalance;
                    uint256 balanceXUSDRequired = requiredXUSD.sub(usdToTake);
                    // have enought bonus for total game amount
                    bonusToTake = balanceXUSDRequired.add(requiredXBonus);
                } else {
                    bonusToTake = requiredXUSD.add(requiredXBonus);
                }
            }
            require(usdBalance >= usdToTake, "insufficiant usd");
            require(bonusBalance >= bonusToTake, "insufficiant bonus");
            // Take funds from user
            xUSD.takeFunds(playerAddress, address(this), usdToTake);
            xBonus.takeFunds(playerAddress, address(this), bonusToTake);

            fundTaken = FundTaken(usdToTake, bonusToTake, "usd", usdToTake);
        }
        if (
            keccak256(abi.encodePacked((playerToken))) !=
            keccak256(abi.encodePacked(("usd")))
        ) {
            uint256 tokenValue = xReservoir.getTokenValue(playerToken);
            uint256 requiredToken = gameCharges.mul(tokenValue);
            address tokenAddress = xReservoir.getTokenAddress(playerToken);
            address reservoirAddress = reservoirContractAddress;
            uint256 reservoirBalance = IERC20(tokenAddress).balanceOf(
                reservoirAddress
            );
            require(
                reservoirBalance >= requiredToken,
                "Insufficent reservoir balance"
            );
            uint256 playerBalance = IERC20(tokenAddress).balanceOf(playerAddress);
            require(
                playerBalance >= requiredToken,
                "Insufficent player balance"
            );

            //check token allowance in reservoir and user account
            uint256 reservoirAllowance = IERC20(tokenAddress).allowance(
                reservoirAddress,
                address(this)
            );
            require(
                reservoirAllowance >= requiredToken,
                "reservoir Token not approved"
            );

            uint256 playerAllowance = IERC20(tokenAddress).allowance(
                playerAddress,
                address(this)
            );
            require(
                playerAllowance >= requiredToken,
                "player Token not approved"
            );

            //transfer required token to reservoir acc from user acc
            IERC20(tokenAddress).transferFrom(
                playerAddress,
                reservoirAddress,
                requiredToken
            );

            //transfer xusd fromm reservoir to challenge contract
            uint256 usdToTransfer = charge;
            IGameToken xUSD = IGameToken(usd);
            xUSD.takeFunds(reservoirAddress, address(this), usdToTransfer);
            fundTaken = FundTaken(usdToTransfer, 0, playerToken, requiredToken);
        }
        return fundTaken;
    }

    //transfer funds
    function transferFunds(
        string calldata tokenId,
        address player,
        uint256 usdToTransfer,
        uint256 bonusToTransfer
    ) external {
        onlyGameContract();
        ITokenReservoir xReservoir = ITokenReservoir(reservoirContractAddress);
        require(player != address(0), "Invalid player addr");
        require(xReservoir.isReservoirTokenAvailable(tokenId), "Unsupported Token");

        address usd = xReservoir.getTokenAddress("usd");
        address bonus = xReservoir.getTokenAddress("bonus");
        address playerAddress = player;
        string memory playerToken = tokenId;

        IGameToken xUSD = IGameToken(usd);
        IGameToken xBonus = IGameToken(bonus);
        if (usdToTransfer > 0) {
            if (
                keccak256(abi.encodePacked((tokenId))) ==
                keccak256(abi.encodePacked(("usd")))
            ) {
                xUSD.transfer(player, usdToTransfer);
            } else {
                //get token value
                uint256 tokenValue = xReservoir.getTokenValue(playerToken);
                //calculate required xusd
                uint256 requiredToken = usdToTransfer.mul(tokenValue);
                //transfer xusd to reservoir
                address reservoirAddress = reservoirContractAddress;
                xUSD.transfer(reservoirAddress, usdToTransfer);
                //transfer token to player account
                address tokenAddress = xReservoir.getTokenAddress(playerToken);
                uint256 reservoirBalance = IERC20(tokenAddress).balanceOf(
                    reservoirAddress
                );
                require(
                    reservoirBalance >= requiredToken,
                    "Insufficent balance reservoir"
                );
                uint256 reservoirAllowance = IERC20(tokenAddress).allowance(
                    reservoirAddress,
                    address(this)
                );
                require(
                    reservoirAllowance >= requiredToken,
                    "Token not approved from reservoir "
                );
                IERC20(tokenAddress).transferFrom(
                    reservoirAddress,
                    playerAddress,
                    requiredToken
                );
            }
        }
        if (bonusToTransfer > 0) {
            xBonus.transfer(player, bonusToTransfer);
        }
    }
    function mintUsd(uint256 amount) external {
        onlyGameContract();
        ITokenReservoir xReservoir = ITokenReservoir(reservoirContractAddress);
        IGameToken usd = IGameToken(xReservoir.getTokenAddress("usd"));
        usd.mint(address(this), amount);
    }
    /**
        The leftover bonus cash token that resides on the contract can be withdrawn to any address 
     */
    function transferBonus(address to, uint256 amount) external onlyOwner {
        ITokenReservoir xReservoir = ITokenReservoir(reservoirContractAddress);
        IGameToken xBonus = IGameToken(xReservoir.getTokenAddress("bonus"));
        xBonus.transfer(to, amount);
    }
}
