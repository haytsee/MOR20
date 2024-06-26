// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETHMock is ERC20 {
    constructor() ERC20("WETH", "WETH") {}

    function mint(address account_, uint256 amount_) external {
        require(amount_ <= 1000000 * (10 ** decimals()), "WETHMock: amount is too big");

        _mint(account_, amount_);
    }
}
