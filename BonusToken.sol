// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract BonusToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GAME_CONTRACT_ROLE =
        keccak256("GAME_CONTRACT_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() public initializer {
        __ERC20_init("bonus", "XBON");
        __ERC20Burnable_init();
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(GAME_CONTRACT_ROLE, msg.sender);
    }

    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        // While depositing tokens also give the sender the permission to take
        _approve(to, _msgSender(), amount);
    }

    function takeFunds(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual returns (bool) {
        require(
            hasRole(GAME_CONTRACT_ROLE, msg.sender),
            "Only Game Contract can do transfers"
        );
        _transfer(sender, recipient, amount);
        return true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            hasRole(GAME_CONTRACT_ROLE, msg.sender) ||
                hasRole(MINTER_ROLE, msg.sender),
            "only approved games and contracts can make transfers"
        );
        super._beforeTokenTransfer(from, to, amount);
    }
}
