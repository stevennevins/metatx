// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/utils/Context.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract ContextTest is Ownable, ERC2771Context {
    constructor(address _forwarder) ERC2771Context(_forwarder) Ownable(msg.sender) {}

    function testFunction() external view {
        address sender = _msgSender();
        if (owner() != sender) revert OwnableInvalidOwner(sender);
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return super._msgData();
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return super._msgSender();
    }

    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }
}
