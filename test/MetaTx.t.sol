// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Forwarder} from "../src/Forwarder.sol";
import {Context} from "../src/Context.sol";
import {ERC2771Forwarder} from "@openzeppelin/metatx/ERC2771Forwarder.sol";

contract MetaTxTest is Test {
    Context internal context;
    Forwarder internal forwarder;
    function setUp() public {
        forwarder = new Forwarder();
        context = new Context(address(forwarder));
    }
}
