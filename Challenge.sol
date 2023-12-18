// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IGameManager.sol";
import "./interface/IGameToken.sol";

struct PlayerDeposit {
    address player;
    string channelOperatorId;
    string rakeId;
    uint256 usd;
    uint256 bonus;
    string tokenId;
    uint256 tokenValue;
}
struct CreateChallenge {
    address player;
    string playOptionId;
    string channelOpId;
    string challengeId;
    string tokenId;
}
struct JoinChallenge {
    address player;
    string channelOpId;
    string challengeId;
    string tokenId;
}

contract Challenge is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    // External contract address
    address gameManager;

    // Configurations
    mapping(uint256 => uint256[]) public winnerAndWinnings;

    // Game
    // Challenge Id -> Players and deposit info
    mapping(string => mapping(address => PlayerDeposit))
        public challengeAndPlayers;
    // Challenge id -> Player address list in the challenge
    mapping(string => address[]) public playersInChallenge;
    // Challenge Id -> Play option id
    mapping(string => string) public challengeAndPlayOption;
    // Challenge Id -> true/false to check If challenge is created already
    mapping(string => bool) public isChallengeCreated;
    // Challenge Id -> true/false to check If challenge is ended
    mapping(string => bool) public isChallengeEnded;
    // Challenge id -> usd funds deposited by players
    mapping(string => uint256) public challengeAndUsdFunds;
    // Usd Minted for challenge
    uint256 public mintedUsd;

    // Events
    event Rake(address player, uint256 usd);
    event Wager(address player, uint256 usd, uint256 bonus);
    event WagerRefund(address player, uint256 usd, uint256 bonus);
    event Win(address player, uint256 usd, uint256 bonus);
    event Tie(address player, uint256 usd, uint256 bonus);

    function initialize() public initializer {
        __Ownable_init();
        mintedUsd = 0;
    }

    function setGameManager(address address_) public onlyOwner {
        gameManager = address_;
    }

    function getGameManager() public view returns (address) {
        return gameManager;
    }

    function setWinnerAndWinnings(
        uint256 winnerCount_,
        uint256[] calldata winnings_
    ) public onlyOwner {
        require(winnings_.length == winnerCount_, "winner count not eq");
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < winnings_.length; i++) {
            totalPercentage = totalPercentage.add(winnings_[i]);
        }
        require(totalPercentage == 100, "total is not 100");
        winnerAndWinnings[winnerCount_] = winnings_;
    }

    function distributeRake(string memory challengeId_, uint256 usdTransferred_)
        internal
    {
        IGameManager _gameManager = IGameManager(gameManager);
        PlayOption memory _playOption = _gameManager.getPlayOption(
            challengeAndPlayOption[challengeId_]
        );
        address[] memory _players = playersInChallenge[challengeId_];
        uint256 roomFunds = challengeAndUsdFunds[challengeId_];
        uint256 _balanceRake = 0;
        uint256 rakeAmountEachPlayer = 0;
        if (usdTransferred_ < roomFunds) {
            _balanceRake = roomFunds.sub(usdTransferred_);
            rakeAmountEachPlayer = _balanceRake.div(_playOption.noOfPlayers);
        }
        mapping(address => PlayerDeposit)
            storage playersData = challengeAndPlayers[challengeId_];
        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            string memory rakeId = playersData[player].rakeId;
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

    /**
        Check player eligiblity and let him create challenge after taking his funds
     */
    function addNewChallenge(CreateChallenge calldata createChallenge)
        external
        onlyOwner
    {
        IGameManager _gameManager = IGameManager(gameManager);
        require(
            !isChallengeCreated[createChallenge.challengeId],
            "challenge already created"
        );
        address player = createChallenge.player;
        string memory playOptionId = createChallenge.playOptionId;
        require(
            _gameManager.isPlayOptAvailable(playOptionId),
            "play option is not available"
        );
        PlayOption memory playOption = _gameManager.getPlayOption(playOptionId);
        string memory rakeId;

         // Check if Channel Operator Id is given else use Game id for Rake Distribution or default
        if (_gameManager.rakeDistFlags(createChallenge.channelOpId)) {
            rakeId = createChallenge.channelOpId;
        }else if (_gameManager.rakeDistFlags(playOption.gameId)) {
            rakeId = playOption.gameId;
        }else if (bytes(createChallenge.channelOpId).length > 0 && _gameManager.rakeDistFlags('default-channelOperator')) {
            rakeId = "default-channelOperator";
        }else if (bytes(createChallenge.channelOpId).length > 0 && _gameManager.rakeDistFlags('default-sdk')) {
            rakeId = 'default-sdk';
        }else{
            revert("Rake distribution not found");
        }

        isChallengeCreated[createChallenge.challengeId] = true;
        FundTaken memory fundTaken = _gameManager.takeFunds(
            createChallenge.tokenId,
            playOption.gameCharges,
            player
        );
        challengeAndUsdFunds[createChallenge.challengeId] = fundTaken.usd;
        PlayerDeposit memory playerDeposit = PlayerDeposit(
            player,
            createChallenge.channelOpId,
            rakeId,
            fundTaken.usd,
            fundTaken.bonus,
            createChallenge.tokenId,
            fundTaken.tokenValue
        );
        challengeAndPlayers[createChallenge.challengeId][
            player
        ] = playerDeposit;
        challengeAndPlayOption[createChallenge.challengeId] = playOptionId;
        playersInChallenge[createChallenge.challengeId] = [player];
        emit Wager(player, fundTaken.usd, fundTaken.bonus);
    }

    /**
        Check player eligiblity and let him join existing challenge after taking his funds
     */
    function joinExistingChallenge(JoinChallenge calldata joinChallenge)
        external
        onlyOwner
    {
        IGameManager _gameManager = IGameManager(gameManager);
        require(
            isChallengeCreated[joinChallenge.challengeId],
            "challenge is not created"
        );
        require(
            !isChallengeEnded[joinChallenge.challengeId],
            "challenge is already ended"
        );
        address player = joinChallenge.player;
        string memory challengeId = joinChallenge.challengeId;
        string memory playOptionId = challengeAndPlayOption[challengeId];
        PlayOption memory playOption = _gameManager.getPlayOption(playOptionId);
        string memory rakeId;

       // Check if Channel Operator Id is given else use Game id for Rake Distribution or default
        if (_gameManager.rakeDistFlags(joinChallenge.channelOpId)) {
            rakeId = joinChallenge.channelOpId;
        }else if (_gameManager.rakeDistFlags(playOption.gameId)) {
            rakeId = playOption.gameId;
        }else if (bytes(joinChallenge.channelOpId).length > 0 && _gameManager.rakeDistFlags('default-channelOperator')) {
            rakeId = "default-channelOperator";
        }else if (bytes(joinChallenge.channelOpId).length > 0 && _gameManager.rakeDistFlags('default-sdk')) {
            rakeId = 'default-sdk';
        }else{
            revert("Rake distribution not found");
        }

        FundTaken memory fundTaken = _gameManager.takeFunds(
            joinChallenge.tokenId,
            playOption.gameCharges,
            player
        );
        challengeAndUsdFunds[challengeId] = challengeAndUsdFunds[challengeId]
            .add(fundTaken.usd);
        PlayerDeposit memory playerDeposit = PlayerDeposit(
            player,
            joinChallenge.channelOpId,
            rakeId,
            fundTaken.usd,
            fundTaken.bonus,
            joinChallenge.tokenId,
            fundTaken.tokenValue
        );
        challengeAndPlayers[challengeId][player] = playerDeposit;
        playersInChallenge[challengeId].push(player);
        require(
            playersInChallenge[challengeId].length <= playOption.noOfPlayers,
            "players allowed count overflow"
        );
        emit Wager(player, fundTaken.usd, fundTaken.bonus);
    }

    function mintUsd(uint256 amount) internal {
        IGameManager _gameManager = IGameManager(gameManager);
        _gameManager.mintUsd(amount);
        mintedUsd = mintedUsd.add(amount);
    }

    /**
        End Challenge do transfers to winners and perform rake distribution as per individual player source
     */
    function endChallenge(
        address[] calldata winners_,
        string calldata challengeId_
    ) external onlyOwner {
        require(isChallengeCreated[challengeId_], "challenge is not created");
        require(!isChallengeEnded[challengeId_], "challenge is already ended");
        string memory _challengeId = challengeId_;
        address[] memory _winners = winners_;
        address[] memory _players = playersInChallenge[_challengeId];
        require(
            _players.length != _winners.length,
            "all players can not be winners"
        );

        isChallengeEnded[_challengeId] = true;

        IGameManager _gameManager = IGameManager(gameManager);
        uint256[] memory winningPercentages = winnerAndWinnings[
            _winners.length
        ];
        string memory playOptionId = challengeAndPlayOption[_challengeId];
        PlayOption memory _playOption = _gameManager.getPlayOption(
            playOptionId
        );

        require(
            _players.length == _playOption.noOfPlayers,
            "players yet to join"
        );

        uint256 deposit = _playOption.noOfPlayers.mul(_playOption.gameCharges);
        uint256 rakeAmount = deposit.div(120);
        rakeAmount = rakeAmount.mul(_playOption.rakePercentage);
        uint256 winnersReceive = deposit.sub(rakeAmount);

        uint256 challengeFunds = challengeAndUsdFunds[_challengeId];
        mapping(address => PlayerDeposit)
            storage playersData = challengeAndPlayers[_challengeId];
        uint256 usdTransferred = 0;

        for (uint256 i = 0; i < _winners.length; i++) {
            address winner = _winners[i];
            uint256 winAmountBase = winnersReceive.mul(winningPercentages[i]);
            uint256 winAmount = winAmountBase.div(100);
            uint256 usdToTransfer = winAmount;
            uint256 bonusToTransfer = playersData[winner].bonus;
            if (winAmount > bonusToTransfer) {
                usdToTransfer = winAmount.sub(bonusToTransfer);
            }
            if (winAmount <= bonusToTransfer) {
                usdToTransfer = 0;
                bonusToTransfer = winAmount;
            }
            // Insufficiant usd funds so mint tokens
            if (challengeFunds == 0) {
                mintUsd(usdToTransfer);
            } else if (usdTransferred > challengeFunds) {
                mintUsd(usdToTransfer);
            } else if (challengeFunds.sub(usdTransferred) < usdToTransfer) {
                mintUsd(usdToTransfer);
            }
            if (usdToTransfer > 0) {
                usdTransferred = usdTransferred.add(usdToTransfer);
            }
            _gameManager.transferFunds(
                playersData[winner].tokenId,
                winner,
                usdToTransfer,
                bonusToTransfer
            );

            emit Win(winner, usdToTransfer, bonusToTransfer);
        }
        distributeRake(_challengeId, usdTransferred);
    }

    function drawChallenge(string calldata challengeId_) external onlyOwner {
        require(isChallengeCreated[challengeId_], "challenge is not created");
        require(!isChallengeEnded[challengeId_], "challenge is already ended");
        string memory _challengeId = challengeId_;
        address[] memory _players = playersInChallenge[_challengeId];

        isChallengeEnded[_challengeId] = true;
        IGameManager _gameManager = IGameManager(gameManager);
        string memory playOptionId = challengeAndPlayOption[_challengeId];
        PlayOption memory _playOption = _gameManager.getPlayOption(
            playOptionId
        );
        uint256 deposit = _playOption.noOfPlayers.mul(_playOption.gameCharges);
        uint256 rakeAmount = deposit.div(120);
        rakeAmount = rakeAmount.mul(_playOption.rakePercentage);
        uint256 eachPlayerRake = rakeAmount.div(_players.length);
        uint256 usdTransferred = 0;
        mapping(address => PlayerDeposit)
            storage playersData = challengeAndPlayers[_challengeId];

        for (uint256 i = 0; i < _players.length; i++) {
            uint256 usdToTransfer = 0;
            uint256 bonusToTransfer = 0;
            address player = _players[i];
            uint256 usdBalance = playersData[player].usd;
            uint256 bonusBalance = playersData[player].bonus;

            if (usdBalance >= eachPlayerRake) {
                usdToTransfer = usdBalance.sub(eachPlayerRake);
                bonusToTransfer = bonusBalance;
            } else if (usdBalance < eachPlayerRake) {
                if (usdBalance > 0) {
                    uint256 bonusToTake = eachPlayerRake.sub(usdBalance);
                    bonusToTransfer = bonusBalance.sub(bonusToTake);
                } else {
                    bonusToTransfer = bonusBalance.sub(eachPlayerRake);
                }
            }
            if (usdToTransfer > 0) {
                usdTransferred = usdTransferred.add(usdToTransfer);
            }
            _gameManager.transferFunds(
                playersData[player].tokenId,
                player,
                usdToTransfer,
                bonusToTransfer
            );

            emit Tie(player, usdToTransfer, bonusToTransfer);
        }
        distributeRake(_challengeId, usdTransferred);
    }

    function exitChallenge(string calldata challengeId_) external onlyOwner {
        require(isChallengeCreated[challengeId_], "challenge is not created");
        require(!isChallengeEnded[challengeId_], "challenge is already ended");
        string memory _challengeId = challengeId_;
        address[] memory _players = playersInChallenge[_challengeId];

        IGameManager _gameManager = IGameManager(gameManager);
        mapping(address => PlayerDeposit)
            storage playersData = challengeAndPlayers[_challengeId];
        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            _gameManager.transferFunds(
                playersData[player].tokenId,
                player,
                playersData[player].usd,
                playersData[player].bonus
            );
            emit WagerRefund(
                player,
                playersData[player].usd,
                playersData[player].bonus
            );
        }
        isChallengeEnded[_challengeId] = true;
    }
}
