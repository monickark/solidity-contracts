// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

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

interface IGameManager {
    function rakeDistFlags(string memory) view external returns(bool);

    function getRakeDistribution(string calldata rakeId_)
        external
        view
        returns (RakeDistribution memory);

    function isPlayOptAvailable(string memory) view external returns(bool);

    function getPlayOption(string calldata playOptionId_)
        external
        view
        returns (PlayOption memory);

    function gameIdPlayOptions(string memory) view external returns(string memory);

    function takeFunds(
        string calldata tokenId,
        uint256 gameCharges,
        address player
    ) external returns (FundTaken memory);

    function transferFunds(
        string memory tokenId,
        address player,
        uint256 usdToTransfer,
        uint256 bonusToTransfer
    ) external;

    function mintUsd(uint256 amount) external;
}
