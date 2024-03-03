// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";

contract Context is ERC2771Context {
    constructor(address _forwarder) ERC2771Context(_forwarder) {}
}
