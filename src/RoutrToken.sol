// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Routr Network
/// @notice Fixed-supply ERC-20. The deploying account receives every token exactly once.
contract RoutrToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Routr Network", "ROUTR") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
