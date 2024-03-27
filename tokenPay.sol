// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ENOToken.sol";

contract TokenPay is AccessControl, Ownable {

    ENOToken public token;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    constructor(ENOToken _token) Ownable(msg.sender) {
        token = _token;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MANAGER_ROLE, _msgSender());
    }

    function fakeMint(address _to, uint256 _amount) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Not allowed");
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal){
        token.transfer(_to, tokenBal);
        }
        else {
        token.transfer(_to, _amount);
        }
    } 
}