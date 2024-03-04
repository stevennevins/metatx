// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Forwarder} from "../src/Forwarder.sol";
import {ContextTest} from "../src/ContextTest.sol";
import {LibZip} from "solady/utils/LibZip.sol";

contract MetaTxTest is Test {
    using LibZip for bytes;

    ContextTest internal context;
    Forwarder internal forwarder;
    function setUp() public {
        forwarder = new Forwarder();
        context = new ContextTest(address(forwarder));
    }

    function test_True() public {
        assertTrue(true);
    }

    function test_Init() public {
        assertTrue(forwarder.isTrustedByTarget(address(context)));
        assertEq(context.owner(), address(this));
    }

    function test_Naive() public {
        context.testFunction();
    }

    function test_RevertsWhen_NotOwner_Naive() public {
        vm.prank(address(420));
        vm.expectRevert();
        context.testFunction();
    }

    function test_Metatx() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotSignedByOwner_MetaTx() public {
        vm.skip(true);
    }

    function test_RevertsWhen_NotTrustedForwarder_MetaTx() public {
        Forwarder notTrusted = new Forwarder();
        vm.skip(true);
    }

    function test_NotZipped_Metatx() public {
        vm.skip(true);
    }
}
