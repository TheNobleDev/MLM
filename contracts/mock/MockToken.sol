// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name) ERC20(name, name) {
        _mint(msg.sender, 1_000_000_000 * 10**18);
    }
}