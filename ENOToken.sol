// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract ENOToken is ERC20, ERC20Permit {
    constructor() ERC20("ENOToken", "ENO") ERC20Permit("ENOToken") {
        _mint(msg.sender, 25000000 * 10 ** decimals());
    }
}