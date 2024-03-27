// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ENOToken is ERC20, ERC20Burnable, Ownable {
    address public _minter;
    bool public minterSetEnabled = true;

    constructor() ERC20("EnoToken", "ENO") Ownable(msg.sender) {}

    function setMinter(address minter) public onlyOwner {
        require(minterSetEnabled, "Setting minter is disabled");
        _minter = minter;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == _minter || msg.sender == owner(), "Caller is not authorized");
        _mint(to, amount);
    }

    function disableSetMinter() public onlyOwner {
        minterSetEnabled = false;
    }
}