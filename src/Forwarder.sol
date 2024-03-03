// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/utils/cryptography/EIP712.sol";
import {LibZip} from "solady/utils/LibZip.sol";

contract Forwarder is EIP712 {
    using LibZip for bytes;
    using ECDSA for bytes32;

    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    mapping(address => uint256) public nonces;

    address private constant DRY_RUN_ADDRESS = 0x0000000000000000000000000000000000000000;

    bytes32 private constant _TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    error InvalidRequest();

    error InvalidSignature();

    constructor() EIP712("Forwarder", "1") {}

    function execute(bytes calldata compressedData) external payable {
        bytes memory data = compressedData.flzDecompress();

        (ForwardRequest memory request, bytes memory sig) = abi.decode(data, (ForwardRequest, bytes));
        _execute(request, sig);
    }

    function _execute(ForwardRequest memory req, bytes memory signature) internal returns (bool, bytes memory) {
        if (!_verify(req, signature)) revert InvalidRequest();
        nonces[req.from] = req.nonce + 1;

        (bool success, bytes memory returndata) = req.to.call{gas: req.gas, value: req.value}(
            abi.encodePacked(req.data, req.from)
        );

        // Validate that the relayer has sent enough gas for the call.
        // See https://ronan.eth.limo/blog/ethereum-gas-dangers/
        if (gasleft() <= req.gas / 63) {
            // We explicitly trigger invalid opcode to consume all gas and bubble-up the effects, since
            // neither revert or assert consume all gas since Solidity 0.8.0
            // https://docs.soliditylang.org/en/v0.8.0/control-structures.html#panic-via-assert-and-error-via-require
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }

        return (success, returndata);
    }
    function _isTrustedByTarget(address target) internal view returns (bool) {
        bytes memory encodedParams = abi.encodeCall(ERC2771Context.isTrustedForwarder, (address(this)));

        bool success;
        uint256 returnSize;
        uint256 returnValue;
        /// @solidity memory-safe-assembly
        assembly {
            // Perform the staticcal and save the result in the scratch space.
            // | Location  | Content  | Content (Hex)                                                      |
            // |-----------|----------|--------------------------------------------------------------------|
            // |           |          |                                                           result ↓ |
            // | 0x00:0x1F | selector | 0x0000000000000000000000000000000000000000000000000000000000000001 |
            success := staticcall(gas(), target, add(encodedParams, 0x20), mload(encodedParams), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        return success && returnSize >= 0x20 && returnValue > 0;
    }

    function _verify(ForwardRequest memory req, bytes memory signature) internal view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_TYPEHASH, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data)))
        ).recover(signature);
        if (!(tx.origin == DRY_RUN_ADDRESS || signer == req.from)) revert InvalidSignature();

        return nonces[req.from] == req.nonce && _isTrustedByTarget(req.to);
    }
}
