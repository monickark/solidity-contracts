// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ITokenReservoir {
    function isReservoirTokenAvailable(string calldata name_)
        external
        view
        returns (bool);

    function getTokenValue(string memory name_) external view returns (uint256);

    function getTokenAddress(string memory name_)
        external
        view
        returns (address);
}
