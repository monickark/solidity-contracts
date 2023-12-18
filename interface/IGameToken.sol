// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IGameToken {
    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

    function takeFunds(
        address from,
        address to,
        uint256 amount
    ) external;

    function transfer(address to, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}
