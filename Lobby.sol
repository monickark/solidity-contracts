// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interface/IGameManager.sol";
import "./interface/IGameToken.sol";

struct LobbyPlayer {
    address player;
    string playOptionId;
    string channelOperatorId;
    string rakeId;
    uint256 usd;
    uint256 bonus;
    string tokenId;
    uint256 tokenValue;
}

struct JoinLobby {
    address player;
    string playOptionId;
    string channelOpId;
    string tokenId;
}

contract Lobby is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    // External contract address
    address gameManager;

    // Configurations
    mapping(uint256 => uint256[]) public winnerAndWinnings;

    // Game
    // Player address -> Player detail with deposit and play option info
    mapping(address => LobbyPlayer) public playersDataInLobby;
    // Player address -> true/false to check If user in lobby already
    mapping(address => bool) public playersInLobby;
    // Player address -> true/false to check If user in a game already
    mapping(address => bool) public isPlayerInRoom;
    // Room id -> Player address list in the room
    mapping(string => address[]) public playersInRoom;
    // Room id -> true/false to check If Allocated already
    mapping(string => bool) public allocatedRoom;
    // Room id -> Play option id mapping to find game value, and rake calculations
    mapping(string => string) public roomAndPlayOption;
    // Room id -> usd funds deposited by players
    mapping(string => uint256) public roomAndUsdFunds;
    // Usd Minted for challenge
    uint256 public mintedUsd;

    // Events
    event Rake(address player, uint256 usd);
    event Wager(address player, uint256 usd, uint256 bonus);
    event WagerRefund(address player, uint256 usd, uint256 bonus);
    event Win(address player, uint256 usd, uint256 bonus);

    function initialize() public initializer {
        __Ownable_init();
        mintedUsd = 0;
    }

    function setGameManager(address address_) external onlyOwner {
        gameManager = address_;
    }

    function getGameManager() public view onlyOwner returns (address) {
        return gameManager;
    }

    function setWinnerAndWinnings(
        uint256 winnerCount_,
        uint256[] calldata winnings_
    ) external onlyOwner {
        require(
            winnings_.length == winnerCount_,
            "winner count not eq distributions"
        );
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < winnings_.length; i++) {
            totalPercentage = totalPercentage.add(winnings_[i]);
        }
        require(totalPercentage == 100, "distributions total is not 100");
        winnerAndWinnings[winnerCount_] = winnings_;
    }

    /**
        Player eligiblity is checked against the play option he is playing for and allow him to enter lobby after taking funds from account
     */
    function joinLobby(JoinLobby calldata joinLobbyReq) external onlyOwner {
        IGameManager _gameManager = IGameManager(gameManager);
        require(
            _gameManager.isPlayOptAvailable(joinLobbyReq.playOptionId),
            "play option is not available"
        );
        require(!playersInLobby[joinLobbyReq.player], "already in lobby");
        PlayOption memory playOption = _gameManager.getPlayOption(
            joinLobbyReq.playOptionId
        );
        string memory rakeId;
        // Check if Channel Operator Id is given else use Game id for Rake Distribution or default
        if (_gameManager.rakeDistFlags(joinLobbyReq.channelOpId)) {
            rakeId = joinLobbyReq.channelOpId;
        }else if (_gameManager.rakeDistFlags(playOption.gameId)) {
            rakeId = playOption.gameId;
        }else if (bytes(joinLobbyReq.channelOpId).length > 0 && _gameManager.rakeDistFlags('default-channelOperator')) {
            rakeId = "default-channelOperator";
        }else if (bytes(playOption.gameId).length > 0 && _gameManager.rakeDistFlags('default-sdk')) {
            rakeId = 'default-sdk';
        }else{
            revert("Rake distribution not found");
        }
        FundTaken memory fundTaken = _gameManager.takeFunds(
            joinLobbyReq.tokenId,
            playOption.gameCharges,
            joinLobbyReq.player
        );
        playersDataInLobby[joinLobbyReq.player] = LobbyPlayer(
            joinLobbyReq.player,
            joinLobbyReq.playOptionId,
            joinLobbyReq.channelOpId,
            rakeId,
            fundTaken.usd,
            fundTaken.bonus,
            fundTaken.tokenId,
            fundTaken.tokenValue
        );
        playersInLobby[joinLobbyReq.player] = true;
        emit Wager(joinLobbyReq.player, fundTaken.usd, fundTaken.bonus);
    }

    /**
     Player exists himself from lobby and receive refund
     */
    function exitLobby(address player_) external onlyOwner returns (bool) {
        require(playersInLobby[player_], "player not in lobby");
        require(!isPlayerInRoom[player_], "player is in a room");
        IGameManager _gameManager = IGameManager(gameManager);

        _gameManager.transferFunds(
            playersDataInLobby[player_].tokenId,
            player_,
            playersDataInLobby[player_].usd,
            playersDataInLobby[player_].bonus
        );
        delete playersDataInLobby[player_];
        playersInLobby[player_] = false;
        emit WagerRefund(
            player_,
            playersDataInLobby[player_].usd,
            playersDataInLobby[player_].bonus
        );
        return true;
    }

    /**
        Create death match game room with the given players
     */
    function createDeathMatchRoom(
        address[] calldata players_,
        string calldata roomId_,
        string calldata playOptionId_
    ) external onlyOwner {
        IGameManager _gameManager = IGameManager(gameManager);
        require(!allocatedRoom[roomId_], "room already allocated");
        require(
            _gameManager.isPlayOptAvailable(playOptionId_),
            "play option not available"
        );
        PlayOption memory _playOption = _gameManager.getPlayOption(
            playOptionId_
        );
        uint256 noOfPlayers = _playOption.noOfPlayers;
        require(
            !(noOfPlayers > players_.length),
            "play option requires more players"
        );
        require(
            !(noOfPlayers < players_.length),
            "play option requires less players"
        );
        uint256 usdDeposits = 0;
        // check if all the players are in the lobby
        for (uint256 i = 0; i < players_.length; i++) {
            require(
                playersInLobby[players_[i]],
                "players must enter lobby first"
            );
            isPlayerInRoom[players_[i]] = true;
            usdDeposits = usdDeposits.add(playersDataInLobby[players_[i]].usd);
        }
        // move players to a room and store the playoption the players are playing for
        playersInRoom[roomId_] = players_;
        allocatedRoom[roomId_] = true;
        roomAndPlayOption[roomId_] = playOptionId_;
        roomAndUsdFunds[roomId_] = usdDeposits;
    }

    function distributeRake(string calldata roomId_, uint256 usdTransferred_)
        internal
    {
        IGameManager _gameManager = IGameManager(gameManager);

        PlayOption memory _playOption = _gameManager.getPlayOption(
            roomAndPlayOption[roomId_]
        );

        address[] memory _players = playersInRoom[roomId_];
        uint256 roomFunds = roomAndUsdFunds[roomId_];

        uint256 _balanceRake = 0;
        uint256 rakeAmountEachPlayer = 0;
        if (usdTransferred_ < roomFunds) {
            _balanceRake = roomFunds.sub(usdTransferred_);
            rakeAmountEachPlayer = _balanceRake.div(_playOption.noOfPlayers);
        }

        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            string memory rakeId = playersDataInLobby[player].rakeId;

            // Remove player from room and lobby
            delete playersDataInLobby[player];
            playersInLobby[player] = false;
            isPlayerInRoom[player] = false;

            if (_balanceRake > 0) {
                RakeDistribution memory rakeDistribution = _gameManager
                    .getRakeDistribution(rakeId);

                if (rakeDistribution.xmannaReward > 0) {
                    uint256 xmannaRewardShare = rakeAmountEachPlayer.mul(
                        rakeDistribution.xmannaReward
                    );
                    xmannaRewardShare = xmannaRewardShare.div(100);
                    if (xmannaRewardShare > 0) {
                        emit Rake(
                            rakeDistribution.xmannaRewardAddress,
                            xmannaRewardShare
                        );
                        _gameManager.transferFunds(
                            "usd",
                            rakeDistribution.xmannaRewardAddress,
                            xmannaRewardShare,
                            0
                        );
                    }
                }
                if (rakeDistribution.userReward > 0) {
                    uint256 userRewardShare = rakeAmountEachPlayer.mul(
                        rakeDistribution.userReward
                    );
                    userRewardShare = userRewardShare.div(100);
                    if (userRewardShare > 0) {
                        emit Rake(
                            rakeDistribution.userRewardAddress,
                            userRewardShare
                        );
                        _gameManager.transferFunds(
                            "usd",
                            rakeDistribution.userRewardAddress,
                            userRewardShare,
                            0
                        );
                    }
                }
                if (rakeDistribution.gameDeveloperReward > 0) {
                    uint256 gameDeveloperRewardShare = rakeAmountEachPlayer.mul(
                        rakeDistribution.gameDeveloperReward
                    );
                    gameDeveloperRewardShare = gameDeveloperRewardShare.div(
                        100
                    );
                    if (gameDeveloperRewardShare > 0) {
                        emit Rake(
                            rakeDistribution.gameDeveloperRewardAddress,
                            gameDeveloperRewardShare
                        );
                        _gameManager.transferFunds(
                            "usd",
                            rakeDistribution.gameDeveloperRewardAddress,
                            gameDeveloperRewardShare,
                            0
                        );
                    }
                }
                if (rakeDistribution.channelOperatorReward > 0) {
                    uint256 channelOperatorRewardShare = rakeAmountEachPlayer
                        .mul(rakeDistribution.channelOperatorReward);
                    channelOperatorRewardShare = channelOperatorRewardShare.div(
                            100
                        );
                    if (channelOperatorRewardShare > 0) {
                        emit Rake(
                            rakeDistribution.channelOperatorRewardAddress,
                            channelOperatorRewardShare
                        );
                        _gameManager.transferFunds(
                            "usd",
                            rakeDistribution.channelOperatorRewardAddress,
                            channelOperatorRewardShare,
                            0
                        );
                    }
                }
            }
        }
    }

    function mintUsd(uint256 amount) internal {
        IGameManager _gameManager = IGameManager(gameManager);
        _gameManager.mintUsd(amount);
        mintedUsd = mintedUsd.add(amount);
    }

    /**
        Close death match game room and do transfers to winners and perform rake distribution as per individual player source
     */
    function endDeathMatchRoom(
        address[] calldata winners_,
        string calldata roomId_
    ) external onlyOwner {
        address[] memory _winners = winners_;
        IGameManager _gameManager = IGameManager(gameManager);
        require(
            _gameManager.isPlayOptAvailable(roomAndPlayOption[roomId_]),
            "play option not available"
        );
        uint256[] memory winningPercentages = winnerAndWinnings[
            _winners.length
        ];
        PlayOption memory _playOption = _gameManager.getPlayOption(
            roomAndPlayOption[roomId_]
        );

        uint256 deposit = _playOption.noOfPlayers.mul(_playOption.gameCharges);
        uint256 rakeAmount = deposit.div(120);
        rakeAmount = rakeAmount.mul(_playOption.rakePercentage);
        uint256 winnersReceive = deposit.sub(rakeAmount);

        uint256 roomFunds = roomAndUsdFunds[roomId_];
        uint256 usdTransferred = 0;

        for (uint256 i = 0; i < _winners.length; i++) {
            address winner = _winners[i];
            uint256 winAmountBase = winnersReceive.mul(winningPercentages[i]);
            uint256 winAmount = winAmountBase.div(100);
            uint256 usdToTransfer = winAmount;
            uint256 bonusToTransfer = playersDataInLobby[winner].bonus;
            if (winAmount > bonusToTransfer) {
                usdToTransfer = usdToTransfer.sub(bonusToTransfer);
            }
            if (winAmount <= bonusToTransfer) {
                usdToTransfer = 0;
                bonusToTransfer = winAmount;
            }
            // Insufficiant usd funds so mint tokens
            if (roomFunds == 0) {
                mintUsd(usdToTransfer);
            } else if (usdTransferred > roomFunds) {
                mintUsd(usdToTransfer);
            } else if (roomFunds.sub(usdTransferred) < usdToTransfer) {
                mintUsd(usdToTransfer);
            }
            if (usdToTransfer > 0) {
                usdTransferred = usdTransferred.add(usdToTransfer);
            }
            _gameManager.transferFunds(
                playersDataInLobby[winner].tokenId,
                winner,
                usdToTransfer,
                bonusToTransfer
            );
            emit Win(winner, usdToTransfer, bonusToTransfer);
        }
        // rake distribution when there is execess
        distributeRake(roomId_, usdTransferred);
    }

    /**
        Exit death match game room and refund players deposit
     */
    function exitDeathMatchRoom(string calldata roomId_) external onlyOwner {
        IGameManager _gameManager = IGameManager(gameManager);

        address[] memory _players = playersInRoom[roomId_];

        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            _gameManager.transferFunds(
                playersDataInLobby[player].tokenId,
                player,
                playersDataInLobby[player].usd,
                playersDataInLobby[player].bonus
            );
            // Remove player from room and lobby
            delete playersDataInLobby[player];
            playersInLobby[player] = false;
            isPlayerInRoom[player] = false;
            emit WagerRefund(
                player,
                playersDataInLobby[player].usd,
                playersDataInLobby[player].bonus
            );
        }
    }
}
